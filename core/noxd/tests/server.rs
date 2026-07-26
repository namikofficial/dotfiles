use noxflow_ipc::{Request, RequestEnvelope, ResponseEnvelope, PROTOCOL_VERSION};
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
