//! Event-driven Bluetooth provider backed by BlueZ's system D-Bus API.
//!
//! The provider exposes nearby and paired devices and owns the user-initiated
//! pairing wizard through a dedicated BlueZ Agent1 object.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    io,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use zbus::{
    blocking::{Connection, MessageIterator, Proxy},
    zvariant::{OwnedObjectPath, OwnedValue},
    MatchRule,
};

pub const PROVIDER: &str = "bluetooth";
const SERVICE: &str = "org.bluez";
const ROOT: &str = "/";
const OBJECT_MANAGER: &str = "org.freedesktop.DBus.ObjectManager";
const ADAPTER: &str = "org.bluez.Adapter1";
const DEVICE: &str = "org.bluez.Device1";
const BATTERY: &str = "org.bluez.Battery1";
const AGENT_MANAGER: &str = "org.bluez.AgentManager1";
const AGENT_PATH: &str = "/org/noxflow/agent";
const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(30);
const PAIRING_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct BluetoothAdapter {
    pub id: String,
    pub powered: bool,
    pub discovering: bool,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct BluetoothDevice {
    pub id: String,
    pub name: String,
    pub device_type: String,
    pub battery: Option<u8>,
    pub paired: bool,
    pub connected: bool,
    pub trusted: bool,
    pub rssi: Option<i16>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct BluetoothState {
    pub adapters: Vec<BluetoothAdapter>,
    pub devices: Vec<BluetoothDevice>,
}

impl BluetoothState {
    pub fn snapshot(&self, status: ProviderStatus) -> ProviderState {
        let powered = self.adapters.iter().any(|adapter| adapter.powered);
        let discovering = self.adapters.iter().any(|adapter| adapter.discovering);
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data: BTreeMap::from([
                ("adapter_present".into(), json!(!self.adapters.is_empty())),
                ("powered".into(), json!(powered)),
                ("discovering".into(), json!(discovering)),
                ("adapters".into(), json!(self.adapters)),
                ("devices".into(), json!(self.devices)),
            ]),
        }
    }
}

#[derive(Debug, Clone)]
pub enum CommandRequest {
    SetPowered(bool),
    SetDiscovering(bool),
    Pair(String),
    Connect(String),
    Disconnect(String),
    PairingResponse {
        request_id: String,
        accepted: bool,
        passkey: Option<String>,
    },
    CancelPairing(String),
    SetTrusted {
        device_id: String,
        trusted: bool,
    },
}

#[derive(Clone)]
pub struct Control {
    sender: mpsc::Sender<(CommandRequest, mpsc::Sender<io::Result<()>>)>,
}

impl Control {
    pub fn send(&self, command: CommandRequest) -> io::Result<()> {
        let (reply, receiver) = mpsc::channel();
        self.sender
            .send((command, reply))
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "bluetooth provider stopped"))?;
        receiver.recv().map_err(|_| {
            io::Error::new(io::ErrorKind::BrokenPipe, "bluetooth action worker stopped")
        })?
    }
}

pub fn start(bus: EventBus, stop: Arc<AtomicBool>) -> (thread::JoinHandle<()>, Control) {
    let (sender, receiver) = mpsc::channel();
    let control = Control { sender };
    let thread = thread::spawn(move || run(bus, stop, receiver));
    (thread, control)
}

fn run(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    receiver: mpsc::Receiver<(CommandRequest, mpsc::Sender<io::Result<()>>)>,
) {
    let agent = PairingAgent::new(bus.clone());
    let agent_connection = match register_agent(agent.clone()) {
        Ok(connection) => Some(connection),
        Err(error) => {
            eprintln!("bluetooth pairing agent unavailable: {error}");
            None
        }
    };
    let mut previous: Option<BluetoothState> = None;
    let mut signals: Option<mpsc::Receiver<()>> = None;
    let mut discovery_deadline: Option<Instant> = None;
    let mut unavailable = false;
    while !stop.load(Ordering::Relaxed) {
        while let Ok((command, reply)) = receiver.try_recv() {
            // Device1.Pair() blocks while BlueZ waits for Agent1 callbacks.
            // Run it off the provider loop so the socket reader can process
            // the in-shell pairing response (or cancellation) immediately.
            if let CommandRequest::Pair(device_id) = command {
                if !agent.begin_pairing() {
                    let _ = reply.send(Err(io::Error::new(
                        io::ErrorKind::AlreadyExists,
                        "another Bluetooth pairing request is already active",
                    )));
                    continue;
                }
                publish_pairing_status(&bus, "pairing_started", &device_id, None);
                let worker_bus = bus.clone();
                let worker_agent = agent.clone();
                let worker_device = device_id.clone();
                thread::spawn(move || {
                    let command = CommandRequest::Pair(worker_device.clone());
                    let result = execute(&command, agent_connection, &worker_agent);
                    worker_agent.end_pairing();
                    if let Err(error) = &result {
                        publish_pairing_status(
                            &worker_bus,
                            "pairing_failed",
                            &worker_device,
                            Some(&error.to_string()),
                        );
                    } else {
                        publish_pairing_status(
                            &worker_bus,
                            "pairing_complete",
                            &worker_device,
                            None,
                        );
                    }
                    let _ = reply.send(result);
                });
                continue;
            }
            let result = execute(&command, agent_connection, &agent);
            if let Err(error) = &result {
                let data = BTreeMap::from([
                    ("action".into(), Value::String(command_name(&command).into())),
                    ("message".into(), Value::String(error.to_string())),
                ]);
                let snapshot = bus
                    .snapshot()
                    .get(PROVIDER)
                    .cloned()
                    .unwrap_or_else(|| BluetoothState::default().snapshot(ProviderStatus::Available));
                let _ = bus.publish(BluetoothEvent {
                    event_type: "action_failed".into(),
                    data,
                    snapshot,
                });
            }
            if result.is_ok() {
                match command {
                    CommandRequest::SetDiscovering(true) => {
                        discovery_deadline = Some(Instant::now() + DISCOVERY_TIMEOUT)
                    }
                    CommandRequest::SetDiscovering(false) => discovery_deadline = None,
                    _ => {}
                }
            }
            let _ = reply.send(result);
        }

        let timed_out = discovery_deadline.is_some_and(|deadline| Instant::now() >= deadline);
        if timed_out {
            let _ = execute(
                &CommandRequest::SetDiscovering(false),
                agent_connection,
                &agent,
            );
            discovery_deadline = None;
        }

        let refresh = signals
            .as_ref()
            .map(|rx| rx.try_recv().is_ok())
            .unwrap_or(true);
        if refresh {
            match read_snapshot() {
                Ok(state) => {
                    let changed = previous.as_ref() != Some(&state);
                    let status = ProviderStatus::Available;
                    if changed {
                        let _ = bus.publish(BluetoothEvent {
                            event_type: "state_changed".into(),
                            data: changed_data(&state),
                            snapshot: state.snapshot(status),
                        });
                    } else {
                        let _ = bus.update_snapshot(state.snapshot(status));
                    }
                    if !state.adapters.iter().any(|adapter| adapter.discovering) {
                        discovery_deadline = None;
                    }
                    previous = Some(state);
                    unavailable = false;
                    if signals.is_none() {
                        signals = subscribe_signals();
                    }
                }
                Err(_) => {
                    if !unavailable {
                        let _ = bus.update_snapshot(
                            BluetoothState::default().snapshot(ProviderStatus::Unavailable),
                        );
                        unavailable = true;
                    }
                    previous = None;
                    signals = None;
                    thread::sleep(Duration::from_millis(500));
                }
            }
        } else {
            let wait = discovery_deadline
                .map(|deadline| deadline.saturating_duration_since(Instant::now()))
                .unwrap_or(Duration::from_millis(100))
                .min(Duration::from_millis(100));
            thread::sleep(wait);
        }
    }
}

fn publish_pairing_status(
    bus: &EventBus,
    event_type: &str,
    device_id: &str,
    message: Option<&str>,
) {
    let mut data = BTreeMap::new();
    data.insert("device_id".into(), normalize_address(device_id).into());
    if let Some(message) = message {
        data.insert("message".into(), message.into());
    }
    let snapshot = bus
        .snapshot()
        .get(PROVIDER)
        .cloned()
        .unwrap_or_else(|| BluetoothState::default().snapshot(ProviderStatus::Available));
    let _ = bus.publish(BluetoothEvent {
        event_type: event_type.into(),
        data,
        snapshot,
    });
}

fn command_name(command: &CommandRequest) -> &'static str {
    match command {
        CommandRequest::SetPowered(_) => "set_powered",
        CommandRequest::SetDiscovering(_) => "set_discovering",
        CommandRequest::Pair(_) => "pair",
        CommandRequest::Connect(_) => "connect",
        CommandRequest::Disconnect(_) => "disconnect",
        CommandRequest::PairingResponse { .. } => "pairing_response",
        CommandRequest::CancelPairing(_) => "cancel_pairing",
        CommandRequest::SetTrusted { .. } => "set_trusted",
    }
}

#[derive(Clone)]
struct PairingAgent {
    bus: EventBus,
    next_request: Arc<AtomicU64>,
    pending: Arc<Mutex<HashMap<String, mpsc::Sender<PairingDecision>>>>,
    active_pairing: Arc<AtomicBool>,
}

#[derive(Debug)]
enum PairingDecision {
    Accept(Option<String>),
    Reject,
}

// BlueZ distinguishes a user rejection/cancellation from a generic D-Bus
// failure. Returning its documented error names lets bluetoothd cleanly
// abort the current transaction instead of leaving the device in limbo.
#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum AgentError {
    Rejected(String),
    Canceled(String),
    Failed(String),
    #[zbus(error)]
    ZBus(zbus::Error),
}

impl PairingAgent {
    fn new(bus: EventBus) -> Self {
        Self {
            bus,
            next_request: Arc::new(AtomicU64::new(1)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            active_pairing: Arc::new(AtomicBool::new(false)),
        }
    }

    fn begin_pairing(&self) -> bool {
        !self.active_pairing.swap(true, Ordering::AcqRel)
    }

    fn end_pairing(&self) {
        self.active_pairing.store(false, Ordering::Release);
    }

    fn reject_pending(&self) {
        let senders = self
            .pending
            .lock()
            .map(|mut pending| pending.drain().map(|(_, sender)| sender).collect::<Vec<_>>())
            .unwrap_or_default();
        for sender in senders {
            let _ = sender.send(PairingDecision::Reject);
        }
    }

    fn request(
        &self,
        device: &OwnedObjectPath,
        method: &str,
        passkey: Option<u32>,
    ) -> Result<PairingDecision, AgentError> {
        let request_id = format!("pair-{}", self.next_request.fetch_add(1, Ordering::Relaxed));
        let device_id = address_from_path(device.as_str());
        let snapshot = self
            .bus
            .snapshot()
            .get(PROVIDER)
            .cloned()
            .unwrap_or_else(|| BluetoothState::default().snapshot(ProviderStatus::Available));
        let device_name = snapshot
            .data
            .get("devices")
            .and_then(Value::as_array)
            .and_then(|devices| {
                devices.iter().find_map(|item| {
                    let item_id = item.get("id")?.as_str()?;
                    (normalize_address(item_id) == device_id).then(|| {
                        item.get("name")
                            .and_then(Value::as_str)
                            .filter(|name| !name.is_empty())
                            .unwrap_or("Bluetooth device")
                            .to_owned()
                    })
                })
            })
            .unwrap_or_else(|| "Bluetooth device".into());
        let (sender, receiver) = mpsc::channel();
        self.pending
            .lock()
            .map_err(|_| AgentError::Failed("pairing state unavailable".into()))?
            .insert(request_id.clone(), sender);

        let mut data = BTreeMap::new();
        data.insert("request_id".into(), request_id.clone().into());
        data.insert("device_id".into(), device_id.into());
        data.insert("device_name".into(), device_name.into());
        data.insert("method".into(), method.into());
        if let Some(value) = passkey {
            data.insert("passkey".into(), value.into());
        }
        let _ = self.bus.publish(BluetoothEvent {
            event_type: "pairing_request".into(),
            data,
            snapshot,
        });

        match receiver.recv_timeout(PAIRING_TIMEOUT) {
            Ok(decision) => Ok(decision),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let _ = self
                    .pending
                    .lock()
                    .map(|mut pending| pending.remove(&request_id));
                Err(AgentError::Canceled(
                    "pairing confirmation timed out".into(),
                ))
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                Err(AgentError::Canceled("pairing request was canceled".into()))
            }
        }
    }

    fn respond(&self, request_id: &str, accepted: bool, passkey: Option<String>) -> io::Result<()> {
        let sender = self
            .pending
            .lock()
            .map_err(|_| io::Error::other("pairing state unavailable"))?
            .remove(request_id)
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "pairing request expired"))?;
        sender
            .send(if accepted {
                PairingDecision::Accept(passkey)
            } else {
                PairingDecision::Reject
            })
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "pairing request ended"))
    }
}

#[zbus::interface(name = "org.bluez.Agent1")]
impl PairingAgent {
    fn release(&self) {
        self.reject_pending();
    }

    fn request_pin_code(&self, device: OwnedObjectPath) -> Result<String, AgentError> {
        match self.request(&device, "pin", None)? {
            PairingDecision::Accept(Some(pin)) => Ok(pin),
            PairingDecision::Accept(None) => Err(AgentError::Failed("PIN required".into())),
            PairingDecision::Reject => Err(AgentError::Rejected("pairing rejected".into())),
        }
    }

    fn display_pin_code(&self, device: OwnedObjectPath, pincode: String) -> Result<(), AgentError> {
        match self.request(&device, "display_pin", pincode.parse::<u32>().ok())? {
            PairingDecision::Accept(_) => Ok(()),
            PairingDecision::Reject => Err(AgentError::Rejected("pairing rejected".into())),
        }
    }

    fn request_passkey(&self, device: OwnedObjectPath) -> Result<u32, AgentError> {
        match self.request(&device, "passkey", None)? {
            PairingDecision::Accept(Some(value)) => value
                .parse::<u32>()
                .map_err(|_| AgentError::Failed("invalid passkey".into())),
            PairingDecision::Accept(None) => Err(AgentError::Failed("passkey required".into())),
            PairingDecision::Reject => Err(AgentError::Rejected("pairing rejected".into())),
        }
    }

    fn display_passkey(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
        _entered: u16,
    ) -> Result<(), AgentError> {
        match self.request(&device, "display_passkey", Some(passkey))? {
            PairingDecision::Accept(_) => Ok(()),
            PairingDecision::Reject => Err(AgentError::Rejected("pairing rejected".into())),
        }
    }

    fn request_confirmation(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
    ) -> Result<(), AgentError> {
        match self.request(&device, "confirmation", Some(passkey))? {
            PairingDecision::Accept(_) => Ok(()),
            PairingDecision::Reject => Err(AgentError::Rejected("pairing rejected".into())),
        }
    }

    fn request_authorization(&self, device: OwnedObjectPath) -> Result<(), AgentError> {
        match self.request(&device, "authorization", None)? {
            PairingDecision::Accept(_) => Ok(()),
            PairingDecision::Reject => Err(AgentError::Rejected("pairing rejected".into())),
        }
    }

    fn authorize_service(&self, device: OwnedObjectPath, _uuid: String) -> Result<(), AgentError> {
        match self.request(&device, "service", None)? {
            PairingDecision::Accept(_) => Ok(()),
            PairingDecision::Reject => Err(AgentError::Rejected("service rejected".into())),
        }
    }

    fn cancel(&self) {
        // BlueZ calls Cancel when the remote device or bluetoothd aborts the
        // transaction. Resolve the in-shell waiter immediately so Pair() can
        // unwind and the UI can offer a fresh attempt without a stale prompt.
        self.reject_pending();
    }
}

fn register_agent(agent: PairingAgent) -> zbus::Result<&'static Connection> {
    // Keep the D-Bus connection alive for the lifetime of the daemon. zbus's
    // blocking object server owns an executor tied to this connection; leaking
    // this one small connection avoids waiting on that executor during the
    // provider shutdown path while still releasing it with the process.
    let connection = Box::leak(Box::new(Connection::system()?));
    connection.object_server().at(AGENT_PATH, agent)?;
    let manager = Proxy::new(connection, SERVICE, "/org/bluez", AGENT_MANAGER)?;
    let path = OwnedObjectPath::try_from(AGENT_PATH)
        .map_err(|error| zbus::Error::Failure(error.to_string()))?;
    // NoxFlow is the normal Bluetooth surface, so make this agent the default
    // while the daemon is running. Blueman remains an explicit recovery path;
    // without a default agent BlueZ can reject Pair() before our in-shell
    // confirmation prompt is ever reached.
    let _: () = manager.call("RegisterAgent", &(path, "KeyboardDisplay"))?;
    let _: () = manager.call(
        "RequestDefaultAgent",
        &(OwnedObjectPath::try_from(AGENT_PATH)
            .map_err(|error| zbus::Error::Failure(error.to_string()))?,),
    )?;
    Ok(connection)
}

struct BluetoothEvent {
    event_type: String,
    data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}

impl ProviderEvent for BluetoothEvent {
    fn provider(&self) -> &str {
        PROVIDER
    }
    fn event_type(&self) -> &str {
        &self.event_type
    }
    fn data(&self) -> BTreeMap<String, Value> {
        self.data.clone()
    }
    fn snapshot(&self) -> ProviderState {
        self.snapshot.clone()
    }
}

fn changed_data(state: &BluetoothState) -> BTreeMap<String, Value> {
    // BluetoothModel consumes the provider fields directly. Keep state events
    // consistent with the initial snapshot so discovery updates immediately
    // render nearby (including unpaired) devices in the shell.
    state.snapshot(ProviderStatus::Available).data
}

fn subscribe_signals() -> Option<mpsc::Receiver<()>> {
    let (sender, receiver) = mpsc::channel();
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(SERVICE)
        .ok()?
        .build();
    thread::spawn(move || {
        let Ok(connection) = Connection::system() else {
            return;
        };
        let Ok(mut messages) = MessageIterator::for_match_rule(rule, &connection, Some(128)) else {
            return;
        };
        while messages.next().is_some() {
            if sender.send(()).is_err() {
                break;
            }
        }
    });
    Some(receiver)
}

fn manager<'a>(connection: &'a Connection) -> zbus::Result<Proxy<'a>> {
    Proxy::new(connection, SERVICE, ROOT, OBJECT_MANAGER)
}

type ManagedObjects = HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>;

fn managed_objects(connection: &Connection) -> zbus::Result<ManagedObjects> {
    manager(connection)?.call("GetManagedObjects", &())
}

fn read_snapshot() -> zbus::Result<BluetoothState> {
    let connection = Connection::system()?;
    let objects = managed_objects(&connection)?;
    let mut adapters = Vec::new();
    let mut devices = Vec::new();
    let mut batteries: Vec<(String, u8)> = Vec::new();
    for (path, interfaces) in &objects {
        if let Some(properties) = interfaces.get(ADAPTER) {
            adapters.push(BluetoothAdapter {
                id: path.to_string(),
                powered: bool_property(properties, "Powered"),
                discovering: bool_property(properties, "Discovering"),
            });
        }
        if let Some(properties) = interfaces.get(BATTERY) {
            if let Some(percentage) = u8_property(properties, "Percentage") {
                batteries.push((path.to_string(), percentage));
            }
        }
    }
    for (path, interfaces) in &objects {
        let Some(properties) = interfaces.get(DEVICE) else {
            continue;
        };
        let id = string_property(properties, "Address")
            .map(|value| normalize_address(&value))
            .unwrap_or_else(|| address_from_path(path.as_str()));
        let battery = batteries
            .iter()
            .find(|(battery_path, _)| battery_path.starts_with(path.as_str()))
            .map(|(_, value)| *value);
        devices.push(BluetoothDevice {
            id,
            name: string_property(properties, "Name")
                .or_else(|| string_property(properties, "Alias"))
                .unwrap_or_default(),
            device_type: device_type(properties),
            battery,
            paired: bool_property(properties, "Paired"),
            connected: bool_property(properties, "Connected"),
            trusted: bool_property(properties, "Trusted"),
            rssi: i16_property(properties, "RSSI"),
        });
    }
    adapters.sort_by(|a, b| a.id.cmp(&b.id));
    devices.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(BluetoothState { adapters, devices })
}

fn execute(
    command: &CommandRequest,
    agent_connection: Option<&Connection>,
    agent: &PairingAgent,
) -> io::Result<()> {
    if let CommandRequest::PairingResponse {
        request_id,
        accepted,
        passkey,
    } = command
    {
        return agent.respond(request_id, *accepted, passkey.clone());
    }
    if let CommandRequest::CancelPairing(request_id) = command {
        return agent.respond(request_id, false, None);
    }
    let connection = match agent_connection {
        Some(connection) => connection.clone(),
        None => Connection::system().map_err(io::Error::other)?,
    };
    let objects = managed_objects(&connection).map_err(io::Error::other)?;
    let adapter_paths: Vec<String> = objects
        .iter()
        .filter(|(_, interfaces)| interfaces.contains_key(ADAPTER))
        .map(|(path, _)| path.to_string())
        .collect();
    if adapter_paths.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "Bluetooth action requires a BlueZ adapter, but no adapter is present",
        ));
    }
    match command {
        CommandRequest::SetPowered(powered) => {
            let path = default_adapter(&objects)?;
            Proxy::new(&connection, SERVICE, path, ADAPTER)
                .map_err(io::Error::other)?
                .set_property("Powered", *powered)
                .map_err(io::Error::other)
        }
        CommandRequest::SetDiscovering(discovering) => {
            for path in &adapter_paths {
                let proxy = Proxy::new(&connection, SERVICE, path.as_str(), ADAPTER)
                    .map_err(io::Error::other)?;
                let result: zbus::Result<()> = if *discovering {
                    proxy.call("StartDiscovery", &())
                } else {
                    proxy.call("StopDiscovery", &())
                };
                result.map_err(io::Error::other)?;
            }
            Ok(())
        }
        CommandRequest::Pair(device_id) => {
            device_call(&connection, &objects, device_id, "Pair", None, false)
        }
        CommandRequest::Connect(device_id) => {
            device_call(&connection, &objects, device_id, "Connect", None, true)
        }
        CommandRequest::Disconnect(device_id) => {
            device_call(&connection, &objects, device_id, "Disconnect", None, true)
        }
        CommandRequest::SetTrusted { device_id, trusted } => {
            device_call(&connection, &objects, device_id, "", Some(*trusted), true)
        }
        CommandRequest::PairingResponse { .. } | CommandRequest::CancelPairing(_) => unreachable!(),
    }
}

fn default_adapter(objects: &ManagedObjects) -> io::Result<&str> {
    if let Some(path) = objects
        .iter()
        .filter(|(_, interfaces)| interfaces.contains_key(ADAPTER))
        .filter(|(_, interfaces)| {
            interfaces
                .get(ADAPTER)
                .map(|properties| bool_property(properties, "Powered"))
                .unwrap_or(false)
        })
        .map(|(path, _)| path.as_str())
        .min()
    {
        return Ok(path);
    }
    objects
        .iter()
        .filter(|(_, interfaces)| interfaces.contains_key(ADAPTER))
        .map(|(path, _)| path.as_str())
        .min()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no Bluetooth adapter is present"))
}

fn device_call(
    connection: &Connection,
    objects: &ManagedObjects,
    device_id: &str,
    method: &str,
    trusted: Option<bool>,
    paired_only: bool,
) -> io::Result<()> {
    let address = normalize_address(device_id);
    let (path, properties) = objects
        .iter()
        .find_map(|(path, interfaces)| {
            interfaces.get(DEVICE).and_then(|props| {
                ((!paired_only || bool_property(props, "Paired"))
                    && string_property(props, "Address").map(|value| normalize_address(&value))
                        == Some(address.clone()))
                .then_some((path, props))
            })
        })
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                if paired_only {
                    "Bluetooth device is not a known paired device"
                } else {
                    "Bluetooth device is not visible; start discovery and try again"
                },
            )
        })?;
    let proxy = Proxy::new(connection, SERVICE, path.as_str(), DEVICE).map_err(io::Error::other)?;
    if let Some(value) = trusted {
        proxy
            .set_property("Trusted", value)
            .map_err(io::Error::other)
    } else {
        let _: () = proxy.call(method, &()).map_err(io::Error::other)?;
        let _ = properties;
        Ok(())
    }
}

fn bool_property(properties: &HashMap<String, OwnedValue>, key: &str) -> bool {
    properties
        .get(key)
        .and_then(|value| value.downcast_ref::<bool>().ok())
        .unwrap_or(false)
}
fn u8_property(properties: &HashMap<String, OwnedValue>, key: &str) -> Option<u8> {
    properties
        .get(key)
        .and_then(|value| value.downcast_ref::<u8>().ok())
}
fn i16_property(properties: &HashMap<String, OwnedValue>, key: &str) -> Option<i16> {
    properties
        .get(key)
        .and_then(|value| value.downcast_ref::<i16>().ok())
}
fn string_property(properties: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    properties
        .get(key)
        .and_then(|value| value.downcast_ref::<String>().ok())
}

fn normalize_address(value: &str) -> String {
    value.trim().to_ascii_uppercase()
}
fn address_from_path(path: &str) -> String {
    path.rsplit("dev_")
        .next()
        .unwrap_or("")
        .replace('_', ":")
        .to_ascii_uppercase()
}

fn device_type(properties: &HashMap<String, OwnedValue>) -> String {
    let major = properties
        .get("Class")
        .and_then(|value| value.downcast_ref::<u32>().ok())
        .map(|class| (class >> 8) & 0x1f)
        .unwrap_or(0);
    match major {
        1 => "computer",
        2 => "phone",
        4 => "audio",
        5 => "input",
        6 => "wearable",
        9 => "health",
        _ => "peripheral",
    }
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_exposes_required_fields() {
        let state = BluetoothState {
            adapters: vec![BluetoothAdapter {
                id: "/org/bluez/hci0".into(),
                powered: true,
                discovering: false,
            }],
            devices: vec![BluetoothDevice {
                id: "AA:BB:CC:DD:EE:FF".into(),
                name: "Headphones".into(),
                device_type: "audio".into(),
                battery: Some(75),
                paired: true,
                connected: true,
                trusted: true,
                rssi: Some(-42),
            }],
        };
        let snapshot = state.snapshot(ProviderStatus::Available);
        assert_eq!(snapshot.data["adapter_present"], json!(true));
        assert_eq!(snapshot.data["devices"][0]["battery"], json!(75));
    }

    #[test]
    fn state_events_keep_device_fields_at_the_provider_root() {
        let state = BluetoothState {
            adapters: vec![BluetoothAdapter {
                id: "/org/bluez/hci0".into(),
                powered: true,
                discovering: true,
            }],
            devices: vec![BluetoothDevice {
                id: "AA:BB:CC:DD:EE:FF".into(),
                name: "Nearby Buds".into(),
                device_type: "audio".into(),
                paired: false,
                ..BluetoothDevice::default()
            }],
        };
        let data = changed_data(&state);
        assert!(data.get("state").is_none());
        assert_eq!(data["devices"][0]["paired"], json!(false));
        assert_eq!(data["discovering"], json!(true));
    }

    #[test]
    fn pairing_agent_round_trips_an_in_shell_confirmation() {
        let bus = EventBus::new();
        bus.register_provider(
            BluetoothState::default().snapshot(ProviderStatus::Available),
        )
        .unwrap();
        let subscription = bus.subscribe(vec![PROVIDER.into()], vec![]).unwrap();
        let agent = PairingAgent::new(bus);
        let worker = agent.clone();
        let device = OwnedObjectPath::try_from(
            "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
        )
        .unwrap();
        let request = thread::spawn(move || worker.request(&device, "confirmation", Some(123456)));

        let event = subscription.recv().unwrap();
        assert_eq!(event.event_type, "pairing_request");
        assert_eq!(event.data["device_id"], json!("AA:BB:CC:DD:EE:FF"));
        assert_eq!(event.data["passkey"], json!(123456));
        let request_id = event.data["request_id"].as_str().unwrap();
        agent.respond(request_id, true, None).unwrap();
        assert!(matches!(
            request.join().unwrap().unwrap(),
            PairingDecision::Accept(None)
        ));
    }

    #[test]
    fn address_normalization_is_stable() {
        assert_eq!(normalize_address("aa:bb:cc:dd:ee:ff"), "AA:BB:CC:DD:EE:FF");
        assert_eq!(
            address_from_path("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"),
            "AA:BB:CC:DD:EE:FF"
        );
    }

    #[test]
    fn discovery_deadline_is_bounded() {
        assert_eq!(DISCOVERY_TIMEOUT, Duration::from_secs(30));
    }
}
