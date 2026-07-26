use noxflow_config::{ConfigLoader, env_profile_override, display_config};
use noxflow_ipc::{Request, RequestEnvelope, PROTOCOL_VERSION};
use std::{
    env,
    io::{Read, Write},
    net::Shutdown,
    os::unix::net::UnixStream,
    path::PathBuf,
    process::Command,
};

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
    eprintln!("usage: noxctl status | doctor | config | shell use <noxflow|wayle> | shell restart | shell safe-mode");
}

fn main() {
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
        [command] if command == "config" => {
            let mut loader = ConfigLoader::new();
            if let Some(profile) = env_profile_override() {
                loader = loader.with_profile(profile);
            }
            match loader.load()
            {
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
