use noxd::{settings::SettingsStore, EventBus, DEFAULT_QUEUE_CAPACITY};
use noxflow_config::{env_profile_override, ConfigLoader};
use noxflow_diagnostics::{install_panic_hook, log as diagnostic_log, ProviderFailureLimiter};
use noxflow_ipc::{
    decode_request, Action, ActionAccepted, DecodeError, ErrorCode, IpcError, ProviderState,
    ProviderStatus, Request, Response, ResponseEnvelope, SettingValue, SettingsMap, State,
    VersionInfo, PROTOCOL_VERSION, SUPPORTED_PROTOCOL_VERSIONS,
};
use noxflow_state::StateStore;
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
// Clients stay connected while waiting for provider events; one second is
// shorter than a normal shell startup and causes EAGAIN to be treated as a
// fatal disconnect before the subscription handshake completes.
const CLIENT_READ_TIMEOUT: Duration = Duration::from_secs(10);
const CLIENT_WRITE_TIMEOUT: Duration = Duration::from_secs(10);

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
    let context = match (socket, error) {
        (Some(socket), Some(error)) => format!("socket={}; {}", socket.display(), error),
        (Some(socket), None) => format!("socket={}", socket.display()),
        (None, Some(error)) => error.to_owned(),
        (None, None) => String::new(),
    };
    diagnostic_log(
        "noxd",
        level,
        event,
        None,
        request_id,
        (!context.is_empty()).then_some(context.as_str()),
    );
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

#[allow(clippy::too_many_arguments)]
fn handle_request(
    request: Request,
    bus: &EventBus,
    settings: &noxd::settings::SettingsStore,
    audio: &noxd::providers::audio::ControlSender,
    brightness: &noxd::providers::brightness::Control,
    power: &noxd::providers::power::Control,
    network: &noxd::providers::network::Control,
    bluetooth: &noxd::providers::bluetooth::Control,
    media: &noxd::providers::media::ControlSender,
    transfer: &noxd::providers::transfer::Control,
) -> Result<Response, IpcError> {
    let result = match request {
        Request::Ping => Response::Pong,
        Request::GetVersion => Response::Version(VersionInfo {
            daemon_version: env!("CARGO_PKG_VERSION").to_owned(),
            protocol_version: PROTOCOL_VERSION,
            supported_protocol_versions: SUPPORTED_PROTOCOL_VERSIONS.to_vec(),
        }),
        Request::GetState => Response::State(State {
            timestamp: timestamp(),
            providers: bus.snapshot(),
            settings: settings.get_all(),
        }),
        Request::GetProviderState { provider } => bus
            .snapshot()
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
        Request::Subscribe { .. } => unreachable!("subscriptions are handled by the client loop"),
        Request::Unsubscribe { .. } => Response::Pong,
        Request::SetSetting { key, value } => {
            settings.set(&key, value.clone())?;
            let _ = bus.publish(noxd::SettingChangedEvent {
                key: key.clone(),
                value: value.clone(),
            });
            Response::SettingUpdated(noxflow_ipc::SettingUpdated { key, value })
        }
        Request::GetSetting { key } => {
            let value = settings.get(&key)?;
            Response::Setting(SettingValue { key, value })
        }
        Request::GetSettings => Response::Settings(SettingsMap {
            settings: settings.get_all(),
        }),
        Request::RunAction { action } => {
            if matches!(
                &action,
                Action::IslandTestVolume { .. }
                    | Action::IslandTestOutputMute { .. }
                    | Action::IslandTestInputMute { .. }
                    | Action::IslandTestBrightness { .. }
            ) {
                noxd::publish_island_test(bus, &action).map_err(|message| IpcError {
                    code: ErrorCode::Unsupported,
                    message,
                    details: BTreeMap::new(),
                })?;
            }
            if matches!(
                &action,
                Action::WorkspaceFocus { .. } | Action::WorkspaceCycle { .. }
            ) {
                noxd::providers::hyprland::dispatch_workspace(&action).map_err(|error| {
                    IpcError {
                        code: ErrorCode::Unsupported,
                        message: error.to_string(),
                        details: BTreeMap::new(),
                    }
                })?;
            }
            let command = match &action {
                Action::AudioSetVolume { target, volume } => {
                    Some(noxd::providers::audio::CommandRequest::SetVolume {
                        target: target.clone(),
                        value: *volume,
                    })
                }
                Action::AudioAdjustVolume { target, delta } => {
                    Some(noxd::providers::audio::CommandRequest::AdjustVolume {
                        target: target.clone(),
                        delta: *delta,
                    })
                }
                Action::AudioToggleMute { target } => {
                    Some(noxd::providers::audio::CommandRequest::ToggleMute {
                        target: target.clone(),
                    })
                }
                Action::AudioSetDefault { target, selector } => {
                    Some(noxd::providers::audio::CommandRequest::SetDefault {
                        target: target.clone(),
                        selector: selector.clone(),
                    })
                }
                _ => None,
            };
            if let Some(command) = command {
                let _ = audio.send(command);
            }
            match action.clone() {
                Action::BrightnessSet { percentage } => {
                    brightness
                        .send(noxd::providers::brightness::CommandRequest::Set { percentage })
                        .map_err(|error| IpcError {
                            code: ErrorCode::Unsupported,
                            message: error.to_string(),
                            details: BTreeMap::new(),
                        })?;
                }
                Action::BrightnessAdjust { delta } => {
                    brightness
                        .send(noxd::providers::brightness::CommandRequest::Adjust { delta })
                        .map_err(|error| IpcError {
                            code: ErrorCode::Unsupported,
                            message: error.to_string(),
                            details: BTreeMap::new(),
                        })?;
                }
                Action::PowerProfileSet { profile } => {
                    power.set_profile(profile).map_err(|error| IpcError {
                        code: ErrorCode::Unsupported,
                        message: error.to_string(),
                        details: BTreeMap::new(),
                    })?;
                }
                Action::NetworkWifiSetEnabled { enabled } => network
                    .send(noxd::providers::network::CommandRequest::WifiSetEnabled(
                        enabled,
                    ))
                    .map_err(network_error)?,
                Action::NetworkConnectSaved { ssid } => network
                    .send(noxd::providers::network::CommandRequest::ConnectSaved(ssid))
                    .map_err(network_error)?,
                Action::NetworkConnect { ssid, passphrase } => network
                    .send(noxd::providers::network::CommandRequest::Connect { ssid, passphrase })
                    .map_err(network_error)?,
                Action::NetworkForget { ssid } => network
                    .send(noxd::providers::network::CommandRequest::Forget(ssid))
                    .map_err(network_error)?,
                Action::NetworkDisconnectWifi => network
                    .send(noxd::providers::network::CommandRequest::DisconnectWifi)
                    .map_err(network_error)?,
                Action::NetworkRefresh => network
                    .send(noxd::providers::network::CommandRequest::Refresh)
                    .map_err(network_error)?,
                Action::NetworkVpnSetEnabled { uuid, enabled } => network
                    .send(noxd::providers::network::CommandRequest::VpnSetEnabled { uuid, enabled })
                    .map_err(network_error)?,
                Action::BluetoothSetPowered { powered } => bluetooth
                    .send(noxd::providers::bluetooth::CommandRequest::SetPowered(
                        powered,
                    ))
                    .map_err(bluetooth_error)?,
                Action::BluetoothSetDiscovering { discovering } => bluetooth
                    .send(noxd::providers::bluetooth::CommandRequest::SetDiscovering(
                        discovering,
                    ))
                    .map_err(bluetooth_error)?,
                Action::BluetoothConnect { device_id } => bluetooth
                    .send(noxd::providers::bluetooth::CommandRequest::Connect(
                        device_id,
                    ))
                    .map_err(bluetooth_error)?,
                Action::BluetoothDisconnect { device_id } => bluetooth
                    .send(noxd::providers::bluetooth::CommandRequest::Disconnect(
                        device_id,
                    ))
                    .map_err(bluetooth_error)?,
                Action::BluetoothSetTrusted { device_id, trusted } => bluetooth
                    .send(noxd::providers::bluetooth::CommandRequest::SetTrusted {
                        device_id,
                        trusted,
                    })
                    .map_err(bluetooth_error)?,
                Action::MediaPlay => media
                    .send(noxd::providers::media::CommandRequest::Play)
                    .map_err(media_error)?,
                Action::MediaPause => media
                    .send(noxd::providers::media::CommandRequest::Pause)
                    .map_err(media_error)?,
                Action::MediaPlayPause => media
                    .send(noxd::providers::media::CommandRequest::PlayPause)
                    .map_err(media_error)?,
                Action::MediaPrevious => media
                    .send(noxd::providers::media::CommandRequest::Previous)
                    .map_err(media_error)?,
                Action::MediaNext => media
                    .send(noxd::providers::media::CommandRequest::Next)
                    .map_err(media_error)?,
                Action::MediaSeek { offset_us } => media
                    .send(noxd::providers::media::CommandRequest::Seek { offset_us })
                    .map_err(media_error)?,
                Action::MediaSelectPlayer { player } => media
                    .send(noxd::providers::media::CommandRequest::SelectPlayer { player })
                    .map_err(media_error)?,
                Action::TransferDiscover => transfer
                    .send(noxd::providers::transfer::CommandRequest::Discover)
                    .map_err(transfer_error)?,
                Action::TransferSend { peer_id, paths } => transfer
                    .send(noxd::providers::transfer::CommandRequest::Send { peer_id, paths })
                    .map_err(transfer_error)?,
                Action::TransferAccept { session_id } => transfer
                    .send(noxd::providers::transfer::CommandRequest::Accept { session_id })
                    .map_err(transfer_error)?,
                Action::TransferDecline { session_id } => transfer
                    .send(noxd::providers::transfer::CommandRequest::Decline { session_id })
                    .map_err(transfer_error)?,
                Action::TransferCancel { session_id } => transfer
                    .send(noxd::providers::transfer::CommandRequest::Cancel { session_id })
                    .map_err(transfer_error)?,
                _ => {}
            }
            let accepted_action = match action {
                Action::NetworkConnect { ssid, .. } => Action::NetworkConnect {
                    ssid,
                    passphrase: String::new(),
                },
                other => other,
            };
            Response::ActionAccepted(ActionAccepted {
                action: accepted_action,
            })
        }
    };
    Ok(result)
}

fn network_error(error: io::Error) -> IpcError {
    IpcError {
        code: ErrorCode::Unsupported,
        message: error.to_string(),
        details: BTreeMap::new(),
    }
}

fn bluetooth_error(error: io::Error) -> IpcError {
    IpcError {
        code: ErrorCode::Unsupported,
        message: error.to_string(),
        details: BTreeMap::new(),
    }
}

fn media_error<E: std::fmt::Display>(error: E) -> IpcError {
    IpcError {
        code: ErrorCode::Unsupported,
        message: error.to_string(),
        details: BTreeMap::new(),
    }
}

fn transfer_error<E: std::fmt::Display>(error: E) -> IpcError {
    IpcError {
        code: ErrorCode::Unsupported,
        message: error.to_string(),
        details: BTreeMap::new(),
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

fn write_event(stream: &mut UnixStream, event: &noxflow_ipc::EventEnvelope) -> io::Result<()> {
    serde_json::to_writer(&mut *stream, event).map_err(io::Error::other)?;
    stream.write_all(b"\n")
}

enum Outbound {
    Response(ResponseEnvelope),
    Event(noxflow_ipc::EventEnvelope),
}

fn writer(mut stream: UnixStream, receiver: std::sync::mpsc::Receiver<Outbound>) -> io::Result<()> {
    while let Ok(message) = receiver.recv() {
        match message {
            Outbound::Response(response) => write_response(&mut stream, &response)?,
            Outbound::Event(event) => write_event(&mut stream, &event)?,
        }
    }
    Ok(())
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

#[allow(clippy::too_many_arguments)]
fn handle_client(
    stream: UnixStream,
    socket: &Path,
    bus: EventBus,
    settings: noxd::settings::SettingsStore,
    audio: noxd::providers::audio::ControlSender,
    brightness: noxd::providers::brightness::Control,
    power: noxd::providers::power::Control,
    network: noxd::providers::network::Control,
    bluetooth: noxd::providers::bluetooth::Control,
    media: noxd::providers::media::ControlSender,
    transfer: noxd::providers::transfer::Control,
) -> io::Result<()> {
    // The listener is nonblocking for accept polling, and accepted Unix
    // streams can inherit that mode. Client reads are handled on their own
    // thread with a timeout, so force blocking mode here; otherwise an
    // ordinary EAGAIN is treated as a fatal client disconnect and the shell
    // loses its subscription before provider snapshots arrive.
    stream.set_nonblocking(false)?;
    stream.set_read_timeout(Some(CLIENT_READ_TIMEOUT))?;
    log_event("info", "client_connection", Some(socket), None, None);
    let (outbound, messages) = std::sync::mpsc::sync_channel(DEFAULT_QUEUE_CAPACITY);
    let writer_stream = stream.try_clone()?;
    writer_stream.set_write_timeout(Some(CLIENT_WRITE_TIMEOUT))?;
    let writer_thread = thread::spawn(move || writer(writer_stream, messages));
    let mut subscriptions: Vec<(String, thread::JoinHandle<()>)> = Vec::new();
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut frame = Vec::with_capacity(MAX_FRAME_BYTES.min(4096));
    loop {
        frame.clear();
        let frame_status = match read_frame(&mut reader, &mut frame) {
            Ok(status) => status,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) =>
            {
                continue
            }
            Err(error) => return Err(error),
        };
        match frame_status {
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
                outbound
                    .send(Outbound::Response(error_response(
                        String::new(),
                        IpcError {
                            code: ErrorCode::InvalidRequest,
                            message: "request must be valid UTF-8".into(),
                            details: BTreeMap::new(),
                        },
                    )))
                    .map_err(|_| {
                        io::Error::new(io::ErrorKind::BrokenPipe, "client writer stopped")
                    })?;
                continue;
            }
        };
        match decode_request(text) {
            Ok(envelope) => {
                let request_id = envelope.request_id;
                match envelope.request {
                    Request::Subscribe {
                        providers,
                        event_types,
                    } => match bus.subscribe(providers, event_types) {
                        Ok(subscription) => {
                            let acknowledgement = subscription.acknowledgement.clone();
                            let receiver = subscription.into_parts().1;
                            let subscription_id = acknowledgement.subscription_id.clone();
                            outbound
                                .send(Outbound::Response(response(
                                    request_id,
                                    Response::Subscription(acknowledgement),
                                )))
                                .map_err(|_| {
                                    io::Error::new(
                                        io::ErrorKind::BrokenPipe,
                                        "client writer stopped",
                                    )
                                })?;
                            let event_sender = outbound.clone();
                            let event_thread = thread::spawn(move || {
                                while let Ok(event) = receiver.recv() {
                                    if event_sender.send(Outbound::Event(event)).is_err() {
                                        break;
                                    }
                                }
                            });
                            subscriptions.push((subscription_id, event_thread));
                        }
                        Err(error) => {
                            outbound
                                .send(Outbound::Response(error_response(
                                    request_id,
                                    bus_error(error),
                                )))
                                .map_err(|_| {
                                    io::Error::new(
                                        io::ErrorKind::BrokenPipe,
                                        "client writer stopped",
                                    )
                                })?;
                        }
                    },
                    Request::Unsubscribe { subscription_id } => {
                        let removed = bus.unsubscribe(&subscription_id);
                        if removed {
                            if let Some(position) = subscriptions
                                .iter()
                                .position(|(id, _)| id == &subscription_id)
                            {
                                let (_, thread) = subscriptions.swap_remove(position);
                                let _ = thread.join();
                            }
                        }
                        outbound
                            .send(Outbound::Response(response(request_id, Response::Pong)))
                            .map_err(|_| {
                                io::Error::new(io::ErrorKind::BrokenPipe, "client writer stopped")
                            })?;
                    }
                    request => {
                        let outbound_response = match handle_request(
                            request,
                            &bus,
                            &settings,
                            &audio,
                            &brightness,
                            &power,
                            &network,
                            &bluetooth,
                            &media,
                            &transfer,
                        ) {
                            Ok(result) => response(request_id, result),
                            Err(error) => error_response(request_id, error),
                        };
                        outbound
                            .send(Outbound::Response(outbound_response))
                            .map_err(|_| {
                                io::Error::new(io::ErrorKind::BrokenPipe, "client writer stopped")
                            })?;
                    }
                }
            }
            Err(error) => {
                let (request_id, ipc_error) = decode_error(error);
                log_event(
                    "warn",
                    "invalid_message",
                    Some(socket),
                    Some(&request_id),
                    Some(&ipc_error.message),
                );
                outbound
                    .send(Outbound::Response(error_response(request_id, ipc_error)))
                    .map_err(|_| {
                        io::Error::new(io::ErrorKind::BrokenPipe, "client writer stopped")
                    })?;
            }
        }
    }
    for (subscription_id, _) in &subscriptions {
        bus.unsubscribe(subscription_id);
    }
    for (_, thread) in subscriptions {
        let _ = thread.join();
    }
    drop(outbound);
    let _ = writer_thread.join();
    log_event("info", "client_disconnection", Some(socket), None, None);
    Ok(())
}

fn bus_error(error: noxd::BusError) -> IpcError {
    IpcError {
        code: match error {
            noxd::BusError::UnknownProvider(_) => ErrorCode::UnknownProvider,
            noxd::BusError::Closed | noxd::BusError::AlreadyRegistered(_) => ErrorCode::Internal,
        },
        message: format!("event bus error: {error:?}"),
        details: BTreeMap::new(),
    }
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
    // Load and validate configuration
    let mut loader = ConfigLoader::new();
    if let Some(profile) = env_profile_override() {
        if !profile.is_empty() {
            loader = loader.with_profile(profile);
        }
    }
    let config = match loader.load() {
        Ok(cfg) => cfg,
        Err(errors) => {
            for error in &errors {
                log_event(
                    "error",
                    "config_error",
                    None,
                    None,
                    Some(&error.to_string()),
                );
            }
            return Err(io::Error::other(format!(
                "configuration validation failed ({} error(s))",
                errors.len()
            )));
        }
    };

    let (mut persistent_state, state_info) =
        StateStore::load(config.runtime.state_dir.join("state.toml"))
            .map_err(|error| io::Error::other(format!("persistent state load failed: {error}")))?;
    if state_info.recovered {
        log_event(
            "warn",
            "state_recovered",
            Some(persistent_state.path()),
            None,
            Some("corrupt state was quarantined and reset"),
        );
    }
    if state_info.migrated {
        log_event(
            "info",
            "state_migrated",
            Some(persistent_state.path()),
            None,
            None,
        );
        if let Err(error) = persistent_state.save() {
            log_event(
                "warn",
                "state_unsynced",
                Some(persistent_state.path()),
                None,
                Some(&error.to_string()),
            );
        }
    }
    if state_info.recovered {
        log_event(
            "warn",
            "state_reset",
            Some(persistent_state.path()),
            None,
            Some("persistent state was reset after recovery"),
        );
        if let Err(error) = persistent_state.save() {
            log_event(
                "warn",
                "state_unsynced",
                Some(persistent_state.path()),
                None,
                Some(&error.to_string()),
            );
        }
    }

    // Initialize settings store
    let settings_store = SettingsStore::new(&config.runtime.state_dir);
    let loaded_settings = settings_store.load();
    let _ = &loaded_settings; // available for broadcast to subscribing clients

    let socket_path = &config.runtime.socket_path;
    eprintln!(
        "{}",
        json!({
            "timestamp": timestamp(),
            "level": "info",
            "event": "config_loaded",
            "component": "noxd",
            "pid": std::process::id(),
            "config_dir": config.runtime.config_dir.display().to_string(),
            "socket": socket_path.display().to_string(),
            "profile": config.profile,
        })
    );

    // Ensure socket directory exists with safe permissions
    if let Some(parent) = socket_path.parent() {
        match fs::symlink_metadata(parent) {
            Ok(_) => validate_directory(parent, current_uid(), true)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                fs::create_dir(parent)?;
                fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
                validate_directory(parent, current_uid(), true)?;
            }
            Err(error) => return Err(error),
        }
    }
    let socket = socket_path.clone();
    prepare_socket(&socket)?;
    let listener = UnixListener::bind(&socket)?;
    if let Err(error) = fs::set_permissions(&socket, fs::Permissions::from_mode(0o600)) {
        cleanup_socket(&socket, None);
        return Err(error);
    }
    let socket_metadata = fs::symlink_metadata(&socket)?;
    let socket_identity = (socket_metadata.dev(), socket_metadata.ino());
    let shutting_down = Arc::new(AtomicBool::new(false));
    let bus = EventBus::new();
    let provider_failures = ProviderFailureLimiter::new(Duration::from_secs(30));
    for provider in [
        "hyprland",
        "audio",
        "brightness",
        "network",
        "power",
        "bluetooth",
        "media",
        "settings",
        "transfer",
    ] {
        let registration = bus.register_provider(ProviderState {
            provider: provider.into(),
            status: ProviderStatus::Pending,
            data: BTreeMap::new(),
        });
        if let Err(error) = registration {
            if let Some(suppressed) = provider_failures.record(provider) {
                diagnostic_log(
                    "noxd",
                    "error",
                    "provider_failure",
                    Some(provider),
                    None,
                    Some(&format!(
                        "socket={}; suppressed={suppressed}; {error:?}",
                        socket.display()
                    )),
                );
            }
            return Err(io::Error::other(format!(
                "provider registration failed: {error:?}"
            )));
        }
    }
    let hyprland_thread = noxd::providers::hyprland::start(bus.clone(), Arc::clone(&shutting_down));
    let (audio_thread, audio_control) = noxd::providers::audio::start(
        bus.clone(),
        Arc::clone(&shutting_down),
        config.audio.max_volume,
    );
    let (brightness_thread, brightness_control) = noxd::providers::brightness::start(
        bus.clone(),
        Arc::clone(&shutting_down),
        config.brightness.minimum,
        config.brightness.step,
        config.brightness.external_backend.clone(),
    );
    let (power_thread, power_control) =
        noxd::providers::power::start(bus.clone(), Arc::clone(&shutting_down));
    let (transfer_thread, transfer_control) = noxd::providers::transfer::start(
        bus.clone(),
        Arc::clone(&shutting_down),
        config.runtime.state_dir.clone(),
    );
    let (network_thread, network_control) =
        noxd::providers::network::start(bus.clone(), Arc::clone(&shutting_down));
    let (bluetooth_thread, bluetooth_control) =
        noxd::providers::bluetooth::start(bus.clone(), Arc::clone(&shutting_down));
    let artwork_dir = if config.media.artwork_cache_dir.is_empty() {
        env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join("noxflow/artwork")
    } else {
        PathBuf::from(&config.media.artwork_cache_dir)
    };
    let (media_thread, media_control) = noxd::providers::media::start(
        bus.clone(),
        Arc::clone(&shutting_down),
        config.providers.media && config.media.mpris_integration,
        config.media.default_player.clone(),
        noxd::providers::media::ArtworkCacheConfig {
            enabled: config.providers.media
                && config.media.mpris_integration
                && config.media.artwork_cache_enabled,
            directory: artwork_dir,
            max_bytes: config.media.artwork_cache_max_bytes,
            ttl: Duration::from_secs(config.media.artwork_cache_ttl),
        },
    );
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
                let client_bus = bus.clone();
                let client_settings = settings_store.clone(); // SettingsStore is Arc<Mutex<...>>
                let client_audio = audio_control.clone();
                let client_brightness = brightness_control.clone();
                let client_power = power_control.clone();
                let client_network = network_control.clone();
                let client_bluetooth = bluetooth_control.clone();
                let client_media = media_control.clone();
                let client_transfer = transfer_control.clone();
                clients.push(thread::spawn(move || {
                    if let Err(error) = handle_client(
                        stream,
                        &client_socket,
                        client_bus,
                        client_settings,
                        client_audio,
                        client_brightness,
                        client_power,
                        client_network,
                        client_bluetooth,
                        client_media,
                        client_transfer,
                    ) {
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
    bus.shutdown();
    let _ = hyprland_thread.join();
    drop(audio_control);
    let _ = audio_thread.join();
    drop(brightness_control);
    let _ = brightness_thread.join();
    drop(power_control);
    let _ = power_thread.join();
    drop(transfer_control);
    let _ = transfer_thread.join();
    drop(network_control);
    let _ = network_thread.join();
    drop(bluetooth_control);
    let _ = bluetooth_thread.join();
    drop(media_control);
    let _ = media_thread.join();
    for client in clients {
        let _ = client.join();
    }
    cleanup_socket(&socket, Some(socket_identity));
    if persistent_state.is_dirty() {
        if let Err(error) = persistent_state.save() {
            log_event(
                "warn",
                "state_unsynced",
                Some(persistent_state.path()),
                None,
                Some(&error.to_string()),
            );
        }
    }
    log_event("info", "shutdown", Some(&socket), None, None);
    Ok(())
}

fn main() {
    install_panic_hook("noxd");
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
