//! Event-driven Bluetooth provider backed by BlueZ's system D-Bus API.
//!
//! This provider deliberately operates only on existing paired devices. It
//! does not register an agent and therefore never participates in pairing or
//! PIN interaction.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    io,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
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
const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(30);

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
    Connect(String),
    Disconnect(String),
    SetTrusted { device_id: String, trusted: bool },
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
    let mut previous: Option<BluetoothState> = None;
    let mut signals: Option<mpsc::Receiver<()>> = None;
    let mut discovery_deadline: Option<Instant> = None;
    let mut unavailable = false;
    while !stop.load(Ordering::Relaxed) {
        while let Ok((command, reply)) = receiver.try_recv() {
            let result = execute(&command);
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
            let _ = execute(&CommandRequest::SetDiscovering(false));
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

struct BluetoothEvent {
    data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}

impl ProviderEvent for BluetoothEvent {
    fn provider(&self) -> &str {
        PROVIDER
    }
    fn event_type(&self) -> &str {
        "state_changed"
    }
    fn data(&self) -> BTreeMap<String, Value> {
        self.data.clone()
    }
    fn snapshot(&self) -> ProviderState {
        self.snapshot.clone()
    }
}

fn changed_data(state: &BluetoothState) -> BTreeMap<String, Value> {
    BTreeMap::from([(
        "state".into(),
        state
            .snapshot(ProviderStatus::Available)
            .data
            .into_iter()
            .collect::<serde_json::Map<String, Value>>()
            .into(),
    )])
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
        if !bool_property(properties, "Paired") {
            continue;
        }
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
            paired: true,
            connected: bool_property(properties, "Connected"),
            trusted: bool_property(properties, "Trusted"),
        });
    }
    adapters.sort_by(|a, b| a.id.cmp(&b.id));
    devices.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(BluetoothState { adapters, devices })
}

fn execute(command: &CommandRequest) -> io::Result<()> {
    let connection = Connection::system().map_err(io::Error::other)?;
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
        CommandRequest::Connect(device_id) => {
            device_call(&connection, &objects, device_id, "Connect", None)
        }
        CommandRequest::Disconnect(device_id) => {
            device_call(&connection, &objects, device_id, "Disconnect", None)
        }
        CommandRequest::SetTrusted { device_id, trusted } => {
            device_call(&connection, &objects, device_id, "", Some(*trusted))
        }
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
) -> io::Result<()> {
    let address = normalize_address(device_id);
    let (path, properties) = objects
        .iter()
        .find_map(|(path, interfaces)| {
            interfaces.get(DEVICE).and_then(|props| {
                (bool_property(props, "Paired")
                    && string_property(props, "Address").map(|value| normalize_address(&value))
                        == Some(address.clone()))
                .then_some((path, props))
            })
        })
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "Bluetooth device is not a known paired device",
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
            }],
        };
        let snapshot = state.snapshot(ProviderStatus::Available);
        assert_eq!(snapshot.data["adapter_present"], json!(true));
        assert_eq!(snapshot.data["devices"][0]["battery"], json!(75));
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
