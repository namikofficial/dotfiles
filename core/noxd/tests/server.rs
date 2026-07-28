use noxflow_ipc::{Action, ErrorCode, Request, RequestEnvelope, ResponseEnvelope, PROTOCOL_VERSION};
use std::{
    fs,
    io::{BufRead, BufReader, Read, Write},
    os::unix::{
        fs::PermissionsExt,
        net::{UnixListener, UnixStream},
    },
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::Arc,
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

struct TestDaemon {
    child: Child,
    runtime: PathBuf,
}

impl TestDaemon {
    #[allow(clippy::zombie_processes)]
    fn start() -> Self {
        let runtime = std::env::temp_dir().join(format!(
            "noxd-test-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&runtime).unwrap();
        fs::set_permissions(&runtime, fs::Permissions::from_mode(0o700)).unwrap();
        let child = Command::new(env!("CARGO_BIN_EXE_noxd"))
            .env("XDG_RUNTIME_DIR", &runtime)
            .env("XDG_STATE_HOME", runtime.join("state"))
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let socket = runtime.join("noxflow/noxd.sock");
        for _ in 0..100 {
            if socket.exists() {
                return Self { child, runtime };
            }
            thread::sleep(Duration::from_millis(10));
        }
        panic!("daemon did not create socket");
    }

    fn socket(&self) -> PathBuf {
        self.runtime.join("noxflow/noxd.sock")
    }

    fn request(&self, request: Request, id: &str) -> ResponseEnvelope {
        let mut stream = UnixStream::connect(self.socket()).unwrap();
        let envelope = RequestEnvelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: id.into(),
            request,
        };
        writeln!(stream, "{}", serde_json::to_string(&envelope).unwrap()).unwrap();
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    }
}

impl Drop for TestDaemon {
    fn drop(&mut self) {
        unsafe {
            libc::kill(self.child.id() as i32, libc::SIGTERM);
        }
        let _ = self.child.wait();
        let _ = fs::remove_dir_all(&self.runtime);
    }
}

#[test]
fn serves_required_requests_and_frames_responses() {
    let daemon = TestDaemon::start();
    let ping = daemon.request(Request::Ping, "ping-1");
    assert_eq!(ping.request_id, "ping-1");
    assert!(ping.result.is_some());

    let version = daemon.request(Request::GetVersion, "version-1");
    assert!(matches!(
        version.result,
        Some(noxflow_ipc::Response::Version(_))
    ));

    let state = daemon.request(Request::GetState, "state-1");
    assert!(matches!(
        state.result,
        Some(noxflow_ipc::Response::State(_))
    ));
}

#[test]
fn accepts_multiple_concurrent_clients() {
    let daemon = Arc::new(TestDaemon::start());
    let workers = (0..8)
        .map(|index| {
            let daemon = Arc::clone(&daemon);
            thread::spawn(move || {
                let response = daemon.request(Request::Ping, &format!("client-{index}"));
                assert_eq!(response.request_id, format!("client-{index}"));
            })
        })
        .collect::<Vec<_>>();
    for worker in workers {
        worker.join().unwrap();
    }
    drop(daemon);
}

#[test]
fn malformed_messages_do_not_kill_daemon() {
    let daemon = TestDaemon::start();
    let mut stream = UnixStream::connect(daemon.socket()).unwrap();
    writeln!(stream, "{{not-json}}").unwrap();
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).unwrap();
    let response: ResponseEnvelope = serde_json::from_str(&line).unwrap();
    assert!(response.error.is_some());
    assert!(daemon
        .request(Request::Ping, "after-invalid")
        .result
        .is_some());
}

#[test]
fn oversized_message_is_disconnected_but_server_survives() {
    let daemon = TestDaemon::start();
    let mut stream = UnixStream::connect(daemon.socket()).unwrap();
    stream.write_all(&vec![b'a'; 65 * 1024]).unwrap();
    stream.shutdown(std::net::Shutdown::Write).unwrap();
    let mut response = String::new();
    let _ = stream.read_to_string(&mut response);
    assert!(daemon
        .request(Request::Ping, "after-oversized")
        .result
        .is_some());
}

#[test]
fn owned_stale_socket_is_removed_and_unexpected_path_is_rejected() {
    let runtime = std::env::temp_dir().join(format!("noxd-safety-{}", std::process::id()));
    let _ = fs::remove_dir_all(&runtime);
    fs::create_dir(&runtime).unwrap();
    fs::set_permissions(&runtime, fs::Permissions::from_mode(0o700)).unwrap();
    let socket = runtime.join("noxflow/noxd.sock");
    fs::create_dir(runtime.join("noxflow")).unwrap();
    fs::set_permissions(runtime.join("noxflow"), fs::Permissions::from_mode(0o700)).unwrap();
    let stale_listener = UnixListener::bind(&socket).unwrap();
    drop(stale_listener);
    let mut daemon = Command::new(env!("CARGO_BIN_EXE_noxd"))
        .env("XDG_RUNTIME_DIR", &runtime)
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    for _ in 0..100 {
        if socket.exists() && UnixStream::connect(&socket).is_ok() {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
    unsafe {
        libc::kill(daemon.id() as i32, libc::SIGTERM);
    }
    daemon.wait().unwrap();
    assert!(!socket.exists());

    fs::write(&socket, b"not a socket").unwrap();
    let rejected = Command::new(env!("CARGO_BIN_EXE_noxd"))
        .env("XDG_RUNTIME_DIR", &runtime)
        .output()
        .unwrap();
    assert!(!rejected.status.success());
    assert!(socket.is_file());
    let _ = fs::remove_dir_all(runtime);
}

#[test]
fn get_setting_before_set_returns_unknown() {
    let daemon = TestDaemon::start();
    // Getting a key that was never set should return UnknownSetting.
    let resp = daemon.request(
        Request::GetSetting {
            key: "nonexistent.key".into(),
        },
        "unknown-1",
    );
    assert!(resp.error.is_some());
    assert_eq!(
        resp.error.unwrap().code,
        ErrorCode::UnknownSetting,
        "expected UnknownSetting for nonexistent key"
    );

    // Now set appearance.profile (a valid key) and verify SettingUpdated.
    let set_resp = daemon.request(
        Request::SetSetting {
            key: "appearance.profile".into(),
            value: serde_json::json!("material-oled"),
        },
        "set-profile-1",
    );
    assert!(set_resp.error.is_none());
    assert!(matches!(
        set_resp.result,
        Some(noxflow_ipc::Response::SettingUpdated(_))
    ));

    // Getting it back should return the value we just set.
    let get_resp = daemon.request(
        Request::GetSetting {
            key: "appearance.profile".into(),
        },
        "get-profile-1",
    );
    assert!(get_resp.error.is_none());
    match get_resp.result {
        Some(noxflow_ipc::Response::Setting(sv)) => {
            assert_eq!(sv.key, "appearance.profile");
            assert_eq!(sv.value, serde_json::json!("material-oled"));
        }
        other => panic!("expected Setting, got {other:?}"),
    }
}

#[test]
fn set_setting_validates_bad_density() {
    let daemon = TestDaemon::start();
    let resp = daemon.request(
        Request::SetSetting {
            key: "appearance.density".into(),
            value: serde_json::json!("ultra"),
        },
        "density-bad-1",
    );
    assert!(resp.result.is_none());
    let err = resp
        .error
        .expect("expected an error for invalid density value");
    assert_eq!(
        err.code,
        ErrorCode::InvalidParams,
        "expected InvalidParams for bad density, got {:?}",
        err.code
    );
}

#[test]
fn get_state_includes_settings_field() {
    let daemon = TestDaemon::start();
    let resp = daemon.request(Request::GetState, "state-settings-1");
    assert!(resp.error.is_none());
    match resp.result {
        Some(noxflow_ipc::Response::State(state)) => {
            // The settings field must be present (even if empty).
            let _settings_map = &state.settings;
        }
        other => panic!("expected State, got {other:?}"),
    }
}

#[test]
fn version_negotiation_rejects_unsupported() {
    let daemon = TestDaemon::start();
    let socket = daemon.socket();

    // Send a request with protocol_version = 99 (unsupported).
    let mut stream = UnixStream::connect(&socket).unwrap();
    let envelope = serde_json::json!({
        "version": 99,
        "id": "bad-version-1",
        "method": "ping",
    });
    writeln!(stream, "{}", serde_json::to_string(&envelope).unwrap()).unwrap();
    let mut line = String::new();
    BufReader::new(&stream)
        .read_line(&mut line)
        .expect("should read response");
    let resp: ResponseEnvelope = serde_json::from_str(&line).unwrap();
    assert_eq!(resp.request_id, "bad-version-1");
    let err = resp
        .error
        .expect("expected error for unsupported protocol version");
    assert_eq!(err.code, ErrorCode::UnsupportedProtocolVersion);

    // The daemon should still be alive — verify with a normal Ping.
    let ping = daemon.request(Request::Ping, "ping-after-version");
    assert!(ping.result.is_some());
}

#[test]
fn many_concurrent_requests() {
    let daemon = Arc::new(TestDaemon::start());
    let handles: Vec<_> = (0..20)
        .map(|i| {
            let daemon = Arc::clone(&daemon);
            thread::spawn(move || {
                let id = format!("concurrent-{i}");
                let resp = daemon.request(Request::GetVersion, &id);
                assert_eq!(resp.request_id, id, "request_id must be echoed");
                assert!(
                    resp.error.is_none(),
                    "unexpected error on request {id}: {:?}",
                    resp.error
                );
                assert!(matches!(
                    resp.result,
                    Some(noxflow_ipc::Response::Version(_))
                ));
            })
        })
        .collect();
    for handle in handles {
        handle.join().expect("thread panicked");
    }
}

#[test]
fn rapid_requests_do_not_crash_daemon() {
    let daemon = TestDaemon::start();
    let socket = daemon.socket();
    let mut stream = UnixStream::connect(&socket).unwrap();

    // Write 50 brightness_set actions rapidly on the same connection.
    for i in 0..50 {
        let envelope = RequestEnvelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: format!("rapid-{i}"),
            request: Request::RunAction {
                action: Action::BrightnessSet {
                    percentage: (i % 100) as u8,
                },
            },
        };
        writeln!(stream, "{}", serde_json::to_string(&envelope).unwrap()).unwrap();
    }

    // Read all 50 responses.
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    for i in 0..50 {
        let mut line = String::new();
        reader
            .read_line(&mut line)
            .expect("should read response line");
        assert!(!line.is_empty(), "response {i} should not be empty");
        let resp: ResponseEnvelope =
            serde_json::from_str(&line).unwrap_or_else(|e| panic!("invalid JSON on response {i}: {e} — line: {line}"));
        assert_eq!(resp.request_id, format!("rapid-{i}"));
    }

    // Verify the daemon is still alive.
    let ping = daemon.request(Request::Ping, "ping-after-rapid");
    assert!(
        ping.result.is_some(),
        "daemon should still respond after 50 rapid requests"
    );
}

#[test]
fn get_setting_after_set_returns_value() {
    let daemon = TestDaemon::start();
    // Set the setting first.
    let set_resp = daemon.request(
        Request::SetSetting {
            key: "appearance.profile".into(),
            value: serde_json::json!("material-oled"),
        },
        "set-prof-1",
    );
    assert!(set_resp.error.is_none(), "set_setting should succeed");
    assert!(matches!(
        set_resp.result,
        Some(noxflow_ipc::Response::SettingUpdated(_))
    ));

    // Now get it and verify the value round-trips.
    let get_resp = daemon.request(
        Request::GetSetting {
            key: "appearance.profile".into(),
        },
        "get-prof-1",
    );
    assert!(get_resp.error.is_none(), "get_setting should succeed");
    match get_resp.result {
        Some(noxflow_ipc::Response::Setting(sv)) => {
            assert_eq!(sv.key, "appearance.profile");
            assert_eq!(sv.value, serde_json::json!("material-oled"));
        }
        other => panic!("expected Setting response, got {other:?}"),
    }
}

#[test]
fn settings_survive_restart() {
    // Use a dedicated state directory that persists across daemon restarts.
    let state_dir = std::env::temp_dir().join(format!(
        "noxd-restart-test-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir_all(&state_dir).unwrap();

    let runtime_dir = std::env::temp_dir().join(format!(
        "noxd-restart-runtime-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir(&runtime_dir).unwrap();
    fs::set_permissions(&runtime_dir, fs::Permissions::from_mode(0o700)).unwrap();

    // --- First daemon instance: set a setting and shut down ---
    let child = Command::new(env!("CARGO_BIN_EXE_noxd"))
        .env("XDG_RUNTIME_DIR", &runtime_dir)
        .env("XDG_STATE_HOME", &state_dir)
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let socket = runtime_dir.join("noxflow/noxd.sock");
    for _ in 0..100 {
        if socket.exists() {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
    assert!(socket.exists(), "first daemon should create socket");

    // Set appearance.profile on the first daemon.
    let mut stream = UnixStream::connect(&socket).unwrap();
    let envelope = RequestEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id: "persist-set-1".into(),
        request: Request::SetSetting {
            key: "appearance.profile".into(),
            value: serde_json::json!("material-oled"),
        },
    };
    writeln!(stream, "{}", serde_json::to_string(&envelope).unwrap()).unwrap();
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).unwrap();
    let resp: ResponseEnvelope = serde_json::from_str(&line).unwrap();
    assert!(resp.error.is_none(), "set_setting should succeed on first daemon");

    // Shut down the first daemon gracefully.
    unsafe {
        libc::kill(child.id() as i32, libc::SIGTERM);
    }
    let mut first_daemon = Some(child);
    first_daemon.as_mut().unwrap().wait().unwrap();

    // Wait for the socket to be cleaned up.
    for _ in 0..100 {
        if !socket.exists() {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }

    // --- Second daemon instance: verify the setting persists ---
    let mut child2 = Command::new(env!("CARGO_BIN_EXE_noxd"))
        .env("XDG_RUNTIME_DIR", &runtime_dir)
        .env("XDG_STATE_HOME", &state_dir)
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    for _ in 0..100 {
        if socket.exists() && UnixStream::connect(&socket).is_ok() {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }

    // Get the setting on the new daemon — it should match what we set before.
    let mut stream2 = UnixStream::connect(&socket).unwrap();
    let envelope2 = RequestEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id: "persist-get-1".into(),
        request: Request::GetSetting {
            key: "appearance.profile".into(),
        },
    };
    writeln!(stream2, "{}", serde_json::to_string(&envelope2).unwrap()).unwrap();
    let mut line2 = String::new();
    BufReader::new(stream2)
        .read_line(&mut line2)
        .expect("should read response from second daemon");
    let resp2: ResponseEnvelope = serde_json::from_str(&line2).unwrap();
    assert!(
        resp2.error.is_none(),
        "get_setting should succeed on second daemon"
    );
    match resp2.result {
        Some(noxflow_ipc::Response::Setting(sv)) => {
            assert_eq!(sv.key, "appearance.profile");
            assert_eq!(
                sv.value,
                serde_json::json!("material-oled"),
                "setting should survive daemon restart"
            );
        }
        other => panic!("expected Setting, got {other:?}"),
    }

    // Clean up the second daemon.
    unsafe {
        libc::kill(child2.id() as i32, libc::SIGTERM);
    }
    drop(first_daemon);
    let _ = child2.wait();
    let _ = fs::remove_dir_all(&runtime_dir);
    let _ = fs::remove_dir_all(&state_dir);
}
