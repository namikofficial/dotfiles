//! Battery, AC, and power-profile provider.
//!
//! Battery state is read from UPower over the system D-Bus. Power profiles
//! use power-profiles-daemon's D-Bus interface when it is available. The
//! provider is deliberately observational: it never requests suspend or
//! shutdown.

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
    blocking::{Connection, Proxy},
    zvariant::OwnedValue,
};

pub const PROVIDER: &str = "power";
const UPOWER_SERVICE: &str = "org.freedesktop.UPower";
const DISPLAY_DEVICE: &str = "/org/freedesktop/UPower/devices/DisplayDevice";
const AC_DEVICE: &str = "/org/freedesktop/UPower/devices/line_power_AC";
const PROFILE_SERVICE: &str = "org.freedesktop.UPower.PowerProfiles";
const PROFILE_PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
const PROFILE_INTERFACE: &str = "org.freedesktop.UPower.PowerProfiles";
const BATTERY_TYPE: u32 = 2;

#[derive(Debug, Clone, PartialEq)]
pub struct PowerProfile {
    pub name: String,
    pub driver: Option<String>,
    pub degraded: Option<bool>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RawPowerSnapshot {
    pub battery_present: bool,
    pub percentage: Option<f64>,
    pub charging_state: String,
    pub time_to_empty_seconds: Option<u64>,
    pub time_to_full_seconds: Option<u64>,
    pub health_percentage: Option<f64>,
    pub ac_online: Option<bool>,
    pub warning_level: u32,
    pub active_profile: Option<String>,
    pub available_profiles: Vec<PowerProfile>,
    pub profiles_available: bool,
}

impl Default for RawPowerSnapshot {
    fn default() -> Self {
        Self {
            battery_present: false,
            percentage: None,
            charging_state: "unknown".into(),
            time_to_empty_seconds: None,
            time_to_full_seconds: None,
            health_percentage: None,
            ac_online: None,
            warning_level: 0,
            active_profile: None,
            available_profiles: Vec::new(),
            profiles_available: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WarningTransition {
    Low,
    Critical,
}

#[derive(Debug, Default)]
struct WarningTracker {
    last_level: u32,
}

impl WarningTracker {
    fn transition(&mut self, snapshot: &RawPowerSnapshot) -> Option<WarningTransition> {
        let previous = self.last_level;
        self.last_level = if snapshot.battery_present && snapshot.ac_online != Some(true) {
            snapshot.warning_level
        } else {
            1
        };
        if previous == self.last_level {
            return None;
        }
        match self.last_level {
            3 => Some(WarningTransition::Low),
            4 | 5 => Some(WarningTransition::Critical),
            _ => None,
        }
    }
}

impl RawPowerSnapshot {
    pub fn snapshot(&self, status: ProviderStatus) -> ProviderState {
        let warning_name = warning_name(self.warning_level);
        let critical = matches!(self.warning_level, 4 | 5);
        let data = BTreeMap::from([
            ("battery_present".into(), json!(self.battery_present)),
            ("percentage".into(), option_json(self.percentage)),
            ("charging_state".into(), json!(self.charging_state)),
            (
                "time_to_empty_seconds".into(),
                option_json(self.time_to_empty_seconds),
            ),
            (
                "time_to_full_seconds".into(),
                option_json(self.time_to_full_seconds),
            ),
            (
                "health_percentage".into(),
                option_json(self.health_percentage),
            ),
            ("ac_online".into(), option_json(self.ac_online)),
            ("warning_level".into(), json!(warning_name)),
            ("warning_level_code".into(), json!(self.warning_level)),
            ("critical".into(), json!(critical)),
            (
                "active_profile".into(),
                option_json(self.active_profile.as_deref()),
            ),
            (
                "available_profiles".into(),
                json!(self
                    .available_profiles
                    .iter()
                    .map(|profile| {
                        json!({
                            "name": profile.name,
                            "driver": profile.driver,
                            "degraded": profile.degraded,
                        })
                    })
                    .collect::<Vec<_>>()),
            ),
            ("profiles_available".into(), json!(self.profiles_available)),
        ]);
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data,
        }
    }
}

fn option_json<T: serde::Serialize>(value: T) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

fn warning_name(level: u32) -> &'static str {
    match level {
        1 => "none",
        2 => "discharging",
        3 => "low",
        4 => "critical",
        5 => "action",
        _ => "unknown",
    }
}

#[derive(Debug, Clone)]
pub enum CommandRequest {
    SetProfile(String),
}

#[derive(Clone)]
pub struct Control {
    sender: mpsc::Sender<CommandRequest>,
    profiles_available: Arc<AtomicBool>,
}

impl Control {
    pub fn set_profile(&self, profile: String) -> io::Result<()> {
        if !self.profiles_available.load(Ordering::Relaxed) {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "power-profiles-daemon is unavailable",
            ));
        }
        self.sender
            .send(CommandRequest::SetProfile(profile))
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "power provider stopped"))
    }
}

pub fn start(bus: EventBus, stop: Arc<AtomicBool>) -> (thread::JoinHandle<()>, Control) {
    let (sender, receiver) = mpsc::channel();
    let profiles_available = Arc::new(AtomicBool::new(false));
    let control = Control {
        sender,
        profiles_available: Arc::clone(&profiles_available),
    };
    let thread = thread::spawn(move || run(bus, stop, profiles_available, receiver));
    (thread, control)
}

fn run(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    profiles_available: Arc<AtomicBool>,
    receiver: mpsc::Receiver<CommandRequest>,
) {
    let mut previous: Option<RawPowerSnapshot> = None;
    let mut warnings = WarningTracker::default();
    while !stop.load(Ordering::Relaxed) {
        while let Ok(command) = receiver.try_recv() {
            let CommandRequest::SetProfile(profile) = command;
            let _ = set_profile(&profile);
        }
        match read_snapshot() {
            Ok(snapshot) => {
                profiles_available.store(snapshot.profiles_available, Ordering::Relaxed);
                let changed = previous.as_ref() != Some(&snapshot);
                let status = if snapshot.profiles_available {
                    ProviderStatus::Available
                } else {
                    ProviderStatus::Degraded
                };
                if changed {
                    let _ = bus.publish(PowerEvent {
                        event_type: "state_changed".into(),
                        data: changed_data(&snapshot),
                        snapshot: snapshot.snapshot(status.clone()),
                    });
                } else {
                    let _ = bus.update_snapshot(snapshot.snapshot(status.clone()));
                }
                if let Some(transition) = warnings.transition(&snapshot) {
                    let event_type = match transition {
                        WarningTransition::Low => "battery_low",
                        WarningTransition::Critical => "battery_critical",
                    };
                    let _ = bus.publish(PowerEvent {
                        event_type: event_type.into(),
                        data: warning_data(&snapshot),
                        snapshot: snapshot.snapshot(status),
                    });
                }
                previous = Some(snapshot);
            }
            Err(_) => {
                profiles_available.store(false, Ordering::Relaxed);
                let snapshot = RawPowerSnapshot::default();
                let _ = bus.update_snapshot(snapshot.snapshot(ProviderStatus::Unavailable));
                previous = None;
                warnings = WarningTracker::default();
            }
        }
        thread::sleep(Duration::from_secs(2));
    }
}

fn changed_data(snapshot: &RawPowerSnapshot) -> BTreeMap<String, Value> {
    BTreeMap::from([
        ("percentage".into(), option_json(snapshot.percentage)),
        ("charging_state".into(), json!(snapshot.charging_state)),
        ("ac_online".into(), option_json(snapshot.ac_online)),
        (
            "active_profile".into(),
            option_json(snapshot.active_profile.as_deref()),
        ),
    ])
}

fn warning_data(snapshot: &RawPowerSnapshot) -> BTreeMap<String, Value> {
    BTreeMap::from([
        (
            "warning_level".into(),
            json!(warning_name(snapshot.warning_level)),
        ),
        ("percentage".into(), option_json(snapshot.percentage)),
        (
            "critical".into(),
            json!(matches!(snapshot.warning_level, 4 | 5)),
        ),
    ])
}

#[derive(Debug, Clone)]
struct PowerEvent {
    event_type: String,
    data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}

impl ProviderEvent for PowerEvent {
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

fn read_snapshot() -> io::Result<RawPowerSnapshot> {
    let connection = Connection::system().map_err(io::Error::other)?;
    let display = Proxy::new(
        &connection,
        UPOWER_SERVICE,
        DISPLAY_DEVICE,
        "org.freedesktop.UPower.Device",
    )
    .map_err(io::Error::other)?;
    let battery_present: u32 = display.get_property("Type").map_err(io::Error::other)?;
    let battery_present = battery_present == BATTERY_TYPE;
    let ac_online = Proxy::new(
        &connection,
        UPOWER_SERVICE,
        AC_DEVICE,
        "org.freedesktop.UPower.Device",
    )
    .ok()
    .and_then(|proxy| proxy.get_property::<bool>("Online").ok());
    let mut snapshot = RawPowerSnapshot {
        battery_present,
        ac_online,
        ..Default::default()
    };
    if battery_present {
        snapshot.percentage = display.get_property("Percentage").ok();
        snapshot.charging_state = display
            .get_property::<u32>("State")
            .map(|state| charging_state(state).into())
            .unwrap_or_else(|_| "unknown".into());
        snapshot.time_to_empty_seconds = positive_seconds(display.get_property("TimeToEmpty").ok());
        snapshot.time_to_full_seconds = positive_seconds(display.get_property("TimeToFull").ok());
        snapshot.health_percentage = display.get_property("Capacity").ok();
        snapshot.warning_level = display.get_property("WarningLevel").unwrap_or(0);
    }
    if let Ok(profile_proxy) = Proxy::new(
        &connection,
        PROFILE_SERVICE,
        PROFILE_PATH,
        PROFILE_INTERFACE,
    ) {
        snapshot.active_profile = profile_proxy.get_property("ActiveProfile").ok();
        if let Ok(profiles) =
            profile_proxy.get_property::<Vec<HashMap<String, OwnedValue>>>("Profiles")
        {
            snapshot.available_profiles = profiles.into_iter().filter_map(profile).collect();
            snapshot.profiles_available = true;
        }
    }
    Ok(snapshot)
}

fn set_profile(profile: &str) -> io::Result<()> {
    let connection = Connection::system().map_err(io::Error::other)?;
    let proxy = Proxy::new(
        &connection,
        PROFILE_SERVICE,
        PROFILE_PATH,
        PROFILE_INTERFACE,
    )
    .map_err(io::Error::other)?;
    proxy
        .set_property("ActiveProfile", profile)
        .map_err(io::Error::other)
}

fn profile(values: HashMap<String, OwnedValue>) -> Option<PowerProfile> {
    let name = values.get("Profile")?.downcast_ref::<String>().ok()?;
    let driver = values
        .get("Driver")
        .and_then(|value| value.downcast_ref::<String>().ok());
    let degraded = values
        .get("Degraded")
        .and_then(|value| value.downcast_ref::<bool>().ok());
    Some(PowerProfile {
        name,
        driver,
        degraded,
    })
}

fn positive_seconds(value: Option<u64>) -> Option<u64> {
    value.filter(|seconds| *seconds > 0)
}

fn charging_state(state: u32) -> &'static str {
    match state {
        1 => "charging",
        2 => "discharging",
        3 => "empty",
        4 => "fully_charged",
        5 => "pending_charge",
        6 => "pending_discharge",
        _ => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn battery(level: u32, ac_online: Option<bool>) -> RawPowerSnapshot {
        RawPowerSnapshot {
            battery_present: true,
            percentage: Some(12.5),
            charging_state: "discharging".into(),
            time_to_empty_seconds: Some(3600),
            health_percentage: Some(91.0),
            warning_level: level,
            ac_online,
            ..Default::default()
        }
    }

    #[test]
    fn snapshot_exposes_battery_and_profile_capabilities() {
        let mut state = battery(3, Some(false));
        state.active_profile = Some("balanced".into());
        state.profiles_available = true;
        state.available_profiles.push(PowerProfile {
            name: "balanced".into(),
            driver: None,
            degraded: Some(false),
        });
        let snapshot = state.snapshot(ProviderStatus::Available);
        assert_eq!(snapshot.data["percentage"], json!(12.5));
        assert_eq!(snapshot.data["warning_level"], json!("low"));
        assert_eq!(snapshot.data["active_profile"], json!("balanced"));
        assert_eq!(snapshot.data["profiles_available"], json!(true));
    }

    #[test]
    fn warning_tracker_emits_once_per_level_and_resets_when_charging() {
        let mut tracker = WarningTracker::default();
        assert_eq!(
            tracker.transition(&battery(3, Some(false))),
            Some(WarningTransition::Low)
        );
        assert_eq!(tracker.transition(&battery(3, Some(false))), None);
        assert_eq!(
            tracker.transition(&battery(4, Some(false))),
            Some(WarningTransition::Critical)
        );
        assert_eq!(tracker.transition(&battery(4, Some(true))), None);
        assert_eq!(
            tracker.transition(&battery(3, Some(false))),
            Some(WarningTransition::Low)
        );
    }

    #[test]
    fn no_battery_keeps_optional_fields_empty() {
        let state = RawPowerSnapshot {
            ac_online: Some(true),
            ..Default::default()
        };
        let snapshot = state.snapshot(ProviderStatus::Degraded);
        assert_eq!(snapshot.data["battery_present"], json!(false));
        assert_eq!(snapshot.data["percentage"], Value::Null);
        assert_eq!(snapshot.data["ac_online"], json!(true));
    }
}
