//! LocalSend v2 (Quick Share) transfer provider.
//!
//! Implements the LocalSend REST protocol v2 directly so the shell can own the
//! full transfer workflow — device discovery, receive accept/decline, send with
//! progress — without the LocalSend Flutter app.
//!
//! Architecture:
//!   - A dedicated Tokio runtime owns the HTTPS receive server (port 53317),
//!     UDP multicast discovery, and per-transfer upload/download tasks.
//!   - The std mpsc `CommandRequest` channel (matching other providers) is
//!     bridged into the Tokio runtime via a tokio mpsc channel.
//!   - State is published to the EventBus as provider `transfer` with
//!     event_type `discovery`, `session`, `progress`, `completed`.
//!
//! Protocol reference: https://github.com/localsend/protocol (v2.1).
//!
//! The self-signed cert is generated once with the `openssl` CLI into
//! `<state>/localsend/` (LocalSend peers accept self-signed certs; the
//! fingerprint is the SHA-256 of the DER cert).

use crate::{EventBus, ProviderEvent};
use http_body_util::{BodyExt, Full};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    fs,
    io::Write,
    net::IpAddr,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::Duration,
};

pub const PROVIDER: &str = "transfer";
pub const SERVER_PORT: u16 = 53317;
const MULTICAST_ADDR: &str = "224.0.0.167";
const MULTICAST_PORT: u16 = 53317;
const ALIAS: &str = "NoxFlow Desktop";
const DEVICE_TYPE: &str = "desktop";
const PROTOCOL_VERSION: &str = "2.0";
const SESSION_TTL_SECS: u64 = 300;

// ── LocalSend protocol types ──

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DeviceInfo {
    alias: String,
    version: String,
    #[serde(default)]
    device_model: Option<String>,
    #[serde(default)]
    device_type: Option<String>,
    #[serde(default)]
    fingerprint: String,
    #[serde(default)]
    port: u16,
    #[serde(default)]
    protocol: String,
    #[serde(default)]
    download: bool,
    #[serde(default)]
    announce: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileMeta {
    id: String,
    #[serde(rename = "fileName")]
    file_name: String,
    size: u64,
    #[serde(rename = "fileType", default)]
    file_type: String,
    #[serde(default)]
    sha256: Option<String>,
    #[serde(default)]
    preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PrepareUploadRequest {
    info: DeviceInfo,
    files: BTreeMap<String, FileMeta>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[allow(non_snake_case)]
struct PrepareUploadResponse {
    sessionId: String,
    files: BTreeMap<String, String>,
}

// ── Provider state (published to the EventBus) ──

#[derive(Debug, Clone, Default)]
pub struct TransferState {
    pub devices: Vec<Peer>,
    pub sessions: Vec<SessionInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Peer {
    pub id: String,
    pub alias: String,
    pub ip: String,
    pub port: u16,
    pub device_type: String,
    pub protocol: String,
    pub fingerprint: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: String,
    pub direction: String, // in | out
    pub peer_alias: String,
    pub peer_ip: String,
    pub files: Vec<SessionFile>,
    pub state: String,
    pub error: Option<String>,
    pub created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionFile {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub transferred: u64,
    pub path: Option<String>,
}

#[derive(Debug, Clone)]
pub enum CommandRequest {
    Discover,
    Send {
        peer_id: String,
        paths: Vec<String>,
    },
    Accept {
        session_id: String,
    },
    Decline {
        session_id: String,
    },
    Cancel {
        session_id: String,
    },
}

#[derive(Clone)]
pub struct Control {
    sender: mpsc::Sender<CommandRequest>,
}

impl Control {
    pub fn send(&self, command: CommandRequest) -> Result<(), String> {
        self.sender.send(command).map_err(|e| e.to_string())
    }
}

// ── State storage (shared between the Tokio runtime and the sync side) ──

struct Inner {
    bus: EventBus,
    state: std::sync::Mutex<TransferState>,
    sessions: std::sync::Mutex<HashMap<String, SessionData>>,
    received_dir: PathBuf,
}

struct SessionData {
    info: SessionInfo,
    file_tokens: HashMap<String, String>,
    #[allow(dead_code)] // reserved for resumable/retry sends
    send_files: Vec<(String, PathBuf, u64)>, // file_id, path, size
}

impl Inner {
    // Full state (devices + sessions) as the provider snapshot.
    fn full_snapshot(&self) -> Value {
        let state = self.state.lock().unwrap();
        json!({ "devices": state.devices, "sessions": state.sessions })
    }

    fn publish_discovery(&self) {
        let state = self.state.lock().unwrap().clone();
        self.bus
            .publish(TransferEvent {
                event_type: "discovery",
                data: json!({ "devices": state.devices }),
                snapshot_value: self.full_snapshot(),
            })
            .ok();
    }

    fn publish_sessions(&self) {
        let state = self.state.lock().unwrap().clone();
        self.bus
            .publish(TransferEvent {
                event_type: "sessions",
                data: json!({ "sessions": state.sessions }),
                snapshot_value: self.full_snapshot(),
            })
            .ok();
    }

    fn add_session(&self, session: SessionData) {
        self.sessions.lock().unwrap().insert(session.info.id.clone(), session);
        self.refresh_state();
        self.publish_sessions();
    }

    fn remove_session(&self, id: &str) {
        self.sessions.lock().unwrap().remove(id);
        self.refresh_state();
        self.publish_sessions();
    }

    fn refresh_state(&self) {
        let mut state = self.state.lock().unwrap();
        let sessions = self.sessions.lock().unwrap();
        state.sessions = sessions.values().map(|s| s.info.clone()).collect();
    }
}

struct TransferEvent {
    event_type: &'static str,
    data: Value,
    // Full state (devices + sessions) to publish as the provider snapshot so
    // subscribers always see the complete picture, not just the delta.
    snapshot_value: Value,
}

impl ProviderEvent for TransferEvent {
    fn provider(&self) -> &str {
        PROVIDER
    }
    fn event_type(&self) -> &str {
        self.event_type
    }
    fn data(&self) -> BTreeMap<String, Value> {
        self.data
            .as_object()
            .map(|m| m.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
            .unwrap_or_default()
    }
    fn snapshot(&self) -> ProviderState {
        ProviderState {
            provider: PROVIDER.into(),
            status: ProviderStatus::Available,
            data: self
                .snapshot_value
                .as_object()
                .map(|m| m.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
                .unwrap_or_default(),
        }
    }
}

fn timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

// ── Cert generation (once per install) ──

fn ensure_cert(state_dir: &Path) -> Result<(PathBuf, PathBuf), String> {
    let dir = state_dir.join("localsend");
    fs::create_dir_all(&dir).map_err(|e| format!("create cert dir: {e}"))?;
    let cert_path = dir.join("cert.pem");
    let key_path = dir.join("key.pem");
    if cert_path.exists() && key_path.exists() {
        return Ok((cert_path, key_path));
    }
    // Generate a self-signed cert valid 10 years, SAN=IP:0.0.0.0 + localhost.
    let status = std::process::Command::new("openssl")
        .args([
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-keyout",
            key_path.to_str().unwrap(),
            "-out",
            cert_path.to_str().unwrap(),
            "-days",
            "3650",
            "-nodes",
            "-subj",
            "/CN=NoxFlow",
            "-addext",
            "subjectAltName=IP:0.0.0.0,IP:127.0.0.1,DNS:localhost",
        ])
        .status()
        .map_err(|e| format!("openssl launch: {e}"))?;
    if !status.success() {
        return Err("openssl failed to generate cert".into());
    }
    Ok((cert_path, key_path))
}

// ── TLS config ──

fn tls_config(cert_path: &Path, key_path: &Path) -> Result<Arc<rustls::ServerConfig>, String> {
    let cert_pem = fs::read_to_string(cert_path).map_err(|e| format!("read cert: {e}"))?;
    let key_pem = fs::read_to_string(key_path).map_err(|e| format!("read key: {e}"))?;
    let certs = pem::parse_many(&cert_pem)
        .map_err(|e| format!("parse cert: {e}"))?
        .iter()
        .map(|p| rustls::pki_types::CertificateDer::from(p.contents().to_vec()))
        .collect();
    let key =
        pem::parse_many(&key_pem)
            .map_err(|e| format!("parse key: {e}"))?
            .into_iter()
            .find(|p| p.tag() == "PRIVATE KEY" || p.tag() == "RSA PRIVATE KEY")
            .ok_or_else(|| "no private key found".to_string())?;
    let key = rustls::pki_types::PrivateKeyDer::Pkcs8(
        key.contents().to_vec().into(),
    );
    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|e| format!("tls config: {e}"))?;
    Ok(Arc::new(config))
}

// ── Entry point ──

pub fn start(bus: EventBus, stop: Arc<AtomicBool>, state_dir: PathBuf) -> (thread::JoinHandle<()>, Control) {
    let (sender, receiver) = mpsc::channel();
    let control = Control { sender };
    let thread = thread::spawn(move || {
        let inner = Arc::new(Inner {
            bus,
            state: std::sync::Mutex::new(TransferState::default()),
            sessions: std::sync::Mutex::new(HashMap::new()),
            received_dir: state_dir.join("received"),
        });
        if let Err(e) = fs::create_dir_all(&inner.received_dir) {
            eprintln!("[transfer] create received dir: {e}");
        }
        run(inner, stop, receiver);
    });
    (thread, control)
}

fn run(
    inner: Arc<Inner>,
    stop: Arc<AtomicBool>,
    receiver: mpsc::Receiver<CommandRequest>,
) {
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            eprintln!("[transfer] tokio runtime: {e}");
            return;
        }
    };

    // Bridge the std channel into the Tokio runtime.
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<CommandRequest>();
    thread::spawn(move || {
        while let Ok(cmd) = receiver.recv() {
            if tx.send(cmd).is_err() {
                break;
            }
        }
    });

    runtime.block_on(async move {
        let state_dir = inner
            .received_dir
            .parent()
            .unwrap_or(Path::new("/tmp"))
            .to_path_buf();
        let cert_path = match ensure_cert(&state_dir) {
            Ok((c, _)) => c,
            Err(e) => {
                eprintln!("[transfer] cert: {e}");
                return;
            }
        };
        let key_path = state_dir.join("localsend/key.pem");
        let tls = match tls_config(&cert_path, &key_path) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[transfer] tls: {e}");
                return;
            }
        };

        // Start the HTTPS receive server.
        let server_inner = Arc::clone(&inner);
        let server_tls = Arc::clone(&tls);
        let server_stop = Arc::clone(&stop);
        tokio::spawn(async move {
            run_server(server_inner, server_tls, server_stop).await;
        });

        // Start periodic multicast discovery.
        let disc_inner = Arc::clone(&inner);
        let disc_stop = Arc::clone(&stop);
        tokio::spawn(async move {
            discovery_loop(disc_inner, disc_stop).await;
        });

        // Command dispatch loop.
        while !stop.load(Ordering::Relaxed) {
            tokio::select! {
                Some(cmd) = rx.recv() => {
                    let inner = Arc::clone(&inner);
                    let tls = Arc::clone(&tls);
                    tokio::spawn(async move {
                        handle_command(inner, tls, cmd).await;
                    });
                }
                _ = tokio::time::sleep(Duration::from_millis(200)) => {
                    // Housekeeping: expire stale sessions.
                    expire_sessions(Arc::clone(&inner));
                }
            }
        }
    });
}

fn expire_sessions(inner: Arc<Inner>) {
    let now = timestamp();
    let mut stale = Vec::new();
    {
        let sessions = inner.sessions.lock().unwrap();
        for (id, s) in sessions.iter() {
            if matches!(s.info.state.as_str(), "incoming" | "offered") && now - s.info.created_at > SESSION_TTL_SECS {
                stale.push(id.clone());
            }
        }
    }
    for id in stale {
        inner.remove_session(&id);
    }
}

async fn handle_command(inner: Arc<Inner>, tls: Arc<rustls::ServerConfig>, cmd: CommandRequest) {
    match cmd {
        CommandRequest::Discover => {
            discover_once(Arc::clone(&inner)).await;
        }
        CommandRequest::Send { peer_id, paths } => {
            send_to_peer(inner, tls, &peer_id, &paths).await;
        }
        CommandRequest::Accept { session_id } => {
            accept_session(Arc::clone(&inner), tls, &session_id).await;
        }
        CommandRequest::Decline { session_id } => {
            decline_session(inner, &session_id);
        }
        CommandRequest::Cancel { session_id } => {
            cancel_session(inner, &session_id);
        }
    }
}

// ── Discovery ──

async fn discovery_loop(inner: Arc<Inner>, stop: Arc<AtomicBool>) {
    while !stop.load(Ordering::Relaxed) {
        discover_once(Arc::clone(&inner)).await;
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

async fn discover_once(inner: Arc<Inner>) {
    // Send a UDP multicast announcement and listen for replies.
    // Inbound peers announce themselves; we also probe via the register
    // handshake against the multicast group.
    let socket = match tokio::net::UdpSocket::bind(("0.0.0.0", MULTICAST_PORT)).await {
        Ok(s) => s,
        Err(_) => {
            // Port busy (e.g. LocalSend app running) — bind ephemeral for send.
            match tokio::net::UdpSocket::bind(("0.0.0.0", 0)).await {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("[transfer] udp bind: {e}");
                    return;
                }
            }
        }
    };
    socket.set_multicast_loop_v4(true).ok();
    socket.join_multicast_v4(MULTICAST_ADDR.parse().unwrap(), "0.0.0.0".parse().unwrap()).ok();

    let info = DeviceInfo {
        alias: ALIAS.into(),
        version: PROTOCOL_VERSION.into(),
        device_model: Some("NoxFlow".into()),
        device_type: Some(DEVICE_TYPE.into()),
        fingerprint: String::new(),
        port: SERVER_PORT,
        protocol: "https".into(),
        download: true,
        announce: Some(true),
    };
    let body = serde_json::to_string(&info).unwrap_or_default();

    let mut seen = HashSet::new();
    let deadline = std::time::Instant::now() + Duration::from_millis(800);
    while std::time::Instant::now() < deadline {
        socket
            .send_to(body.as_bytes(), (MULTICAST_ADDR, MULTICAST_PORT))
            .await
            .ok();
        let mut buf = [0u8; 4096];
        let recv = tokio::time::timeout(Duration::from_millis(100), socket.recv_from(&mut buf)).await;
        if let Ok(Ok((len, src))) = recv {
            let ip = src.ip();
            if ip.is_loopback() { continue; }
            if !seen.insert(ip) { continue; }
            if let Ok(text) = std::str::from_utf8(&buf[..len]) {
                if let Ok(reply) = serde_json::from_str::<DeviceInfo>(text) {
                    if reply.alias != ALIAS {
                        add_peer(&inner, &ip, &reply);
                    }
                }
            }
        }
    }
    inner.publish_discovery();
}

fn add_peer(inner: &Arc<Inner>, ip: &IpAddr, info: &DeviceInfo) {
    let peer = Peer {
        id: format!("{}:{}", ip, info.port),
        alias: info.alias.clone(),
        ip: ip.to_string(),
        port: info.port,
        device_type: info.device_type.clone().unwrap_or_default(),
        protocol: info.protocol.clone(),
        fingerprint: info.fingerprint.clone(),
    };
    let mut state = inner.state.lock().unwrap();
    state.devices.retain(|p| p.ip != ip.to_string());
    state.devices.push(peer);
}

// ── HTTPS server (receiving) ──

use std::collections::HashSet;

async fn run_server(inner: Arc<Inner>, tls: Arc<rustls::ServerConfig>, stop: Arc<AtomicBool>) {
    let listener = match tokio::net::TcpListener::bind(("0.0.0.0", SERVER_PORT)).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[transfer] server bind :{SERVER_PORT}: {e}");
            return;
        }
    };

    loop {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        let (stream, _) = match listener.accept().await {
            Ok(x) => x,
            Err(_) => continue,
        };
        let tls = Arc::clone(&tls);
        let inner = Arc::clone(&inner);
        tokio::spawn(async move {
            let tls_stream = match tokio_rustls::TlsAcceptor::from(tls)
                .accept(stream)
                .await
            {
                Ok(s) => s,
                Err(_) => return,
            };
            let io = hyper_util::rt::TokioIo::new(tls_stream);
            let svc = hyper::service::service_fn(move |req| handle_http(inner.clone(), req));
            let acceptor = hyper_util::server::conn::auto::Builder::new(hyper_util::rt::TokioExecutor::new());
            let _ = acceptor.serve_connection_with_upgrades(io, svc).await;
        });
    }
}

async fn handle_http(
    inner: Arc<Inner>,
    req: hyper::Request<hyper::body::Incoming>,
) -> Result<hyper::Response<Full<bytes::Bytes>>, hyper::Error> {
    let method = req.method().clone();
    let path = req.uri().path().to_owned();
    let query: HashMap<String, String> = req
        .uri()
        .query()
        .map(|q| serde_urlencoded::from_str(q).unwrap_or_default())
        .unwrap_or_default();

    let response = match (method.as_str(), path.as_str()) {
        ("GET", "/api/localsend/v2/info") => {
            let info = DeviceInfo {
                alias: ALIAS.into(),
                version: PROTOCOL_VERSION.into(),
                device_model: Some("NoxFlow".into()),
                device_type: Some(DEVICE_TYPE.into()),
                fingerprint: String::new(),
                port: SERVER_PORT,
                protocol: "https".into(),
                download: true,
                announce: None,
            };
            json_response(serde_json::to_string(&info).unwrap_or_default())
        }
        ("POST", "/api/localsend/v2/register") => {
            // Respond to a discovery probe from a peer.
            let info = DeviceInfo {
                alias: ALIAS.into(),
                version: PROTOCOL_VERSION.into(),
                device_model: Some("NoxFlow".into()),
                device_type: Some(DEVICE_TYPE.into()),
                fingerprint: String::new(),
                port: SERVER_PORT,
                protocol: "https".into(),
                download: true,
                announce: None,
            };
            json_response(serde_json::to_string(&info).unwrap_or_default())
        }
        ("POST", "/api/localsend/v2/prepare-upload") => {
            // Peer wants to send us files. Parse metadata, create an incoming
            // session in "incoming" state, respond with session id + tokens.
            let peer_ip = req
                .headers()
                .get("x-forwarded-for")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("unknown")
                .to_owned();
            let body = read_body(req).await;
            match serde_json::from_str::<PrepareUploadRequest>(&body) {
                Ok(meta) => {
                    let session_id = format!("in-{}", timestamp());
                    let files: BTreeMap<String, SessionFile> = meta
                        .files
                        .iter()
                        .map(|(id, f)| {
                            (
                                id.clone(),
                                SessionFile {
                                    id: id.clone(),
                                    name: f.file_name.clone(),
                                    size: f.size,
                                    transferred: 0,
                                    path: None,
                                },
                            )
                        })
                        .collect();
                    let mut tokens = HashMap::new();
                    for id in meta.files.keys() {
                        tokens.insert(id.clone(), format!("tok-{}-{}", timestamp(), id));
                    }
                    let session = SessionData {
                        info: SessionInfo {
                            id: session_id.clone(),
                            direction: "in".into(),
                            peer_alias: meta.info.alias.clone(),
                            peer_ip,
                            files: files.values().cloned().collect(),
                            state: "incoming".into(),
                            error: None,
                            created_at: timestamp(),
                        },
                        file_tokens: tokens.clone(),
                        send_files: Vec::new(),
                    };
                    inner.add_session(session);
                    let resp = PrepareUploadResponse {
                        sessionId: session_id,
                        files: meta
                            .files
                            .keys()
                            .filter_map(|id| tokens.get(id).map(|token| (id.clone(), token.clone())))
                            .collect(),
                    };
                    json_response(serde_json::to_string(&resp).unwrap_or_default())
                }
                Err(e) => {
                    status_response(400, format!("invalid body: {e}"))
                }
            }
        }
        ("POST", "/api/localsend/v2/upload") => {
            // Peer uploads a file. Validate token, stream to disk with progress.
            let session_id = query.get("sessionId").cloned().unwrap_or_default();
            let file_id = query.get("fileId").cloned().unwrap_or_default();
            let token = query.get("token").cloned().unwrap_or_default();
            match receive_upload(&inner, &session_id, &file_id, &token, req).await {
                Ok(size) => {
                    update_file_progress(&inner, &session_id, &file_id, size);
                    empty_response(204)
                }
                Err(msg) => status_response(400, msg),
            }
        }
        ("POST", "/api/localsend/v2/cancel") => {
            let session_id = query.get("sessionId").cloned().unwrap_or_default();
            inner.remove_session(&session_id);
            empty_response(204)
        }
        _ => status_response(404, "not found".to_string()),
    };
    Ok(response)
}

async fn read_body(req: hyper::Request<hyper::body::Incoming>) -> String {
    let bytes = match req.into_body().collect().await {
        Ok(b) => b.to_bytes(),
        Err(_) => return String::new(),
    };
    String::from_utf8_lossy(&bytes).to_string()
}

async fn receive_upload(
    inner: &Arc<Inner>,
    session_id: &str,
    file_id: &str,
    token: &str,
    req: hyper::Request<hyper::body::Incoming>,
) -> Result<u64, String> {
    // Look up the session + file.
    let (file_name, file_size, expected_token) = {
        let sessions = inner.sessions.lock().unwrap();
        let session = sessions.get(session_id).ok_or("session not found")?;
        if session.info.direction != "in" {
            return Err("not an inbound session".into());
        }
        if !matches!(session.info.state.as_str(), "incoming" | "transferring") {
            return Err(format!("transfer {}", session.info.state));
        }
        let expected = session.file_tokens.get(file_id).ok_or("unknown file")?.clone();
        let f = session.info.files.iter().find(|f| f.id == file_id).ok_or("unknown file")?;
        (f.name.clone(), f.size, expected)
    };
    if expected_token != token {
        return Err("invalid token".into());
    }

    // Keep peer-provided names inside the receive directory.
    let safe_name = Path::new(&file_name)
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty() && *name != "." && *name != "..")
        .unwrap_or("received-file");
    let dest = inner.received_dir.join(safe_name);
    let mut file = fs::File::create(&dest).map_err(|e| format!("create: {e}"))?;
    let mut body = req.into_body();
    let mut written: u64 = 0;
    // Stream body frames.
    while let Some(frame) = body.frame().await {
        match frame {
            Ok(f) => {
                if let Some(data) = f.data_ref() {
                    let bytes = data.iter().copied().collect::<Vec<u8>>();
                    file.write_all(&bytes).map_err(|e| format!("write: {e}"))?;
                    written += bytes.len() as u64;
                    update_file_progress(inner, session_id, file_id, written);
                }
            }
            Err(e) => return Err(format!("stream: {e}")),
        }
    }
    file.flush().ok();
    if written != file_size {
        return Err(format!("size mismatch: wrote {written} of {file_size}"));
    }
    Ok(written)
}

fn update_file_progress(inner: &Arc<Inner>, session_id: &str, file_id: &str, transferred: u64) {
    let mut sessions = inner.sessions.lock().unwrap();
    if let Some(session) = sessions.get_mut(session_id) {
        for f in &mut session.info.files {
            if f.id == file_id {
                f.transferred = transferred;
                break;
            }
        }
        // If all files complete, mark completed.
        let all_done = session
            .info
            .files
            .iter()
            .all(|f| f.size > 0 && f.transferred >= f.size);
        if all_done && session.info.state != "completed" {
            session.info.state = "completed".into();
        } else if session.info.state == "incoming" && transferred > 0 {
            session.info.state = "transferring".into();
        }
    }
    drop(sessions);
    inner.refresh_state();
    inner.publish_sessions();
}

fn json_response(body: String) -> hyper::Response<Full<bytes::Bytes>> {
    hyper::Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(Full::new(bytes::Bytes::from(body)))
        .unwrap()
}

fn empty_response(code: u16) -> hyper::Response<Full<bytes::Bytes>> {
    hyper::Response::builder()
        .status(code)
        .body(Full::new(bytes::Bytes::new()))
        .unwrap()
}

fn status_response(code: u16, msg: String) -> hyper::Response<Full<bytes::Bytes>> {
    hyper::Response::builder()
        .status(code)
        .body(Full::new(bytes::Bytes::from(msg)))
        .unwrap()
}

// ── Sending ──

async fn send_to_peer(inner: Arc<Inner>, _tls: Arc<rustls::ServerConfig>, peer_id: &str, paths: &[String]) {
    let peer = {
        let state = inner.state.lock().unwrap();
        state.devices.iter().find(|p| p.id == peer_id).cloned()
    };
    let peer = match peer {
        Some(p) => p,
        None => {
            inner.bus.publish(TransferEvent {
                event_type: "sessions",
                data: json!({ "error": "peer not found" }),
                snapshot_value: inner.full_snapshot(),
            }).ok();
            return;
        }
    };

    // Build file metadata.
    let mut files: BTreeMap<String, FileMeta> = BTreeMap::new();
    let mut path_map: Vec<(String, PathBuf, u64)> = Vec::new();
    for (idx, path) in paths.iter().enumerate() {
        let p = PathBuf::from(path);
        let meta = match fs::metadata(&p) {
            Ok(m) => m,
            Err(e) => {
                eprintln!("[transfer] file metadata {path}: {e}");
                continue;
            }
        };
        let id = format!("f{idx}");
        let name = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        files.insert(
            id.clone(),
            FileMeta {
                id: id.clone(),
                file_name: name,
                size: meta.len(),
                file_type: mime_guess_for(&path),
                sha256: None,
                preview: None,
            },
        );
        path_map.push((id.clone(), p, meta.len()));
    }
    if files.is_empty() {
        inner.bus.publish(TransferEvent {
            event_type: "sessions",
            data: json!({ "error": "no valid files" }),
            snapshot_value: inner.full_snapshot(),
        }).ok();
        return;
    }

    let session_id = format!("out-{}", timestamp());
    let session_info = SessionInfo {
        id: session_id.clone(),
        direction: "out".into(),
        peer_alias: peer.alias.clone(),
        peer_ip: peer.ip.clone(),
        files: path_map
            .iter()
            .map(|(id, _, size)| SessionFile {
                id: id.clone(),
                name: String::new(),
                size: *size,
                transferred: 0,
                path: None,
            })
            .collect(),
        state: "offered".into(),
        error: None,
        created_at: timestamp(),
    };
    inner.add_session(SessionData {
        info: session_info,
        file_tokens: HashMap::new(),
        send_files: path_map.clone(),
    });

    // Prepare-upload against the peer.
    let scheme = if peer.protocol == "http" { "http" } else { "https" };
    let url = format!("{scheme}://{}:{}/api/localsend/v2/prepare-upload", peer.ip, peer.port);
    let body = PrepareUploadRequest {
        info: DeviceInfo {
            alias: ALIAS.into(),
            version: PROTOCOL_VERSION.into(),
            device_model: Some("NoxFlow".into()),
            device_type: Some(DEVICE_TYPE.into()),
            fingerprint: String::new(),
            port: SERVER_PORT,
            protocol: "https".into(),
            download: false,
            announce: None,
        },
        files,
    };

    let client = hyper_util::client::legacy::Client::builder(hyper_util::rt::TokioExecutor::new())
        .build(
            hyper_rustls::HttpsConnectorBuilder::new()
                .with_webpki_roots()
                .https_or_http()
                .enable_http1()
                .build(),
        );

    let req = hyper::Request::builder()
        .method("POST")
        .uri(&url)
        .header("content-type", "application/json")
        .body(Full::new(bytes::Bytes::from(serde_json::to_string(&body).unwrap_or_default())))
        .unwrap();

    let resp = match client.request(req).await {
        Ok(r) => r,
        Err(e) => {
            fail_session(&inner, &session_id, format!("prepare failed: {e}"));
            return;
        }
    };
    let status = resp.status().as_u16();
    let resp_body = match resp.into_body().collect().await {
        Ok(b) => String::from_utf8_lossy(&b.to_bytes()).to_string(),
        Err(e) => {
            fail_session(&inner, &session_id, format!("prepare body: {e}"));
            return;
        }
    };
    if status == 403 {
        fail_session(&inner, &session_id, "peer declined".into());
        return;
    }
    if status != 200 {
        fail_session(&inner, &session_id, format!("prepare status {status}: {resp_body}"));
        return;
    }
    let prepared: PrepareUploadResponse = match serde_json::from_str(&resp_body) {
        Ok(p) => p,
        Err(e) => {
            fail_session(&inner, &session_id, format!("prepare parse: {e}"));
            return;
        }
    };

    // Store the per-file tokens.
    {
        let mut sessions = inner.sessions.lock().unwrap();
        if let Some(s) = sessions.get_mut(&session_id) {
            s.info.state = "transferring".into();
            s.file_tokens = prepared.files.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
            for f in &mut s.info.files {
                if let Some(orig) = path_map.iter().find(|(id, _, _)| id == &f.id) {
                    f.name = orig.1.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                    f.path = Some(orig.1.to_string_lossy().to_string());
                }
            }
        }
    }
    inner.publish_sessions();

    // Upload each file.
    let mut ok = true;
    for (file_id, path, size) in path_map {
        let token = prepared.files.get(&file_id).cloned().unwrap_or_default();
        let url = format!(
            "{scheme}://{}:{}/api/localsend/v2/upload?sessionId={}&fileId={}&token={}",
            peer.ip, peer.port, session_id, file_id, token
        );
        match upload_file(&client, &url, &path, size, &inner, &session_id, &file_id).await {
            Ok(_) => {}
            Err(e) => {
                fail_session(&inner, &session_id, format!("upload {}: {e}", path.display()));
                ok = false;
                break;
            }
        }
    }
    if ok {
        let mut sessions = inner.sessions.lock().unwrap();
        if let Some(s) = sessions.get_mut(&session_id) {
            s.info.state = "completed".into();
        }
        drop(sessions);
        inner.publish_sessions();
    }
}

async fn upload_file<C>(
    client: &hyper_util::client::legacy::Client<C, Full<bytes::Bytes>>,
    url: &str,
    path: &Path,
    size: u64,
    inner: &Arc<Inner>,
    session_id: &str,
    file_id: &str,
) -> Result<(), String>
where
    C: hyper_util::client::legacy::connect::Connect + Clone + Send + Sync + 'static,
{
    let data = fs::read(path).map_err(|e| format!("read {e}"))?;
    let req = hyper::Request::builder()
        .method("POST")
        .uri(url)
        .header("content-type", "application/octet-stream")
        .body(Full::new(bytes::Bytes::from(data)))
        .unwrap();
    let resp = client.request(req).await.map_err(|e| format!("req {e}"))?;
    if resp.status().as_u16() != 204 && resp.status().as_u16() != 200 {
        return Err(format!("status {}", resp.status().as_u16()));
    }
    update_file_progress(inner, session_id, file_id, size);
    Ok(())
}

fn fail_session(inner: &Arc<Inner>, session_id: &str, message: String) {
    let mut sessions = inner.sessions.lock().unwrap();
    if let Some(s) = sessions.get_mut(session_id) {
        s.info.state = "failed".into();
        s.info.error = Some(message);
    }
    drop(sessions);
    inner.refresh_state();
    inner.publish_sessions();
}

// ── Session accept/decline/cancel ──

async fn accept_session(inner: Arc<Inner>, _tls: Arc<rustls::ServerConfig>, session_id: &str) {
    let mut sessions = inner.sessions.lock().unwrap();
    if let Some(s) = sessions.get_mut(session_id) {
        if s.info.state == "incoming" {
            s.info.state = "transferring".into();
        }
    }
    drop(sessions);
    inner.publish_sessions();
}

fn decline_session(inner: Arc<Inner>, session_id: &str) {
    let mut sessions = inner.sessions.lock().unwrap();
    if let Some(s) = sessions.get_mut(session_id) {
        s.info.state = "declined".into();
    }
    drop(sessions);
    inner.publish_sessions();
}

fn cancel_session(inner: Arc<Inner>, session_id: &str) {
    let mut sessions = inner.sessions.lock().unwrap();
    if let Some(s) = sessions.get_mut(session_id) {
        s.info.state = "cancelled".into();
    }
    drop(sessions);
    inner.publish_sessions();
}

fn mime_guess_for(path: &str) -> String {
    let ext = Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "png" => "image/png".into(),
        "jpg" | "jpeg" => "image/jpeg".into(),
        "gif" => "image/gif".into(),
        "webp" => "image/webp".into(),
        "svg" => "image/svg+xml".into(),
        "pdf" => "application/pdf".into(),
        "mp4" => "video/mp4".into(),
        "mp3" => "audio/mpeg".into(),
        "txt" => "text/plain".into(),
        "md" => "text/markdown".into(),
        "json" => "application/json".into(),
        "zip" => "application/zip".into(),
        "tar" => "application/x-tar".into(),
        "gz" => "application/gzip".into(),
        "deb" => "application/vnd.debian.binary-package".into(),
        "appimage" => "application/x-appimage".into(),
        _ => "application/octet-stream".into(),
    }
}
