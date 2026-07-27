use clap::{CommandFactory, Parser, Subcommand, ValueEnum};
use clap_complete::{
    generate,
    shells::{Bash, Fish, Zsh},
};
use noxflow_config::{display_config, resolve_config_dir, ConfigLoader};
use noxflow_diagnostics::{install_panic_hook, sanitize};
use noxflow_ipc::{
    Action, AudioTarget, ErrorCode, Request, RequestEnvelope, Response, ResponseEnvelope, State,
    PROTOCOL_VERSION,
};
use serde_json::Value;
use std::{
    env, fs,
    io::{self, Read, Write},
    net::Shutdown,
    os::unix::net::UnixStream,
    path::PathBuf,
    process::Command,
    time::Duration,
};

const JOURNALCTL: &str = "/usr/bin/journalctl";
const DEFAULT_TIMEOUT_MS: u64 = 2_000;

#[derive(Parser, Debug)]
#[command(
    name = "noxctl",
    version,
    about = "Control the NoxFlow desktop daemon",
    arg_required_else_help = true
)]
struct Cli {
    #[arg(long, global = true, help = "Emit machine-readable JSON")]
    json: bool,
    #[arg(
        long,
        global = true,
        value_name = "PATH",
        help = "Override the NoxFlow IPC socket"
    )]
    socket: Option<PathBuf>,
    #[arg(long, global = true, default_value_t = DEFAULT_TIMEOUT_MS, value_name = "MILLISECONDS", help = "IPC timeout")]
    timeout_ms: u64,
    #[command(subcommand)]
    command: CommandGroup,
}

#[derive(Subcommand, Debug)]
enum CommandGroup {
    Status {
        provider: Option<String>,
    },
    Provider {
        #[command(subcommand)]
        command: ProviderCommand,
    },
    Audio {
        #[command(subcommand)]
        command: AudioCommand,
    },
    Brightness {
        #[command(subcommand)]
        command: BrightnessCommand,
    },
    Power {
        #[command(subcommand)]
        command: PowerCommand,
    },
    Network {
        #[command(subcommand)]
        command: NetworkCommand,
    },
    Bluetooth {
        #[command(subcommand)]
        command: BluetoothCommand,
    },
    Media {
        #[command(subcommand)]
        command: MediaCommand,
    },
    Shell {
        #[command(subcommand)]
        command: ShellCommand,
    },
    Profile {
        #[command(subcommand)]
        command: ProfileCommand,
    },
    Config {
        #[arg(long)]
        profile: Option<String>,
    },
    Logs {
        #[arg(long)]
        follow: bool,
        #[arg(long)]
        provider: Option<String>,
    },
    Doctor,
    Completions {
        shell: CompletionShell,
    },
}

#[derive(Subcommand, Debug)]
enum ProviderCommand {
    List,
    Status { provider: String },
}
#[derive(Subcommand, Debug)]
enum AudioCommand {
    Status,
    Volume {
        value: String,
    },
    Mute {
        #[command(subcommand)]
        command: ToggleCommand,
    },
    Mic {
        #[command(subcommand)]
        command: ToggleCommand,
    },
    Default {
        target: AudioTargetArg,
        selector: String,
    },
}
#[derive(Subcommand, Debug)]
enum ToggleCommand {
    Toggle,
}
#[derive(Subcommand, Debug)]
enum BrightnessCommand {
    Status,
    Set { percentage: u8 },
    Adjust { delta: i16 },
}
#[derive(Subcommand, Debug)]
enum PowerCommand {
    Status,
    Profile {
        #[command(subcommand)]
        command: PowerProfileCommand,
    },
}
#[derive(Subcommand, Debug)]
enum PowerProfileCommand {
    List,
    Set { profile: String },
}
#[derive(Subcommand, Debug)]
enum NetworkCommand {
    Status,
    Wifi { action: WifiAction },
    Connect { uuid: String },
    Disconnect,
    Refresh,
    Vpn { action: WifiAction, uuid: String },
}
#[derive(ValueEnum, Clone, Debug)]
enum WifiAction {
    Enable,
    Disable,
}
#[derive(Subcommand, Debug)]
enum BluetoothCommand {
    Status,
    Power { action: BluetoothPower },
    Discover { action: DiscoverAction },
    Connect { address: String },
    Disconnect { address: String },
    Trust { address: String },
    Untrust { address: String },
}
#[derive(ValueEnum, Clone, Debug)]
enum BluetoothPower {
    On,
    Off,
}
#[derive(ValueEnum, Clone, Debug)]
enum DiscoverAction {
    Start,
    Stop,
}
#[derive(Subcommand, Debug)]
enum MediaCommand {
    Status,
    Play,
    Pause,
    PlayPause,
    Previous,
    Next,
    Seek {
        seconds: f64,
    },
    Player {
        #[command(subcommand)]
        command: PlayerCommand,
    },
}
#[derive(Subcommand, Debug)]
enum PlayerCommand {
    List,
    Select { player: String },
}
#[derive(Subcommand, Debug)]
enum ShellCommand {
    Status,
    Use { shell: ShellName },
    Restart,
    SafeMode,
    Toggle { target: ShellTarget },
}
#[derive(ValueEnum, Clone, Debug)]
enum ShellName {
    Noxflow,
    Wayle,
}
#[derive(ValueEnum, Clone, Debug)]
enum ShellTarget {
    ControlCenter,
    Panel,
    Notifications,
}
#[derive(Subcommand, Debug)]
enum ProfileCommand {
    List,
    Show { name: Option<String> },
    Current,
    Use { name: String },
}
#[derive(ValueEnum, Clone, Debug)]
enum CompletionShell {
    Bash,
    Zsh,
    Fish,
}
#[derive(ValueEnum, Clone, Debug)]
enum AudioTargetArg {
    Output,
    Input,
}

#[derive(Debug)]
enum CliError {
    Usage(String),
    Unavailable(String),
    Timeout,
    Protocol(String),
    Daemon(String),
    Local(String),
}
impl CliError {
    fn code(&self) -> i32 {
        match self {
            Self::Usage(_) => 2,
            Self::Protocol(_) => 3,
            _ => 1,
        }
    }
    fn message(&self) -> String {
        match self {
            Self::Usage(s)
            | Self::Unavailable(s)
            | Self::Protocol(s)
            | Self::Daemon(s)
            | Self::Local(s) => s.clone(),
            Self::Timeout => "noxd request timed out".into(),
        }
    }
}

struct Client {
    socket: PathBuf,
    timeout: Duration,
}
impl Client {
    fn request(&self, request: Request, id: &str) -> Result<Response, CliError> {
        let envelope = RequestEnvelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: id.into(),
            request,
        };
        let payload = serde_json::to_vec(&envelope).map_err(|e| CliError::Local(e.to_string()))?;
        let socket = self.socket.clone();
        let timeout = self.timeout;
        let (sender, receiver) = std::sync::mpsc::sync_channel(1);
        std::thread::spawn(move || {
            let _ = sender.send(UnixStream::connect(socket));
        });
        let mut stream = match receiver.recv_timeout(timeout) {
            Ok(Ok(stream)) => stream,
            Ok(Err(e)) => {
                return Err(CliError::Unavailable(format!(
                    "noxd unavailable at {}: {}",
                    self.socket.display(),
                    sanitize(&e.to_string())
                )))
            }
            Err(_) => return Err(CliError::Timeout),
        };
        stream
            .set_read_timeout(Some(self.timeout))
            .map_err(|e| CliError::Local(e.to_string()))?;
        stream
            .set_write_timeout(Some(self.timeout))
            .map_err(|e| CliError::Local(e.to_string()))?;
        stream
            .write_all(&payload)
            .map_err(|e| CliError::Unavailable(sanitize(&e.to_string())))?;
        stream
            .write_all(b"\n")
            .map_err(|e| CliError::Unavailable(sanitize(&e.to_string())))?;
        stream.shutdown(Shutdown::Write).ok();
        let mut response = String::new();
        stream.read_to_string(&mut response).map_err(|e| {
            if matches!(
                e.kind(),
                io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
            ) {
                CliError::Timeout
            } else {
                CliError::Unavailable(sanitize(&e.to_string()))
            }
        })?;
        let response: ResponseEnvelope = serde_json::from_str(response.trim())
            .map_err(|e| CliError::Protocol(format!("invalid response from noxd: {e}")))?;
        if response.protocol_version != PROTOCOL_VERSION {
            return Err(CliError::Protocol(format!(
                "protocol mismatch: noxctl supports {PROTOCOL_VERSION}, daemon responded with {}",
                response.protocol_version
            )));
        }
        if let Some(error) = response.error {
            if error.code == ErrorCode::UnsupportedProtocolVersion {
                return Err(CliError::Protocol(format!(
                    "protocol mismatch: {}",
                    error.message
                )));
            }
            return Err(CliError::Daemon(format!(
                "{} ({:?})",
                error.message, error.code
            )));
        }
        response.result.ok_or_else(|| {
            CliError::Protocol("daemon returned neither a result nor an error".into())
        })
    }
}

fn client(cli: &Cli) -> Client {
    Client {
        socket: cli
            .socket
            .clone()
            .unwrap_or_else(noxflow_config::default_socket_path),
        timeout: Duration::from_millis(cli.timeout_ms.max(1)),
    }
}
fn validate_uuid(s: &str) -> Result<(), CliError> {
    if s.len() == 36
        && s.bytes()
            .enumerate()
            .all(|(i, b)| b.is_ascii_hexdigit() || matches!(i, 8 | 13 | 18 | 23) && b == b'-')
    {
        Ok(())
    } else {
        Err(CliError::Usage("value must be a valid UUID".into()))
    }
}
fn validate_address(s: &str) -> Result<String, CliError> {
    let p: Vec<_> = s.split(':').collect();
    if p.len() == 6
        && p.iter()
            .all(|x| x.len() == 2 && x.bytes().all(|b| b.is_ascii_hexdigit()))
    {
        Ok(s.to_ascii_uppercase())
    } else {
        Err(CliError::Usage(
            "value must be a valid Bluetooth address".into(),
        ))
    }
}
fn validate_name(s: &str) -> Result<(), CliError> {
    if !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-' | b'.'))
    {
        Ok(())
    } else {
        Err(CliError::Usage(
            "name contains unsupported characters".into(),
        ))
    }
}
fn action(c: &Client, a: Action, id: &str) -> Result<Response, CliError> {
    c.request(Request::RunAction { action: a }, id)
}

fn response_json(response: &Response) -> Value {
    serde_json::to_value(response).unwrap_or(Value::Null)
}
fn provider_data(response: &Response) -> Value {
    match response {
        Response::ProviderState(s) => serde_json::to_value(s).unwrap_or(Value::Null),
        Response::State(s) => serde_json::to_value(s).unwrap_or(Value::Null),
        _ => response_json(response),
    }
}
fn print_response(response: &Response, json: bool) {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&provider_data(response)).unwrap()
        );
        return;
    }
    match response {
        Response::State(State {
            timestamp,
            providers,
            ..
        }) => {
            println!("NoxFlow status (timestamp {timestamp})");
            for (name, p) in providers {
                println!("  {name:<12} {:?}", p.status);
            }
        }
        Response::ProviderState(p) => {
            println!("{}: {:?}", p.provider, p.status);
            for (k, v) in &p.data {
                println!("  {k}: {v}");
            }
        }
        Response::ActionAccepted(a) => println!("accepted: {:?}", a.action),
        Response::Version(v) => println!(
            "noxd {} (protocol {})",
            v.daemon_version, v.protocol_version
        ),
        Response::Pong => println!("ok"),
        other => println!(
            "{}",
            serde_json::to_string_pretty(&response_json(other)).unwrap()
        ),
    }
}
fn run_request(c: &Client, request: Request, id: &str, json: bool) -> Result<(), CliError> {
    print_response(&c.request(request, id)?, json);
    Ok(())
}

fn parse_volume(value: &str) -> Result<Action, CliError> {
    if let Some(rest) = value.strip_prefix('+').or_else(|| value.strip_prefix('-')) {
        let n: i16 = rest
            .parse()
            .map_err(|_| CliError::Usage("volume adjustment must be an integer".into()))?;
        if n == 0 || n > 100 {
            return Err(CliError::Usage(
                "volume adjustment must be between 1 and 100".into(),
            ));
        };
        return Ok(Action::AudioAdjustVolume {
            target: AudioTarget::Output,
            delta: if value.starts_with('-') { -n } else { n },
        });
    };
    let n = value
        .parse::<u8>()
        .map_err(|_| CliError::Usage("volume must be 0-255 or a signed adjustment".into()))?;
    Ok(Action::AudioSetVolume {
        target: AudioTarget::Output,
        volume: n,
    })
}
fn parse_seek(seconds: f64) -> Result<i64, CliError> {
    if !seconds.is_finite() || seconds.abs() > 86_400.0 {
        Err(CliError::Usage(
            "seek must be finite and within one day".into(),
        ))
    } else {
        Ok((seconds * 1_000_000.0).round() as i64)
    }
}

fn run_logs(follow: bool, provider: Option<&str>, json: bool) -> Result<(), CliError> {
    if let Some(p) = provider {
        validate_name(p)?;
    }
    let mut args = vec![
        "--user",
        "-u",
        "noxd.service",
        "--no-pager",
        "-o",
        if json { "json" } else { "short-iso" },
    ];
    if follow {
        args.push("--follow")
    };
    let out = Command::new(JOURNALCTL).args(args).output().map_err(|e| {
        CliError::Local(format!(
            "unable to run journalctl: {}",
            sanitize(&e.to_string())
        ))
    })?;
    let text = String::from_utf8_lossy(&out.stdout);
    let lines = text.lines().filter(|line| {
        provider
            .map(|p| {
                line.contains(&format!("\"provider\":\"{p}\""))
                    || line.contains(&format!("provider={p}"))
            })
            .unwrap_or(true)
    });
    for line in lines {
        println!("{line}");
    }
    if !out.status.success() {
        return Err(CliError::Local(
            String::from_utf8_lossy(&out.stderr).trim().to_owned(),
        ));
    }
    Ok(())
}

fn config_for(profile: Option<String>) -> Result<noxflow_config::Config, CliError> {
    let loader = profile
        .map(|p| ConfigLoader::new().with_profile(p))
        .unwrap_or_else(ConfigLoader::new);
    loader.load().map_err(|e| {
        CliError::Local(
            e.iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join("\n"),
        )
    })
}
fn profile_names() -> Result<Vec<String>, CliError> {
    let dir = resolve_config_dir().join("profiles");
    let mut names = Vec::new();
    if dir.exists() {
        for e in fs::read_dir(dir).map_err(|e| CliError::Local(e.to_string()))? {
            let p = e.map_err(|e| CliError::Local(e.to_string()))?.path();
            if p.extension().and_then(|x| x.to_str()) == Some("toml") {
                if let Some(n) = p.file_stem().and_then(|x| x.to_str()) {
                    names.push(n.to_owned())
                }
            }
        }
    }
    names.sort();
    Ok(names)
}
fn activate_profile(name: &str) -> Result<(), CliError> {
    validate_name(name)?;
    let dir = resolve_config_dir();
    fs::create_dir_all(&dir).map_err(|e| CliError::Local(e.to_string()))?;
    let path = dir.join("config.toml");
    let mut table: toml::Table = fs::read_to_string(&path)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or_default();
    table.insert("profile".into(), toml::Value::String(name.into()));
    let text = toml::to_string_pretty(&toml::Value::Table(table))
        .map_err(|e| CliError::Local(e.to_string()))?;
    let tmp = path.with_extension("toml.tmp");
    fs::write(&tmp, text).map_err(|e| CliError::Local(e.to_string()))?;
    fs::rename(tmp, path).map_err(|e| CliError::Local(e.to_string()))
}

fn shell_script() -> PathBuf {
    env::var_os("NOXFLOW_PANEL_SWITCH")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".config")
                })
                .join("hypr/scripts/panel-switch.sh")
        })
}
fn shell_command(command: &ShellCommand) -> Result<(), CliError> {
    let (program, args): (PathBuf, Vec<&str>) = match command {
        ShellCommand::Use {
            shell: ShellName::Wayle,
        } => (shell_script(), vec!["wayle"]),
        ShellCommand::Use {
            shell: ShellName::Noxflow,
        } => {
            return Err(CliError::Daemon(
                "NoxFlow shell activation is not installed in this session".into(),
            ))
        }
        ShellCommand::Toggle {
            target: ShellTarget::Panel,
        } => (shell_script(), vec!["toggle-view"]),
        ShellCommand::Toggle {
            target: ShellTarget::ControlCenter,
        } => (
            PathBuf::from("/usr/bin/systemctl"),
            vec!["--user", "start", "noxflow-control-center.service"],
        ),
        ShellCommand::Toggle {
            target: ShellTarget::Notifications,
        } => (
            PathBuf::from("/usr/bin/systemctl"),
            vec!["--user", "start", "noxflow-notifications.service"],
        ),
        ShellCommand::Restart => (
            PathBuf::from("/usr/bin/systemctl"),
            vec!["--user", "restart", "noxflow-session-optional.service"],
        ),
        ShellCommand::SafeMode => (
            PathBuf::from("/usr/bin/systemctl"),
            vec!["--user", "restart", "noxflow-session-optional.service"],
        ),
        ShellCommand::Status => return Ok(()),
    };
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|e| CliError::Local(sanitize(&e.to_string())))?;
    if status.success() {
        Ok(())
    } else {
        Err(CliError::Local(format!(
            "shell operation failed with {}",
            status
        )))
    }
}

fn execute(cli: Cli) -> Result<(), CliError> {
    let c = client(&cli);
    match cli.command {
        CommandGroup::Completions { shell } => {
            let mut cmd = Cli::command();
            match shell {
                CompletionShell::Bash => generate(Bash, &mut cmd, "noxctl", &mut io::stdout()),
                CompletionShell::Zsh => generate(Zsh, &mut cmd, "noxctl", &mut io::stdout()),
                CompletionShell::Fish => generate(Fish, &mut cmd, "noxctl", &mut io::stdout()),
            };
            Ok(())
        }
        CommandGroup::Status { provider } => run_request(
            &c,
            provider
                .map(|p| Request::GetProviderState { provider: p })
                .unwrap_or(Request::GetState),
            "status",
            cli.json,
        ),
        CommandGroup::Provider { command } => match command {
            ProviderCommand::List => run_request(&c, Request::GetState, "provider-list", cli.json),
            ProviderCommand::Status { provider } => {
                validate_name(&provider)?;
                run_request(
                    &c,
                    Request::GetProviderState { provider },
                    "provider-status",
                    cli.json,
                )
            }
        },
        CommandGroup::Audio { command } => {
            let r = match command {
                AudioCommand::Status => {
                    return run_request(
                        &c,
                        Request::GetProviderState {
                            provider: "audio".into(),
                        },
                        "audio-status",
                        cli.json,
                    )
                }
                AudioCommand::Volume { value } => parse_volume(&value)?,
                AudioCommand::Mute {
                    command: ToggleCommand::Toggle,
                } => Action::AudioToggleMute {
                    target: AudioTarget::Output,
                },
                AudioCommand::Mic {
                    command: ToggleCommand::Toggle,
                } => Action::AudioToggleMute {
                    target: AudioTarget::Input,
                },
                AudioCommand::Default { target, selector } => {
                    if selector.is_empty() {
                        return Err(CliError::Usage("selector cannot be empty".into()));
                    };
                    Action::AudioSetDefault {
                        target: match target {
                            AudioTargetArg::Output => AudioTarget::Output,
                            AudioTargetArg::Input => AudioTarget::Input,
                        },
                        selector,
                    }
                }
            };
            let x = action(&c, r, "audio-action")?;
            print_response(&x, cli.json);
            Ok(())
        }
        CommandGroup::Brightness { command } => {
            let r = match command {
                BrightnessCommand::Status => {
                    return run_request(
                        &c,
                        Request::GetProviderState {
                            provider: "brightness".into(),
                        },
                        "brightness-status",
                        cli.json,
                    )
                }
                BrightnessCommand::Set { percentage } => Action::BrightnessSet { percentage },
                BrightnessCommand::Adjust { delta } => {
                    if delta == 0 {
                        return Err(CliError::Usage(
                            "brightness adjustment cannot be zero".into(),
                        ));
                    };
                    Action::BrightnessAdjust { delta }
                }
            };
            let x = action(&c, r, "brightness-action")?;
            print_response(&x, cli.json);
            Ok(())
        }
        CommandGroup::Power { command } => match command {
            PowerCommand::Status => run_request(
                &c,
                Request::GetProviderState {
                    provider: "power".into(),
                },
                "power-status",
                cli.json,
            ),
            PowerCommand::Profile {
                command: PowerProfileCommand::List,
            } => run_request(
                &c,
                Request::GetProviderState {
                    provider: "power".into(),
                },
                "power-profile-list",
                cli.json,
            ),
            PowerCommand::Profile {
                command: PowerProfileCommand::Set { profile },
            } => {
                validate_name(&profile)?;
                let x = action(&c, Action::PowerProfileSet { profile }, "power-profile-set")?;
                print_response(&x, cli.json);
                Ok(())
            }
        },
        CommandGroup::Network { command } => {
            let r = match command {
                NetworkCommand::Status => {
                    return run_request(
                        &c,
                        Request::GetProviderState {
                            provider: "network".into(),
                        },
                        "network-status",
                        cli.json,
                    )
                }
                NetworkCommand::Wifi { action } => Action::NetworkWifiSetEnabled {
                    enabled: matches!(action, WifiAction::Enable),
                },
                NetworkCommand::Connect { uuid } => {
                    validate_uuid(&uuid)?;
                    Action::NetworkConnectSaved { uuid }
                }
                NetworkCommand::Disconnect => Action::NetworkDisconnectWifi,
                NetworkCommand::Refresh => Action::NetworkRefresh,
                NetworkCommand::Vpn { action, uuid } => {
                    validate_uuid(&uuid)?;
                    Action::NetworkVpnSetEnabled {
                        uuid,
                        enabled: matches!(action, WifiAction::Enable),
                    }
                }
            };
            let x = action(&c, r, "network-action")?;
            print_response(&x, cli.json);
            Ok(())
        }
        CommandGroup::Bluetooth { command } => {
            let r = match command {
                BluetoothCommand::Status => {
                    return run_request(
                        &c,
                        Request::GetProviderState {
                            provider: "bluetooth".into(),
                        },
                        "bluetooth-status",
                        cli.json,
                    )
                }
                BluetoothCommand::Power { action } => Action::BluetoothSetPowered {
                    powered: matches!(action, BluetoothPower::On),
                },
                BluetoothCommand::Discover { action } => Action::BluetoothSetDiscovering {
                    discovering: matches!(action, DiscoverAction::Start),
                },
                BluetoothCommand::Connect { address } => Action::BluetoothConnect {
                    device_id: validate_address(&address)?,
                },
                BluetoothCommand::Disconnect { address } => Action::BluetoothDisconnect {
                    device_id: validate_address(&address)?,
                },
                BluetoothCommand::Trust { address } => Action::BluetoothSetTrusted {
                    device_id: validate_address(&address)?,
                    trusted: true,
                },
                BluetoothCommand::Untrust { address } => Action::BluetoothSetTrusted {
                    device_id: validate_address(&address)?,
                    trusted: false,
                },
            };
            let x = action(&c, r, "bluetooth-action")?;
            print_response(&x, cli.json);
            Ok(())
        }
        CommandGroup::Media { command } => {
            let r = match command {
                MediaCommand::Status => {
                    return run_request(
                        &c,
                        Request::GetProviderState {
                            provider: "media".into(),
                        },
                        "media-status",
                        cli.json,
                    )
                }
                MediaCommand::Play => Action::MediaPlay,
                MediaCommand::Pause => Action::MediaPause,
                MediaCommand::PlayPause => Action::MediaPlayPause,
                MediaCommand::Previous => Action::MediaPrevious,
                MediaCommand::Next => Action::MediaNext,
                MediaCommand::Seek { seconds } => Action::MediaSeek {
                    offset_us: parse_seek(seconds)?,
                },
                MediaCommand::Player {
                    command: PlayerCommand::List,
                } => {
                    return run_request(
                        &c,
                        Request::GetProviderState {
                            provider: "media".into(),
                        },
                        "media-player-list",
                        cli.json,
                    )
                }
                MediaCommand::Player {
                    command: PlayerCommand::Select { player },
                } => {
                    validate_name(&player)?;
                    Action::MediaSelectPlayer { player }
                }
            };
            let x = action(&c, r, "media-action")?;
            print_response(&x, cli.json);
            Ok(())
        }
        CommandGroup::Shell { command } => {
            if matches!(command, ShellCommand::Status) {
                println!("shell script: {}", shell_script().display());
                return Ok(());
            }
            shell_command(&command)
        }
        CommandGroup::Profile { command } => match command {
            ProfileCommand::List => {
                let names = profile_names()?;
                if cli.json {
                    println!("{}", serde_json::to_string_pretty(&names).unwrap())
                } else {
                    for n in names {
                        println!("{n}")
                    }
                }
                Ok(())
            }
            ProfileCommand::Current => {
                let cfg = config_for(None)?;
                let value = cfg.profile.unwrap_or_else(|| "(none)".into());
                if cli.json {
                    println!("{}", serde_json::json!({"profile":value}))
                } else {
                    println!("{value}")
                }
                Ok(())
            }
            ProfileCommand::Show { name } => {
                let cfg = config_for(name)?;
                if cli.json {
                    println!("{}", display_config(&cfg))
                } else {
                    println!("{}", display_config(&cfg))
                }
                Ok(())
            }
            ProfileCommand::Use { name } => {
                activate_profile(&name)?;
                let x = action(
                    &c,
                    Action::SetProfile {
                        profile: name.clone(),
                    },
                    "profile-use",
                );
                match x {
                    Ok(r) => print_response(&r, cli.json),
                    Err(CliError::Unavailable(_)) => {}
                    Err(e) => return Err(e),
                };
                if !cli.json {
                    println!("profile activated: {name}")
                }
                Ok(())
            }
        },
        CommandGroup::Config { profile } => {
            let cfg = config_for(profile)?;
            if cli.json {
                println!("{}", display_config(&cfg))
            } else {
                println!("{}", display_config(&cfg))
            }
            Ok(())
        }
        CommandGroup::Logs { follow, provider } => run_logs(follow, provider.as_deref(), cli.json),
        CommandGroup::Doctor => {
            let version = c.request(Request::GetVersion, "doctor-version")?;
            print_response(&version, cli.json);
            println!("socket: {}", c.socket.display());
            println!("config: {}", resolve_config_dir().display());
            Ok(())
        }
    }
}

fn main() {
    install_panic_hook("noxctl");
    let cli = Cli::parse();
    if let Err(e) = execute(cli) {
        eprintln!("noxctl: {}", e.message());
        std::process::exit(e.code())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn uuid_validation_is_strict() {
        assert!(validate_uuid("01234567-89ab-cdef-0123-456789abcdef").is_ok());
        assert!(validate_uuid("not uuid").is_err());
    }
    #[test]
    fn address_validation_is_strict() {
        assert_eq!(
            validate_address("aa:bb:cc:dd:ee:ff").unwrap(),
            "AA:BB:CC:DD:EE:FF"
        );
        assert!(validate_address("bad").is_err());
    }
    #[test]
    fn volume_and_seek_are_bounded() {
        assert!(matches!(
            parse_volume("+5"),
            Ok(Action::AudioAdjustVolume { delta: 5, .. })
        ));
        assert!(parse_volume("+0").is_err());
        assert_eq!(parse_seek(-1.5).unwrap(), -1_500_000);
        assert!(parse_seek(f64::NAN).is_err());
    }
}
