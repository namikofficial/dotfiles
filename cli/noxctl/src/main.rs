use noxflow_config::{display_config, env_profile_override, ConfigLoader};
use noxflow_diagnostics::{install_panic_hook, sanitize};
use noxflow_ipc::{Request, RequestEnvelope, PROTOCOL_VERSION};
use std::{
    env,
    io::{Read, Write},
    net::Shutdown,
    os::unix::net::UnixStream,
    path::PathBuf,
    process::Command,
};

const JOURNALCTL: &str = "/usr/bin/journalctl";

fn socket() -> PathBuf {
    PathBuf::from(env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into()))
        .join("noxflow/noxd.sock")
}

fn daemon_request(request: &str) -> std::io::Result<String> {
    let mut stream = UnixStream::connect(socket())?;
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.shutdown(Shutdown::Write)?;
    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(response)
}

fn usage() {
    eprintln!("usage: noxctl status [hyprland] | doctor | config | logs [--follow] [--provider NAME] | shell use <noxflow|wayle> | shell restart | shell safe-mode");
}

fn valid_provider(provider: &str) -> bool {
    !provider.is_empty()
        && provider
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
}

fn journal_args(follow: bool, provider: Option<&str>) -> Result<Vec<String>, String> {
    if let Some(provider) = provider {
        if !valid_provider(provider) {
            return Err("invalid provider name".into());
        }
    }
    let mut args = vec![
        "--user".into(),
        "-u".into(),
        "noxd.service".into(),
        "--no-pager".into(),
        "-o".into(),
        "short-iso".into(),
    ];
    if follow {
        args.push("--follow".into());
    }
    Ok(args)
}

fn filter_provider_lines<'a>(
    lines: impl IntoIterator<Item = &'a str>,
    provider: &str,
) -> Vec<&'a str> {
    let json_marker = format!("\"provider\":\"{provider}\"");
    let field_marker = format!("provider={provider}");
    lines
        .into_iter()
        .filter(|line| line.contains(&json_marker) || line.contains(&field_marker))
        .collect()
}

fn run_logs(follow: bool, provider: Option<&str>) -> i32 {
    let args = match journal_args(follow, provider) {
        Ok(args) => args,
        Err(error) => {
            eprintln!("logs: {error}");
            return 2;
        }
    };
    let output = Command::new(JOURNALCTL).args(&args).output();
    let output = match output {
        Ok(output) => output,
        Err(error) => {
            eprintln!("unable to run journalctl: {}", sanitize(&error.to_string()));
            return 1;
        }
    };
    let text = String::from_utf8_lossy(&output.stdout);
    if let Some(provider) = provider {
        for line in filter_provider_lines(text.lines(), provider) {
            println!("{line}");
        }
    } else {
        print!("{text}");
    }
    if !output.status.success() {
        eprint!("{}", String::from_utf8_lossy(&output.stderr));
    }
    output.status.code().unwrap_or(1)
}

fn main() {
    install_panic_hook("noxctl");
    let args: Vec<String> = env::args().skip(1).collect();
    match args.as_slice() {
        [command] if command == "status" => {
            let request = RequestEnvelope {
                protocol_version: PROTOCOL_VERSION,
                request_id: "noxctl-status".into(),
                request: Request::GetState,
            };
            let request = serde_json::to_string(&request).expect("IPC request serializes");
            match daemon_request(&request) {
                Ok(response) => println!("{response}"),
                Err(error) => {
                    eprintln!("noxd unavailable: {error}");
                    std::process::exit(1);
                }
            }
        }
        [command, provider] if command == "status" && provider == "hyprland" => {
            let request = RequestEnvelope {
                protocol_version: PROTOCOL_VERSION,
                request_id: "noxctl-status-hyprland".into(),
                request: Request::GetProviderState {
                    provider: provider.into(),
                },
            };
            let request = serde_json::to_string(&request).expect("IPC request serializes");
            match daemon_request(&request) {
                Ok(response) => println!("{response}"),
                Err(error) => {
                    eprintln!("noxd unavailable: {error}");
                    std::process::exit(1);
                }
            }
        }
        [command] if command == "config" => {
            let mut loader = ConfigLoader::new();
            if let Some(profile) = env_profile_override() {
                loader = loader.with_profile(profile);
            }
            match loader.load() {
                Ok(cfg) => {
                    println!("{}", display_config(&cfg));
                }
                Err(errors) => {
                    for error in &errors {
                        eprintln!("config error: {error}");
                    }
                    std::process::exit(1);
                }
            }
        }
        [command] if command == "doctor" => {
            println!("noxflow doctor");
            println!("  runtime socket: {}", socket().display());
            println!("  shell fallback: available through panel-switch.sh wayle");
        }
        [command] if command == "logs" => std::process::exit(run_logs(false, None)),
        [command, option] if command == "logs" && option == "--follow" => {
            std::process::exit(run_logs(true, None))
        }
        [command, follow, option, provider]
            if command == "logs" && follow == "--follow" && option == "--provider" =>
        {
            std::process::exit(run_logs(true, Some(provider)))
        }
        [command, option, provider] if command == "logs" && option == "--provider" => {
            std::process::exit(run_logs(false, Some(provider)))
        }
        [shell, action, target]
            if shell == "shell"
                && action == "use"
                && (target == "noxflow" || target == "wayle") =>
        {
            let script = env::var_os("NOXFLOW_PANEL_SWITCH").unwrap_or_else(|| {
                PathBuf::from(env::var_os("XDG_CONFIG_HOME").unwrap_or_else(|| {
                    PathBuf::from(env::var_os("HOME").unwrap_or_default())
                        .join(".config")
                        .into_os_string()
                }))
                .join("hypr/scripts/panel-switch.sh")
                .into_os_string()
            });
            let status = Command::new(script).arg(target).status();
            match status {
                Ok(status) if status.success() => println!("shell switched to {target}"),
                Ok(status) => std::process::exit(status.code().unwrap_or(1)),
                Err(error) => {
                    eprintln!("unable to switch shell: {error}");
                    std::process::exit(1);
                }
            }
        }
        [shell, action] if shell == "shell" && (action == "restart" || action == "safe-mode") => {
            eprintln!("shell {action} is reserved for the session integration sprint");
            std::process::exit(2);
        }
        _ => {
            usage();
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_names_are_restricted() {
        assert!(valid_provider("hyprland"));
        assert!(!valid_provider("hyprland; rm -rf /"));
        assert!(!valid_provider(""));
    }

    #[test]
    fn journal_command_is_fixed() {
        assert_eq!(
            journal_args(false, Some("hyprland")).unwrap(),
            vec![
                "--user",
                "-u",
                "noxd.service",
                "--no-pager",
                "-o",
                "short-iso"
            ]
        );
        assert!(journal_args(false, Some("bad name")).is_err());
    }

    #[test]
    fn provider_filter_matches_only_provider_field() {
        let lines = [
            "2026-07-27 noxd[1]: {\"provider\":\"hyprland\",\"event\":\"failure\"}",
            "2026-07-27 noxd[1]: {\"provider\":\"audio\",\"message\":\"hyprland failed\"}",
        ];
        assert_eq!(filter_provider_lines(lines, "hyprland").len(), 1);
    }
}
