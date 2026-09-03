//! iwd-backed network provider with systemd-networkd IP state.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    io,
    process::Command,
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

pub const PROVIDER: &str = "network";
const SERVICE: &str = "org.freedesktop.NetworkManager";
const ROOT: &str = "/org/freedesktop/NetworkManager";
const NM_IFACE: &str = "org.freedesktop.NetworkManager";
const DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device";
const WIFI_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const ACTIVE_IFACE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const AP_IFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
const IWD_STATION_RETRY_ATTEMPTS: usize = 6;
const IWD_STATION_RETRY_DELAY: Duration = Duration::from_millis(250);

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
    pub connected_bssid: Option<String>,
    pub frequency: Option<u32>,
    pub channel: Option<u32>,
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
                (
                    "connected_bssid".into(),
                    option_json(self.connected_bssid.as_deref()),
                ),
                ("frequency".into(), option_json(self.frequency)),
                ("channel".into(), option_json(self.channel)),
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
    Connect { ssid: String, passphrase: String },
    Forget(String),
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
    let mut previous: Option<NetworkState> = None;
    let mut signal_rx: Option<mpsc::Receiver<()>> = None;
    let mut unavailable = false;
    let mut last_refresh = Instant::now() - Duration::from_secs(3);
    let mut force_publish = false;
    while !stop.load(Ordering::Relaxed) {
        while let Ok(command) = receiver.try_recv() {
            match execute(&command) {
                Ok(()) if matches!(command, CommandRequest::Refresh) => {
                    // Always publish a complete post-scan snapshot, even if
                    // the visible SSID set is unchanged from the last poll.
                    force_publish = true;
                    last_refresh = Instant::now() - Duration::from_secs(3);
                }
                Ok(()) => {}
                Err(error) => {
                    let message = error.to_string();
                    eprintln!(
                        "{{\"provider\":\"network\",\"event\":\"action_failed\",\"error\":{}}}",
                        json!(message)
                    );
                    let mut data = BTreeMap::from([
                        ("action".into(), json!(action_name(&command))),
                        ("code".into(), json!(action_error_code(&message))),
                        ("message".into(), json!(user_action_error(&message))),
                    ]);
                    if let Some(ssid) = action_ssid(&command) {
                        data.insert("ssid".into(), json!(ssid));
                    }
                    let snapshot = previous
                        .clone()
                        .unwrap_or_default()
                        .snapshot(ProviderStatus::Available);
                    let _ = bus.publish(NetworkEvent {
                        event_type: "action_failed".into(),
                        data,
                        snapshot,
                    });
                }
            }
        }
        let refresh = signal_rx
            .as_ref()
            .map(|rx| rx.try_recv().is_ok())
            .unwrap_or(true)
            || last_refresh.elapsed() >= Duration::from_secs(2);
        if refresh {
            last_refresh = Instant::now();
            match read_snapshot() {
                Ok(state) => {
                    let changed = force_publish || previous.as_ref() != Some(&state);
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
                    force_publish = false;
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
    // Network consumers need the complete scan result on every state event.
    // A partial payload can contain connected_ssid while omitting
    // available_wifi, which makes the shell render a false empty state.
    state.snapshot(ProviderStatus::Available).data
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

#[allow(dead_code)]
fn read_snapshot_networkmanager() -> zbus::Result<NetworkState> {
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

fn iwctl_station() -> io::Result<String> {
    let output = Command::new("iwctl").arg("station").arg("list").output()?;
    if !output.status.success() {
        return Err(io::Error::other("iwctl station list failed"));
    }
    strip_iwctl_ansi(&String::from_utf8_lossy(&output.stdout))
        .lines()
        .skip(4)
        .find_map(|line| {
            let name = line.split_whitespace().next()?;
            (name.starts_with("wlan") || name.starts_with("wlp")).then(|| name.to_owned())
        })
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no iwd station found"))
}

fn iwctl_station_for_action() -> io::Result<String> {
    retry_iwd_station(
        iwctl_station,
        thread::sleep,
        IWD_STATION_RETRY_ATTEMPTS,
        IWD_STATION_RETRY_DELAY,
    )
}

fn retry_iwd_station<F, S>(
    mut locate: F,
    mut sleep: S,
    attempts: usize,
    delay: Duration,
) -> io::Result<String>
where
    F: FnMut() -> io::Result<String>,
    S: FnMut(Duration),
{
    let attempts = attempts.max(1);
    for attempt in 0..attempts {
        match locate() {
            Ok(station) => return Ok(station),
            Err(_) if attempt + 1 < attempts => sleep(delay),
            Err(error) => return Err(error),
        }
    }
    unreachable!("at least one iwd station lookup is always attempted")
}

fn iwctl_output(args: &[&str]) -> io::Result<String> {
    let output = Command::new("iwctl").args(args).output()?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(io::Error::other(format!(
            "iwctl command failed: {:?}{}",
            args,
            if detail.is_empty() {
                String::new()
            } else {
                format!(": {detail}")
            }
        )));
    }
    Ok(strip_iwctl_ansi(&String::from_utf8_lossy(&output.stdout)))
}

fn strip_iwctl_ansi(value: &str) -> String {
    value
        .replace("\u{1b}[1;90m", "")
        .replace("\u{1b}[90m", "")
        .replace("\u{1b}[0m", "")
}

fn parse_iwctl_networks(
    output: &str,
    saved: &std::collections::HashSet<String>,
    connected_ssid: Option<&str>,
) -> Vec<Value> {
    output
        .lines()
        .skip(4)
        .filter_map(|line| {
            let tokens = line.split_whitespace().collect::<Vec<_>>();
            let security_index = tokens
                .iter()
                .position(|value| matches!(*value, "open" | "psk" | "8021x" | "wep" | "sae"))?;
            let ssid = tokens[..security_index]
                .join(" ")
                .trim_start_matches('>')
                .trim()
                .to_owned();
            let security = tokens[security_index].to_owned();
            let signal = tokens
                .last()
                .and_then(|value| value.parse::<i32>().ok())
                .map(|value| ((value / 100 + 100).clamp(0, 100)) as u8)
                .unwrap_or(0);
            (!ssid.is_empty()).then(|| {
                json!({
                    "ssid": ssid,
                    "strength": signal,
                    "security": security,
                    "secure": security != "open",
                    "saved": saved.contains(&ssid),
                    "connected": connected_ssid == Some(ssid.as_str()),
                })
            })
        })
        .collect()
}

fn read_snapshot() -> zbus::Result<NetworkState> {
    let station = iwctl_station().map_err(|error| zbus::Error::Failure(error.to_string()))?;
    let details = iwctl_output(&["station", &station, "show"])
        .map_err(|error| zbus::Error::Failure(error.to_string()))?;
    let connected_ssid = details
        .lines()
        .map(str::trim_start)
        .find_map(|line| line.strip_prefix("Connected network"))
        .map(|value| value.trim_start_matches(':').trim().to_owned())
        .filter(|value| !value.is_empty() && value != "--");
    let signal_strength = details.lines().map(str::trim_start).find_map(|line| {
        let value = line.strip_prefix("RSSI")?.trim_start_matches(':').trim();
        let dbm = value.split_whitespace().next()?.parse::<i32>().ok()?;
        Some((dbm + 100).clamp(0, 100) as u8)
    });
    let connected_bssid = details.lines().map(str::trim_start).find_map(|line| {
        line.strip_prefix("ConnectedBss")
            .map(|value| value.trim_start_matches(':').trim().to_owned())
    });
    let frequency = details.lines().map(str::trim_start).find_map(|line| {
        line.strip_prefix("Frequency")
            .and_then(|value| value.trim_start_matches(':').split_whitespace().next())
            .and_then(|value| value.parse::<u32>().ok())
    });
    let channel = details.lines().map(str::trim_start).find_map(|line| {
        line.strip_prefix("Channel")
            .and_then(|value| value.trim_start_matches(':').split_whitespace().next())
            .and_then(|value| value.parse::<u32>().ok())
    });
    let online = Command::new("networkctl")
        .args(["status", &station, "--no-pager"])
        .output()
        .map(|output| {
            let status = String::from_utf8_lossy(&output.stdout);
            status.contains("Online state: online") || status.contains("State: routable")
        })
        .unwrap_or(false);
    let ipv4 = Command::new("ip")
        .args(["-j", "address", "show", "dev", &station])
        .output()
        .ok()
        .and_then(|output| serde_json::from_slice::<Vec<Value>>(&output.stdout).ok())
        .unwrap_or_default()
        .into_iter()
        .flat_map(|item| {
            item.get("addr_info")
                .cloned()
                .unwrap_or(Value::Array(vec![]))
                .as_array()
                .cloned()
                .unwrap_or_default()
        })
        .filter(|item| item.get("family").and_then(Value::as_str) == Some("inet"))
        .filter_map(|item| {
            Some(format!(
                "{}/{}",
                item.get("local")?.as_str()?,
                item.get("prefixlen")?.as_u64()?
            ))
        })
        .collect();
    let saved = iwctl_output(&["known-networks", "list"])
        .unwrap_or_default()
        .lines()
        .skip(4)
        .filter_map(|line| {
            let tokens = line.split_whitespace().collect::<Vec<_>>();
            let security_index = tokens
                .iter()
                .position(|value| matches!(*value, "open" | "psk" | "8021x" | "wep" | "sae"))?;
            let ssid = tokens[..security_index]
                .join(" ")
                .trim_start_matches('>')
                .trim()
                .to_owned();
            (!ssid.is_empty()).then_some(ssid)
        })
        .collect::<std::collections::HashSet<_>>();
    let available_wifi = parse_iwctl_networks(
        &iwctl_output(&["station", &station, "get-networks", "rssi-dbms"]).unwrap_or_default(),
        &saved,
        connected_ssid.as_deref(),
    );
    let active = connected_ssid.clone().map(|ssid| {
        json!({"id": ssid, "uuid": connected_ssid.clone().unwrap_or_default(), "type": "wifi", "state": if online { "connected" } else { "connecting" }, "vpn": false, "default": online, "interface": station, "ipv4": ipv4, "ipv6": []})
    });
    Ok(NetworkState {
        connectivity: if online { "full" } else { "none" }.into(),
        connectivity_check_available: true,
        connectivity_check_enabled: true,
        nm_state: if online { "connected" } else { "disconnected" }.into(),
        networking_enabled: true,
        wifi_enabled: Some(true),
        wifi_hardware_enabled: Some(true),
        active_connection: active,
        available_wifi,
        connected_ssid,
        signal_strength,
        connected_bssid,
        frequency,
        channel,
        ipv4,
        ..Default::default()
    })
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
            addresses.push(format!("{address}/{prefix}"));
        }
    }
    Ok(addresses)
}

fn execute(command: &CommandRequest) -> io::Result<()> {
    if let CommandRequest::VpnSetEnabled { .. } = command {
        return Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "VPN control is not provided by iwd; use the system VPN manager",
        ));
    }
    match command {
        CommandRequest::WifiSetEnabled(enabled) => {
            let station = iwctl_station_for_action()?;
            let value = if *enabled { "on" } else { "off" };
            iwctl_output(&["device", &station, "set-property", "Powered", value]).map(|_| ())
        }
        CommandRequest::Refresh => {
            let station = iwctl_station_for_action()?;
            iwctl_output(&["station", &station, "scan"]).map(|_| ())
        }
        CommandRequest::ConnectSaved(ssid) => {
            let station = iwctl_station_for_action()?;
            iwctl_output(&["--dont-ask", "station", &station, "connect", ssid]).map(|_| ())
        }
        CommandRequest::Connect { ssid, passphrase } => {
            let station = iwctl_station_for_action()?;
            if passphrase.is_empty() {
                iwctl_output(&["--dont-ask", "station", &station, "connect", ssid]).map(|_| ())
            } else {
                let output = Command::new("iwctl")
                    .args([
                        "--passphrase",
                        passphrase,
                        "station",
                        &station,
                        "connect",
                        ssid,
                    ])
                    .output()?;
                if output.status.success() {
                    Ok(())
                } else {
                    let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
                    Err(io::Error::other(if detail.is_empty() {
                        "iwd rejected the Wi-Fi credentials".to_owned()
                    } else {
                        format!("iwd rejected the Wi-Fi credentials: {detail}")
                    }))
                }
            }
        }
        CommandRequest::Forget(ssid) => {
            iwctl_output(&["known-networks", ssid, "forget"]).map(|_| ())
        }
        CommandRequest::DisconnectWifi => {
            let station = iwctl_station_for_action()?;
            iwctl_output(&["station", &station, "disconnect"]).map(|_| ())
        }
        CommandRequest::VpnSetEnabled { .. } => unreachable!(),
    }
}

fn action_name(command: &CommandRequest) -> &'static str {
    match command {
        CommandRequest::WifiSetEnabled(_) => "wifi_power",
        CommandRequest::ConnectSaved(_) | CommandRequest::Connect { .. } => "connect",
        CommandRequest::Forget(_) => "forget",
        CommandRequest::DisconnectWifi => "disconnect",
        CommandRequest::Refresh => "refresh",
        CommandRequest::VpnSetEnabled { .. } => "vpn",
    }
}

fn action_ssid(command: &CommandRequest) -> Option<&str> {
    match command {
        CommandRequest::ConnectSaved(ssid)
        | CommandRequest::Connect { ssid, .. }
        | CommandRequest::Forget(ssid) => Some(ssid),
        _ => None,
    }
}

fn action_error_code(message: &str) -> &'static str {
    let message = message.to_ascii_lowercase();
    if message.contains("credential")
        || message.contains("passphrase")
        || message.contains("password")
    {
        "credentials_rejected"
    } else if message.contains("no iwd station")
        || message.contains("adapter")
        || message.contains("device not found")
    {
        "adapter_unavailable"
    } else if message.contains("timeout") || message.contains("timed out") {
        "timeout"
    } else if message.contains("not found") || message.contains("network") {
        "network_unavailable"
    } else {
        "action_failed"
    }
}

fn user_action_error(message: &str) -> &'static str {
    match action_error_code(message) {
        "credentials_rejected" => "Wi‑Fi password was rejected. Check it and try again.",
        "adapter_unavailable" => "The Wi‑Fi adapter is unavailable.",
        "timeout" => "The Wi‑Fi connection timed out. Try again.",
        "network_unavailable" => "That network is no longer available. Rescan and try again.",
        _ => "The Wi‑Fi action failed. Try again.",
    }
}

#[allow(dead_code)]
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
                CommandRequest::Connect { ssid, .. } => self.connected_uuid = Some(ssid),
                CommandRequest::Forget(_) => self.connected_uuid = None,
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
    fn parses_iwctl_networks_with_spaces_and_ansi_markers() {
        let output = "Available networks\n---\nNetwork name Security Signal\n---\n  > Home Hotspot psk -5100\n      Cafe open -8200\n";
        let saved = ["Home Hotspot".to_owned()].into_iter().collect();
        let networks = parse_iwctl_networks(output, &saved, Some("Home Hotspot"));
        assert_eq!(networks.len(), 2);
        assert_eq!(networks[0]["ssid"], json!("Home Hotspot"));
        assert_eq!(networks[0]["strength"], json!(49));
        assert_eq!(networks[0]["saved"], json!(true));
        assert_eq!(networks[0]["connected"], json!(true));
        assert_eq!(networks[1]["secure"], json!(false));
    }

    #[test]
    fn retries_transiently_missing_iwd_station() {
        let mut calls = 0;
        let mut sleeps = 0;
        let station = retry_iwd_station(
            || {
                calls += 1;
                if calls < 3 {
                    Err(io::Error::new(
                        io::ErrorKind::NotFound,
                        "no iwd station found",
                    ))
                } else {
                    Ok("wlan0".to_owned())
                }
            },
            |_| sleeps += 1,
            6,
            Duration::from_millis(250),
        )
        .expect("station should become available");

        assert_eq!(station, "wlan0");
        assert_eq!(calls, 3);
        assert_eq!(sleeps, 2);
    }

    #[test]
    fn reports_iwd_station_unavailable_after_bounded_retries() {
        let mut calls = 0;
        let error = retry_iwd_station(
            || {
                calls += 1;
                Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    "no iwd station found",
                ))
            },
            |_| {},
            3,
            Duration::ZERO,
        )
        .expect_err("station should remain unavailable");

        assert_eq!(calls, 3);
        assert_eq!(error.kind(), io::ErrorKind::NotFound);
        assert_eq!(action_error_code(&error.to_string()), "adapter_unavailable");
    }

    #[test]
    fn classifies_connection_errors_without_exposing_credentials() {
        assert_eq!(
            action_error_code("iwd rejected the Wi-Fi credentials: authentication failed"),
            "credentials_rejected"
        );
        assert_eq!(
            user_action_error("iwd rejected the Wi-Fi credentials: secret-passphrase"),
            "Wi‑Fi password was rejected. Check it and try again."
        );
        assert!(!user_action_error("password=secret-passphrase").contains("secret-passphrase"));
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
