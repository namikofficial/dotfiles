use noxflow_ipc::{
    ProviderState, ProviderStatus, Response, ResponseEnvelope, State, PROTOCOL_VERSION,
};
use std::{
    collections::BTreeMap,
    io::{BufRead, BufReader, Write},
    os::unix::net::UnixListener,
    process::Command,
    thread,
    time::Duration,
};

fn noxctl() -> Command {
    Command::new(env!("CARGO_BIN_EXE_noxctl"))
}

#[test]
fn help_lists_the_stable_command_groups() {
    let output = noxctl().arg("--help").output().unwrap();
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    for command in [
        "status",
        "provider",
        "audio",
        "brightness",
        "power",
        "network",
        "bluetooth",
        "media",
        "shell",
        "profile",
        "config",
        "logs",
        "doctor",
    ] {
        assert!(text.contains(command), "missing {command} in help: {text}");
    }
}

#[test]
fn unavailable_daemon_has_stable_exit_code_and_error() {
    let socket = std::env::temp_dir().join(format!("noxctl-missing-{}", std::process::id()));
    let output = noxctl()
        .args(["--socket", socket.to_str().unwrap(), "status"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("noxd unavailable"));
}

#[test]
fn invalid_arguments_have_usage_exit_code() {
    let output = noxctl()
        .args(["network", "connect", "not-a-uuid"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("valid UUID"));
}

#[test]
fn completions_are_generated_for_each_shell() {
    for shell in ["bash", "zsh", "fish"] {
        let output = noxctl().args(["completions", shell]).output().unwrap();
        assert!(output.status.success());
        assert!(!output.stdout.is_empty());
    }
}

fn mock_socket(response: ResponseEnvelope, delay: Option<Duration>) -> String {
    let path = std::env::temp_dir().join(format!(
        "noxctl-mock-{}-{}.sock",
        std::process::id(),
        rand_suffix()
    ));
    let listener = UnixListener::bind(&path).unwrap();
    thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        if let Some(delay) = delay {
            thread::sleep(delay);
        }
        let mut request = String::new();
        let _ = BufReader::new(stream.try_clone().unwrap()).read_line(&mut request);
        writeln!(stream, "{}", serde_json::to_string(&response).unwrap()).unwrap();
    });
    path.to_str().unwrap().to_owned()
}

fn rand_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

#[test]
fn status_human_and_json_output_are_stable() {
    let mut providers = BTreeMap::new();
    providers.insert(
        "audio".into(),
        ProviderState {
            provider: "audio".into(),
            status: ProviderStatus::Available,
            data: BTreeMap::new(),
        },
    );
    let response = ResponseEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id: "status".into(),
        result: Some(Response::State(State {
            timestamp: 42,
            providers,
            settings: BTreeMap::new(),
        })),
        error: None,
    };
    let socket = mock_socket(response.clone(), None);
    let human = noxctl()
        .args(["--socket", &socket, "status"])
        .output()
        .unwrap();
    assert!(human.status.success());
    assert_eq!(
        String::from_utf8_lossy(&human.stdout),
        "NoxFlow status (timestamp 42)\n  audio        Available\n"
    );

    let socket = mock_socket(response, None);
    let json = noxctl()
        .args(["--json", "--socket", &socket, "status"])
        .output()
        .unwrap();
    assert!(json.status.success());
    let value: serde_json::Value = serde_json::from_slice(&json.stdout).unwrap();
    assert_eq!(value["timestamp"], 42);
    assert_eq!(value["providers"]["audio"]["status"], "available");
}

#[test]
fn protocol_mismatch_has_exit_code_three() {
    let response = ResponseEnvelope {
        protocol_version: 99,
        request_id: "status".into(),
        result: Some(Response::Pong),
        error: None,
    };
    let socket = mock_socket(response, None);
    let output = noxctl()
        .args(["--socket", &socket, "status"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&output.stderr).contains("protocol mismatch"));
}

#[test]
fn socket_timeout_has_stable_exit_code() {
    let response = ResponseEnvelope {
        protocol_version: PROTOCOL_VERSION,
        request_id: "status".into(),
        result: Some(Response::Pong),
        error: None,
    };
    let socket = mock_socket(response, Some(Duration::from_millis(200)));
    let output = noxctl()
        .args(["--timeout-ms", "20", "--socket", &socket, "status"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("timed out"));
}
