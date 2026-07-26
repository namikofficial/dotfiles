use noxflow_ipc::{
    decode_request, ActionAccepted, DecodeError, ErrorCode, IpcError, ProviderState,
    ProviderStatus, Request, Response, ResponseEnvelope, State, VersionInfo, PROTOCOL_VERSION,
    SOCKET_DIRECTORY, SOCKET_NAME, SUPPORTED_PROTOCOL_VERSIONS,
};
use std::{
    collections::BTreeMap,
    env, fs,
    io::Read,
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

fn runtime_dir() -> PathBuf {
    PathBuf::from(env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into()))
        .join(SOCKET_DIRECTORY)
}

fn timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn response(request_id: String, result: Response) -> ResponseEnvelope {
    ResponseEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id,
        result: Some(result),
        error: None,
    }
}

fn state() -> State {
    let mut providers = BTreeMap::new();
    for provider in ["hyprland", "audio", "network", "battery", "media"] {
        providers.insert(
            provider.to_owned(),
            ProviderState {
                provider: provider.to_owned(),
                status: ProviderStatus::Pending,
                data: BTreeMap::new(),
            },
        );
    }
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
            .unwrap_or(Response::State(State {
                timestamp: timestamp(),
                providers: BTreeMap::new(),
                settings: BTreeMap::new(),
            })),
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

fn handle(mut stream: UnixStream) -> std::io::Result<()> {
    let mut input = String::new();
    stream.read_to_string(&mut input)?;
    let envelope = match decode_request(&input) {
        Ok(envelope) => envelope,
        Err(error) => {
            let (request_id, ipc_error) = match error {
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
            };
            serde_json::to_writer(
                &mut stream,
                &ResponseEnvelope {
                    protocol_version: PROTOCOL_VERSION,
                    request_id,
                    result: None,
                    error: Some(ipc_error),
                },
            )?;
            return Ok(());
        }
    };
    Ok(serde_json::to_writer(
        &mut stream,
        &response(envelope.request_id, handle_request(envelope.request)),
    )?)
}

fn main() -> std::io::Result<()> {
    let dir = runtime_dir();
    fs::create_dir_all(&dir)?;
    let socket = dir.join(SOCKET_NAME);
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
