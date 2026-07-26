use noxflow_ipc::{
    decode_request, ActionAccepted, DecodeError, ErrorCode, IpcError, ProviderState,
    ProviderStatus, Request, Response, ResponseEnvelope, State, VersionInfo, PROTOCOL_VERSION,
    SOCKET_DIRECTORY, SOCKET_NAME, SUPPORTED_PROTOCOL_VERSIONS,
};
use serde_json::json;
use std::{
    collections::BTreeMap,
    env, fs,
    io::{self, BufRead, BufReader, Write},
    os::unix::{
        fs::{FileTypeExt, MetadataExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const MAX_FRAME_BYTES: usize = 64 * 1024;
const ACCEPT_POLL_INTERVAL: Duration = Duration::from_millis(50);
const CLIENT_READ_TIMEOUT: Duration = Duration::from_secs(5);

fn timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn log_event(
    level: &str,
    event: &str,
    socket: Option<&Path>,
    request_id: Option<&str>,
    error: Option<&str>,
) {
    let mut value = json!({
        "timestamp": timestamp(),
        "level": level,
        "event": event,
        "component": "noxd",
        "pid": std::process::id(),
    });
    if let Some(socket) = socket {
        value["socket"] = json!(socket.display().to_string());
    }
    if let Some(request_id) = request_id {
        value["request_id"] = json!(request_id);
    }
    if let Some(error) = error {
        value["error"] = json!(error);
    }
    eprintln!("{value}");
}

fn current_uid() -> u32 {
    unsafe { libc::geteuid() }
}

fn validate_directory(path: &Path, uid: u32, require_private: bool) -> io::Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_dir() || metadata.uid() != uid {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("unsafe runtime directory: {}", path.display()),
        ));
    }
    if require_private && metadata.mode() & 0o077 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("runtime directory is not private: {}", path.display()),
        ));
    }
    if metadata.mode() & 0o022 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!(
                "runtime directory is writable by other users: {}",
                path.display()
            ),
        ));
    }
    Ok(())
}

fn socket_path() -> io::Result<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "XDG_RUNTIME_DIR is required"))?;
    if !runtime.is_absolute()
        || runtime
            .components()
            .any(|c| matches!(c, std::path::Component::ParentDir))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "XDG_RUNTIME_DIR must be a safe absolute path",
        ));
    }
    let uid = current_uid();
    validate_directory(&runtime, uid, false)?;
    let directory = runtime.join(SOCKET_DIRECTORY);
    match fs::symlink_metadata(&directory) {
        Ok(_) => validate_directory(&directory, uid, true)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            fs::create_dir(&directory)?;
            fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))?;
            validate_directory(&directory, uid, true)?;
        }
        Err(error) => return Err(error),
    }
    Ok(directory.join(SOCKET_NAME))
}

fn prepare_socket(path: &Path) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if !metadata.file_type().is_socket() {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    format!("unexpected socket path: {}", path.display()),
                ));
            }
            if metadata.uid() != current_uid() {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "socket is owned by another user",
                ));
            }
            match UnixStream::connect(path) {
                Ok(_) => {
                    return Err(io::Error::new(
                        io::ErrorKind::AlreadyExists,
                        "noxd is already running",
                    ))
                }
                Err(error) if error.kind() == io::ErrorKind::ConnectionRefused => {
                    fs::remove_file(path)?
                }
                Err(error) => {
                    return Err(io::Error::new(
                        error.kind(),
                        format!("cannot verify existing socket: {error}"),
                    ))
                }
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    Ok(())
}

fn response(request_id: String, result: Response) -> ResponseEnvelope {
    ResponseEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id,
        result: Some(result),
        error: None,
    }
}

fn error_response(request_id: String, error: IpcError) -> ResponseEnvelope {
    ResponseEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id,
        result: None,
        error: Some(error),
    }
}

fn state() -> State {
    let providers = ["hyprland", "audio", "network", "battery", "media"]
        .into_iter()
        .map(|provider| {
            (
                provider.to_owned(),
                ProviderState {
                    provider: provider.to_owned(),
                    status: ProviderStatus::Pending,
                    data: BTreeMap::new(),
                },
            )
        })
        .collect();
    State {
        timestamp: timestamp(),
        providers,
        settings: BTreeMap::new(),
    }
}

fn handle_request(request: Request) -> Response {
    match request {
        Request::Ping => Response::Pong,
        Request::GetVersion => Response::Version(VersionInfo {
            daemon_version: env!("CARGO_PKG_VERSION").to_owned(),
            protocol_version: PROTOCOL_VERSION,
            supported_protocol_versions: SUPPORTED_PROTOCOL_VERSIONS.to_vec(),
        }),
        Request::GetState => Response::State(state()),
        Request::GetProviderState { provider } => state()
            .providers
            .get(&provider)
            .cloned()
            .map(Response::ProviderState)
            .unwrap_or_else(|| {
                Response::State(State {
                    timestamp: timestamp(),
                    providers: BTreeMap::new(),
                    settings: BTreeMap::new(),
                })
            }),
        Request::Subscribe { .. } => Response::Subscription(noxflow_ipc::Subscription {
            subscription_id: "pending".into(),
        }),
        Request::Unsubscribe { .. } => Response::Pong,
        Request::SetSetting { key, value } => {
            Response::SettingUpdated(noxflow_ipc::SettingUpdated { key, value })
        }
        Request::RunAction { action } => Response::ActionAccepted(ActionAccepted { action }),
    }
}

fn decode_error(error: DecodeError) -> (String, IpcError) {
    match error {
        DecodeError::UnsupportedProtocolVersion {
            request_id,
            requested,
        } => {
            let mut details = BTreeMap::new();
            details.insert("requested_version".into(), requested.to_string());
            details.insert(
                "supported_versions".into(),
                format!("{SUPPORTED_PROTOCOL_VERSIONS:?}"),
            );
            (
                request_id,
                IpcError {
                    code: ErrorCode::UnsupportedProtocolVersion,
                    message: "unsupported protocol version".into(),
                    details,
                },
            )
        }
        DecodeError::MissingRequestId => (
            String::new(),
            IpcError {
                code: ErrorCode::InvalidRequest,
                message: "every request must include an id".into(),
                details: BTreeMap::new(),
            },
        ),
        other => (
            String::new(),
            IpcError {
                code: ErrorCode::InvalidRequest,
                message: format!("invalid request: {other:?}"),
                details: BTreeMap::new(),
            },
        ),
    }
}

fn write_response(stream: &mut UnixStream, response: &ResponseEnvelope) -> io::Result<()> {
    serde_json::to_writer(&mut *stream, response).map_err(io::Error::other)?;
    stream.write_all(b"\n")
}

enum FrameStatus {
    EndOfStream,
    Complete,
    Unterminated,
    Oversized,
}

fn read_frame(reader: &mut BufReader<UnixStream>, frame: &mut Vec<u8>) -> io::Result<FrameStatus> {
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(if frame.is_empty() {
                FrameStatus::EndOfStream
            } else {
                FrameStatus::Unterminated
            });
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let remaining = MAX_FRAME_BYTES + 1 - frame.len().min(MAX_FRAME_BYTES + 1);
        let amount = newline
            .map(|position| (position + 1).min(remaining))
            .unwrap_or(available.len().min(remaining));
        frame.extend_from_slice(&available[..amount]);
        reader.consume(amount);
        if frame.len() > MAX_FRAME_BYTES {
            return Ok(FrameStatus::Oversized);
        }
        if newline.is_some() {
            return Ok(FrameStatus::Complete);
        }
    }
}

fn handle_client(mut stream: UnixStream, socket: &Path) -> io::Result<()> {
    stream.set_read_timeout(Some(CLIENT_READ_TIMEOUT))?;
    log_event("info", "client_connection", Some(socket), None, None);
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut frame = Vec::with_capacity(MAX_FRAME_BYTES.min(4096));
    loop {
        frame.clear();
        match read_frame(&mut reader, &mut frame)? {
            FrameStatus::EndOfStream => break,
            FrameStatus::Unterminated => {
                log_event(
                    "warn",
                    "invalid_message",
                    Some(socket),
                    None,
                    Some("message is not newline terminated"),
                );
                break;
            }
            FrameStatus::Oversized => {
                log_event(
                    "warn",
                    "invalid_message",
                    Some(socket),
                    None,
                    Some("message exceeds 64 KiB"),
                );
                break;
            }
            FrameStatus::Complete => {}
        }
        if frame.last() == Some(&b'\n') {
            frame.pop();
        }
        if frame.last() == Some(&b'\r') {
            frame.pop();
        }
        let text = match std::str::from_utf8(&frame) {
            Ok(text) => text,
            Err(error) => {
                log_event(
                    "warn",
                    "invalid_message",
                    Some(socket),
                    None,
                    Some(&error.to_string()),
                );
                write_response(
                    &mut stream,
                    &error_response(
                        String::new(),
                        IpcError {
                            code: ErrorCode::InvalidRequest,
                            message: "request must be valid UTF-8".into(),
                            details: BTreeMap::new(),
                        },
                    ),
                )?;
                continue;
            }
        };
        match decode_request(text) {
            Ok(envelope) => write_response(
                &mut stream,
                &response(envelope.request_id, handle_request(envelope.request)),
            )?,
            Err(error) => {
                let (request_id, ipc_error) = decode_error(error);
                log_event(
                    "warn",
                    "invalid_message",
                    Some(socket),
                    Some(&request_id),
                    Some(&ipc_error.message),
                );
                write_response(&mut stream, &error_response(request_id, ipc_error))?;
            }
        }
    }
    log_event("info", "client_disconnection", Some(socket), None, None);
    Ok(())
}

fn cleanup_socket(path: &Path, expected: Option<(u64, u64)>) {
    if let Ok(metadata) = fs::symlink_metadata(path) {
        let identity_matches = expected
            .map(|(device, inode)| metadata.dev() == device && metadata.ino() == inode)
            .unwrap_or(true);
        if metadata.file_type().is_socket() && metadata.uid() == current_uid() && identity_matches {
            if let Err(error) = fs::remove_file(path) {
                log_event(
                    "error",
                    "internal_failure",
                    Some(path),
                    None,
                    Some(&format!("socket cleanup failed: {error}")),
                );
            }
        }
    }
}

fn run() -> io::Result<()> {
    let socket = socket_path()?;
    prepare_socket(&socket)?;
    let listener = UnixListener::bind(&socket)?;
    if let Err(error) = fs::set_permissions(&socket, fs::Permissions::from_mode(0o600)) {
        cleanup_socket(&socket, None);
        return Err(error);
    }
    let socket_metadata = fs::symlink_metadata(&socket)?;
    let socket_identity = (socket_metadata.dev(), socket_metadata.ino());
    let shutting_down = Arc::new(AtomicBool::new(false));
    signal_hook::flag::register(signal_hook::consts::SIGTERM, Arc::clone(&shutting_down))
        .map_err(io::Error::other)?;
    signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&shutting_down))
        .map_err(io::Error::other)?;
    listener.set_nonblocking(true)?;
    log_event("info", "startup", Some(&socket), None, None);
    let mut clients = Vec::new();
    while !shutting_down.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, _)) => {
                let client_socket = socket.clone();
                clients.push(thread::spawn(move || {
                    if let Err(error) = handle_client(stream, &client_socket) {
                        log_event(
                            "error",
                            "internal_failure",
                            Some(&client_socket),
                            None,
                            Some(&error.to_string()),
                        );
                    }
                }));
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(ACCEPT_POLL_INTERVAL)
            }
            Err(error) => log_event(
                "error",
                "internal_failure",
                Some(&socket),
                None,
                Some(&error.to_string()),
            ),
        }
    }
    drop(listener);
    for client in clients {
        let _ = client.join();
    }
    cleanup_socket(&socket, Some(socket_identity));
    log_event("info", "shutdown", Some(&socket), None, None);
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        log_event(
            "error",
            "internal_failure",
            None,
            None,
            Some(&error.to_string()),
        );
        std::process::exit(1);
    }
}
