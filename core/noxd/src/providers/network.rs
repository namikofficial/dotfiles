//! Event-driven NetworkManager provider.
//!
//! State is read from NetworkManager's system D-Bus API and refreshed when
//! NetworkManager emits a signal. Actions operate only on existing saved
//! profiles; this provider never handles secrets or creates profiles.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    io,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::Duration,
};
use zbus::{
    blocking::{Connection, MessageIterator, Proxy},
    zvariant::{OwnedObjectPath, OwnedValue},
    MatchRule,
};

pub const PROVIDER: &str = "network";
const SERVICE: &str = "org.freedesktop.NetworkManager";
const ROOT: &str = "/org/freedesktop/NetworkManager";
const NM_IFACE: &str = "org.freedesktop.NetworkManager";
const DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device";
const WIFI_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const ACTIVE_IFACE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const AP_IFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
const SETTINGS_IFACE: &str = "org.freedesktop.NetworkManager.Settings";

#[derive(Debug, Clone, PartialEq, Default)]
pub struct NetworkState {
    pub connectivity: String,
    pub connectivity_check_available: bool,
    pub connectivity_check_enabled: bool,
    pub nm_state: String,
    pub networking_enabled: bool,
    pub wifi_enabled: Option<bool>,
    pub wifi_hardware_enabled: Option<bool>,
    pub active_connection: Option<Value>,
    pub ethernet: Vec<Value>,
    pub connected_ssid: Option<String>,
    pub signal_strength: Option<u8>,
    pub available_wifi: Vec<Value>,
    pub ipv4: Vec<String>,
    pub ipv6: Vec<String>,
    pub metered: String,
    pub vpn: Vec<Value>,
}

impl NetworkState {
    pub fn snapshot(&self, status: ProviderStatus) -> ProviderState {
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data: BTreeMap::from([
                ("connectivity".into(), json!(self.connectivity)),
                (
                    "connectivity_check_available".into(),
                    json!(self.connectivity_check_available),
                ),
                (
                    "connectivity_check_enabled".into(),
                    json!(self.connectivity_check_enabled),
                ),
                ("nm_state".into(), json!(self.nm_state)),
                ("networking_enabled".into(), json!(self.networking_enabled)),
                ("wifi_enabled".into(), option_json(self.wifi_enabled)),
                (
                    "wifi_hardware_enabled".into(),
                    option_json(self.wifi_hardware_enabled),
                ),
                (
                    "active_connection".into(),
                    self.active_connection.clone().unwrap_or(Value::Null),
                ),
                ("ethernet".into(), json!(self.ethernet)),
                (
                    "connected_ssid".into(),
                    option_json(self.connected_ssid.as_deref()),
                ),
                ("signal_strength".into(), option_json(self.signal_strength)),
                ("available_wifi".into(), json!(self.available_wifi)),
                ("ipv4".into(), json!(self.ipv4)),
                ("ipv6".into(), json!(self.ipv6)),
                ("metered".into(), json!(self.metered)),
                ("vpn".into(), json!(self.vpn)),
            ]),
        }
    }
}

fn option_json<T: serde::Serialize>(value: T) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

#[derive(Debug, Clone)]
pub enum CommandRequest {
    WifiSetEnabled(bool),
    ConnectSaved(String),
    DisconnectWifi,
    Refresh,
    VpnSetEnabled { uuid: String, enabled: bool },
}

#[derive(Clone)]
pub struct Control {
    sender: mpsc::Sender<CommandRequest>,
}

impl Control {
    pub fn send(&self, command: CommandRequest) -> io::Result<()> {
        self.sender
            .send(command)
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "network provider stopped"))
    }
}

pub fn start(bus: EventBus, stop: Arc<AtomicBool>) -> (thread::JoinHandle<()>, Control) {
    let (sender, receiver) = mpsc::channel();
    let control = Control { sender };
    let thread = thread::spawn(move || run(bus, stop, receiver));
    (thread, control)
}

fn run(bus: EventBus, stop: Arc<AtomicBool>, receiver: mpsc::Receiver<CommandRequest>) {
    let mut previous = None;
    let mut signal_rx: Option<mpsc::Receiver<()>> = None;
    let mut unavailable = false;
    while !stop.load(Ordering::Relaxed) {
        while let Ok(command) = receiver.try_recv() {
            if let Err(error) = execute(&command) {
                eprintln!(
                    "{{\"provider\":\"network\",\"event\":\"action_failed\",\"error\":{}}}",
                    json!(error.to_string())
                );
            }
        }
        let refresh = signal_rx
            .as_ref()
            .map(|rx| rx.try_recv().is_ok())
            .unwrap_or(true);
        if refresh {
            match read_snapshot() {
                Ok(state) => {
                    let changed = previous.as_ref() != Some(&state);
                    if changed {
                        let _ = bus.publish(NetworkEvent {
                            event_type: "state_changed".into(),
                            data: changed_data(&state),
                            snapshot: state.snapshot(ProviderStatus::Available),
                        });
                    } else {
                        let _ = bus.update_snapshot(state.snapshot(ProviderStatus::Available));
                    }
                    previous = Some(state);
                    unavailable = false;
                    if signal_rx.is_none() {
                        signal_rx = subscribe_signals();
                    }
                }
                Err(_) => {
                    if !unavailable {
                        let _ = bus.update_snapshot(
                            NetworkState::default().snapshot(ProviderStatus::Unavailable),
                        );
                        unavailable = true;
                    }
                    signal_rx = None;
                    thread::sleep(Duration::from_millis(500));
                }
            }
        } else {
            thread::sleep(Duration::from_millis(50));
        }
    }
}

fn changed_data(state: &NetworkState) -> BTreeMap<String, Value> {
    BTreeMap::from([
        ("connectivity".into(), json!(state.connectivity)),
        (
            "connected_ssid".into(),
            option_json(state.connected_ssid.as_deref()),
        ),
        ("wifi_enabled".into(), option_json(state.wifi_enabled)),
        ("signal_strength".into(), option_json(state.signal_strength)),
        ("metered".into(), json!(state.metered)),
    ])
}

struct NetworkEvent {
    event_type: String,
    data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}
impl ProviderEvent for NetworkEvent {
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

fn subscribe_signals() -> Option<mpsc::Receiver<()>> {
    let (tx, rx) = mpsc::channel();
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(SERVICE)
        .ok()?
        .build();
    thread::spawn(move || {
        let Ok(connection) = Connection::system() else {
            return;
        };
        let Ok(mut messages) = MessageIterator::for_match_rule(rule, &connection, Some(64)) else {
            return;
        };
        while messages.next().is_some() {
            if tx.send(()).is_err() {
                break;
            }
        }
    });
    Some(rx)
}

fn proxy<'a>(
    connection: &'a Connection,
    path: &'a str,
    interface: &'a str,
) -> zbus::Result<Proxy<'a>> {
    Proxy::new(connection, SERVICE, path, interface)
}

fn read_snapshot() -> zbus::Result<NetworkState> {
    let connection = Connection::system()?;
    let manager = proxy(&connection, ROOT, NM_IFACE)?;
    let connectivity: u32 = manager.get_property("Connectivity")?;
    let state: u32 = manager.get_property("State")?;
    let mut result = NetworkState {
        connectivity: connectivity_name(connectivity).into(),
        connectivity_check_available: manager
            .get_property("ConnectivityCheckAvailable")
            .unwrap_or(false),
        connectivity_check_enabled: manager
            .get_property("ConnectivityCheckEnabled")
            .unwrap_or(false),
        nm_state: nm_state_name(state).into(),
        networking_enabled: manager.get_property("NetworkingEnabled").unwrap_or(false),
        wifi_enabled: manager.get_property("WirelessEnabled").ok(),
        wifi_hardware_enabled: manager.get_property("WirelessHardwareEnabled").ok(),
        metered: metered_name(manager.get_property::<u32>("Metered").unwrap_or(0)).into(),
        ..Default::default()
    };
    let active: Vec<OwnedObjectPath> = manager
        .get_property("ActiveConnections")
        .unwrap_or_default();
    for path in active {
        if let Ok(connection_state) = active_connection(&connection, path.as_str()) {
            if result.ipv4.is_empty() {
                result.ipv4 = connection_state
                    .get("ipv4")
                    .and_then(Value::as_array)
                    .map(|values| {
                        values
                            .iter()
                            .filter_map(Value::as_str)
                            .map(str::to_owned)
                            .collect()
                    })
                    .unwrap_or_default();
            }
            if result.ipv6.is_empty() {
                result.ipv6 = connection_state
                    .get("ipv6")
                    .and_then(Value::as_array)
                    .map(|values| {
                        values
                            .iter()
                            .filter_map(Value::as_str)
                            .map(str::to_owned)
                            .collect()
                    })
                    .unwrap_or_default();
            }
            if connection_state
                .get("vpn")
                .and_then(Value::as_bool)
                .unwrap_or(false)
            {
                result.vpn.push(connection_state.clone());
            } else if result.active_connection.is_none() {
                result.active_connection = Some(connection_state);
            }
        }
    }
    let devices: Vec<OwnedObjectPath> = manager.get_property("Devices").unwrap_or_default();
    for path in devices {
        let device = proxy(&connection, path.as_str(), DEVICE_IFACE)?;
        let kind: u32 = device.get_property("DeviceType").unwrap_or(0);
        let iface: String = device.get_property("Interface").unwrap_or_default();
        let state_code: u32 = device.get_property("State").unwrap_or(0);
        let active_path: OwnedObjectPath = device
            .get_property("ActiveConnection")
            .unwrap_or_else(|_| OwnedObjectPath::try_from("/").unwrap());
        if kind == 1 {
            result.ethernet.push(json!({"interface": iface, "state": device_state_name(state_code), "carrier": proxy(&connection, path.as_str(), "org.freedesktop.NetworkManager.Device.Wired").ok().and_then(|p| p.get_property::<bool>("Carrier").ok())}));
        }
        if kind == 2 {
            let wifi = proxy(&connection, path.as_str(), WIFI_IFACE)?;
            let ap: OwnedObjectPath = wifi
                .get_property("ActiveAccessPoint")
                .unwrap_or_else(|_| OwnedObjectPath::try_from("/").unwrap());
            if ap.as_str() != "/" {
                let access = proxy(&connection, ap.as_str(), AP_IFACE)?;
                result.connected_ssid = access
                    .get_property::<Vec<u8>>("Ssid")
                    .ok()
                    .map(|v| String::from_utf8_lossy(&v).into_owned());
                result.signal_strength = access.get_property("Strength").ok();
            }
            let aps: Vec<OwnedObjectPath> = wifi.get_property("AccessPoints").unwrap_or_default();
            for ap in aps {
                if let Ok(access) = proxy(&connection, ap.as_str(), AP_IFACE) {
                    let ssid = access.get_property::<Vec<u8>>("Ssid").unwrap_or_default();
                    if !ssid.is_empty() {
                        result.available_wifi.push(json!({"ssid": String::from_utf8_lossy(&ssid), "strength": access.get_property::<u8>("Strength").unwrap_or(0), "frequency": access.get_property::<u32>("Frequency").unwrap_or(0), "secure": access.get_property::<u32>("WpaFlags").unwrap_or(0) != 0 || access.get_property::<u32>("RsnFlags").unwrap_or(0) != 0}));
                    }
                }
            }
        }
        if active_path.as_str() != "/" && result.active_connection.is_none() {
            result.active_connection = active_connection(&connection, active_path.as_str()).ok();
        }
    }
    Ok(result)
}

fn active_connection(connection: &Connection, path: &str) -> zbus::Result<Value> {
    let active = proxy(connection, path, ACTIVE_IFACE)?;
    let vpn: bool = active.get_property("Vpn").unwrap_or(false);
    let devices: Vec<OwnedObjectPath> = active.get_property("Devices").unwrap_or_default();
    let interface = devices
        .first()
        .and_then(|path| proxy(connection, path.as_str(), DEVICE_IFACE).ok())
        .and_then(|device| device.get_property::<String>("Interface").ok())
        .unwrap_or_default();
    let ipv4 = active
        .get_property::<OwnedObjectPath>("Ip4Config")
        .ok()
        .and_then(|path| {
            read_addresses(
                connection,
                path.as_str(),
                "org.freedesktop.NetworkManager.IP4Config",
                false,
            )
            .ok()
        })
        .unwrap_or_default();
    let ipv6 = active
        .get_property::<OwnedObjectPath>("Ip6Config")
        .ok()
        .and_then(|path| {
            read_addresses(
                connection,
                path.as_str(),
                "org.freedesktop.NetworkManager.IP6Config",
                true,
            )
            .ok()
        })
        .unwrap_or_default();
    Ok(
        json!({"id": active.get_property::<String>("Id").unwrap_or_default(), "uuid": active.get_property::<String>("Uuid").unwrap_or_default(), "type": active.get_property::<String>("Type").unwrap_or_default(), "state": active.get_property::<u32>("State").unwrap_or(0), "vpn": vpn, "default": active.get_property::<bool>("Default").unwrap_or(false), "interface": interface, "ipv4": ipv4, "ipv6": ipv6}),
    )
}

fn read_addresses(
    connection: &Connection,
    path: &str,
    interface: &str,
    ipv6: bool,
) -> zbus::Result<Vec<String>> {
    let config = proxy(connection, path, interface)?;
    let data: Vec<HashMap<String, OwnedValue>> =
        config.get_property("AddressData").unwrap_or_default();
    let mut addresses = Vec::new();
    for item in data {
        if let Some(address) = item
            .get("address")
            .and_then(|value| value.downcast_ref::<String>().ok())
        {
            let prefix = item
                .get("prefix")
                .and_then(|value| value.downcast_ref::<u32>().ok())
                .unwrap_or(0);
            addresses.push(if ipv6 {
                format!("{address}/{prefix}")
            } else {
                format!("{address}/{prefix}")
            });
        }
    }
    Ok(addresses)
}

fn execute(command: &CommandRequest) -> io::Result<()> {
    let connection = Connection::system().map_err(io::Error::other)?;
    let manager = proxy(&connection, ROOT, NM_IFACE).map_err(io::Error::other)?;
    match command {
        CommandRequest::WifiSetEnabled(enabled) => manager
            .set_property("WirelessEnabled", *enabled)
            .map_err(io::Error::other),
        CommandRequest::Refresh => {
            let devices: Vec<OwnedObjectPath> =
                manager.get_property("Devices").map_err(io::Error::other)?;
            for path in devices {
                let device =
                    proxy(&connection, path.as_str(), DEVICE_IFACE).map_err(io::Error::other)?;
                if device.get_property::<u32>("DeviceType").unwrap_or(0) == 2 {
                    let wifi =
                        proxy(&connection, path.as_str(), WIFI_IFACE).map_err(io::Error::other)?;
                    let _: () = wifi
                        .call(
                            "RequestScan",
                            &std::collections::HashMap::<String, OwnedValue>::new(),
                        )
                        .map_err(io::Error::other)?;
                }
            }
            Ok(())
        }
        CommandRequest::ConnectSaved(uuid) => {
            let settings = proxy(
                &connection,
                "/org/freedesktop/NetworkManager/Settings",
                SETTINGS_IFACE,
            )
            .map_err(io::Error::other)?;
            let path: OwnedObjectPath = settings
                .call("GetConnectionByUuid", &(uuid.as_str(),))
                .map_err(io::Error::other)?;
            let device = wifi_device_path(&connection, &manager)?;
            manager
                .call::<_, _, OwnedObjectPath>(
                    "ActivateConnection",
                    &(path, device, OwnedObjectPath::try_from("/").unwrap()),
                )
                .map(|_| ())
                .map_err(io::Error::other)
        }
        CommandRequest::DisconnectWifi => {
            let state = read_snapshot().map_err(io::Error::other)?;
            if let Some(active) = state.active_connection {
                if active
                    .get("type")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .contains("wireless")
                {
                    let paths: Vec<OwnedObjectPath> = manager
                        .get_property("ActiveConnections")
                        .map_err(io::Error::other)?;
                    for path in paths {
                        let active_proxy = proxy(&connection, path.as_str(), ACTIVE_IFACE)
                            .map_err(io::Error::other)?;
                        let uuid = active_proxy
                            .get_property::<String>("Uuid")
                            .unwrap_or_default();
                        drop(active_proxy);
                        if uuid == active.get("uuid").and_then(Value::as_str).unwrap_or("") {
                            let _: () = manager
                                .call("DeactivateConnection", &(path,))
                                .map_err(io::Error::other)?;
                            break;
                        }
                    }
                }
            }
            Ok(())
        }
        CommandRequest::VpnSetEnabled { uuid, enabled } => {
            let settings = proxy(
                &connection,
                "/org/freedesktop/NetworkManager/Settings",
                SETTINGS_IFACE,
            )
            .map_err(io::Error::other)?;
            let path: OwnedObjectPath = settings
                .call("GetConnectionByUuid", &(uuid.as_str(),))
                .map_err(io::Error::other)?;
            if *enabled {
                manager
                    .call::<_, _, OwnedObjectPath>(
                        "ActivateConnection",
                        &(
                            path,
                            OwnedObjectPath::try_from("/").unwrap(),
                            OwnedObjectPath::try_from("/").unwrap(),
                        ),
                    )
                    .map(|_| ())
                    .map_err(io::Error::other)
            } else {
                let paths: Vec<OwnedObjectPath> = manager
                    .get_property("ActiveConnections")
                    .map_err(io::Error::other)?;
                for active_path in paths {
                    let active = proxy(&connection, active_path.as_str(), ACTIVE_IFACE)
                        .map_err(io::Error::other)?;
                    let active_uuid = active.get_property::<String>("Uuid").unwrap_or_default();
                    drop(active);
                    if active_uuid == *uuid {
                        let _: () = manager
                            .call("DeactivateConnection", &(active_path,))
                            .map_err(io::Error::other)?;
                    }
                }
                Ok(())
            }
        }
    }
}

fn wifi_device_path(connection: &Connection, manager: &Proxy<'_>) -> io::Result<OwnedObjectPath> {
    let devices: Vec<OwnedObjectPath> =
        manager.get_property("Devices").map_err(io::Error::other)?;
    for path in devices {
        let device = proxy(connection, path.as_str(), DEVICE_IFACE).map_err(io::Error::other)?;
        if device.get_property::<u32>("DeviceType").unwrap_or(0) == 2 {
            drop(device);
            return Ok(path);
        }
    }
    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no Wi-Fi device available",
    ))
}

fn connectivity_name(value: u32) -> &'static str {
    match value {
        0 => "unknown",
        1 => "none",
        2 => "portal",
        3 => "limited",
        4 => "full",
        _ => "unknown",
    }
}
fn nm_state_name(value: u32) -> &'static str {
    match value {
        10 => "asleep",
        20 => "disconnected",
        30 => "disconnecting",
        40 => "connecting",
        50 => "connected_local",
        60 => "connected_site",
        70 => "connected",
        _ => "unknown",
    }
}
fn device_state_name(value: u32) -> &'static str {
    match value {
        30 => "disconnected",
        50 => "configuring",
        100 => "activated",
        120 => "failed",
        _ => "unknown",
    }
}
fn metered_name(value: u32) -> &'static str {
    match value {
        1 => "unknown",
        2 => "unmetered",
        3 => "metered",
        4 => "guess_yes",
        5 => "guess_no",
        _ => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct MockNetworkManager {
        wifi_enabled: bool,
        connected_uuid: Option<String>,
        vpn_uuids: Vec<String>,
        scan_requests: usize,
    }

    impl MockNetworkManager {
        fn apply(&mut self, command: CommandRequest) {
            match command {
                CommandRequest::WifiSetEnabled(enabled) => self.wifi_enabled = enabled,
                CommandRequest::ConnectSaved(uuid) => self.connected_uuid = Some(uuid),
                CommandRequest::DisconnectWifi => self.connected_uuid = None,
                CommandRequest::Refresh => self.scan_requests += 1,
                CommandRequest::VpnSetEnabled { uuid, enabled } => {
                    if enabled && !self.vpn_uuids.contains(&uuid) {
                        self.vpn_uuids.push(uuid);
                    } else if !enabled {
                        self.vpn_uuids.retain(|candidate| candidate != &uuid);
                    }
                }
            }
        }
    }
    #[test]
    fn snapshot_contains_required_network_fields() {
        let state = NetworkState {
            connectivity: "portal".into(),
            connected_ssid: Some("Cafe".into()),
            signal_strength: Some(72),
            metered: "metered".into(),
            ..Default::default()
        };
        let snapshot = state.snapshot(ProviderStatus::Available);
        assert_eq!(snapshot.data["connectivity"], json!("portal"));
        assert_eq!(snapshot.data["connected_ssid"], json!("Cafe"));
        assert_eq!(snapshot.data["signal_strength"], json!(72));
    }

    #[test]
    fn mocked_actions_only_touch_existing_profile_identifiers() {
        let uuid = "01234567-89ab-cdef-0123-456789abcdef".to_owned();
        let mut manager = MockNetworkManager::default();
        manager.apply(CommandRequest::WifiSetEnabled(true));
        manager.apply(CommandRequest::ConnectSaved(uuid.clone()));
        manager.apply(CommandRequest::VpnSetEnabled {
            uuid: uuid.clone(),
            enabled: true,
        });
        manager.apply(CommandRequest::Refresh);
        assert!(manager.wifi_enabled);
        assert_eq!(manager.connected_uuid, Some(uuid.clone()));
        assert_eq!(manager.vpn_uuids, vec![uuid.clone()]);
        assert_eq!(manager.scan_requests, 1);
        manager.apply(CommandRequest::DisconnectWifi);
        manager.apply(CommandRequest::VpnSetEnabled {
            uuid,
            enabled: false,
        });
        assert!(manager.connected_uuid.is_none());
        assert!(manager.vpn_uuids.is_empty());
    }
}
