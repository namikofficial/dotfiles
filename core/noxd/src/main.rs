use std::{
    env, fs,
    io::{Read, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

fn runtime_dir() -> PathBuf {
    PathBuf::from(env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into())).join("noxflow")
}

fn status_json() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!(
        r#"{{"schema":1,"daemon":"noxd","timestamp":{},"shell":"noxflow","providers":{{"hyprland":"pending","audio":"pending","network":"pending","battery":"pending","media":"pending"}}}}"#,
        now
    )
}

fn handle(mut stream: UnixStream) -> std::io::Result<()> {
    let mut request = String::new();
    stream.read_to_string(&mut request)?;
    let response = match request.trim() {
        "status" | "{\"method\":\"status\"}" => status_json(),
        "ping" => r#"{"ok":true,"daemon":"noxd"}"#.to_owned(),
        _ => r#"{"ok":false,"error":"unknown request"}"#.to_owned(),
    };
    stream.write_all(response.as_bytes())
}

fn main() -> std::io::Result<()> {
    let dir = runtime_dir();
    fs::create_dir_all(&dir)?;
    let socket = dir.join("noxd.sock");
    let _ = fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket)?;
    println!("noxd listening on {}", socket.display());
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let _ = handle(stream);
            }
            Err(error) => eprintln!("noxd client error: {error}"),
        }
    }
    Ok(())
}
