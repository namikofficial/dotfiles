//! Safe, event-driven display brightness provider.
//!
//! Device discovery is read-only. All mutations go through brightnessctl;
//! noxd never writes to sysfs brightness files itself.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fs, io,
    path::Path,
    process::Command,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::Duration,
};

pub const PROVIDER: &str = "brightness";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BacklightDevice {
    pub name: String,
    pub kind: String,
    pub max: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrightnessState {
    pub device: Option<BacklightDevice>,
    pub percentage: Option<u8>,
    pub minimum: u8,
    pub step: u8,
    pub external_backend: String,
    pub external_supported: bool,
    pub backend_available: bool,
}

impl BrightnessState {
    fn snapshot(&self, status: ProviderStatus) -> ProviderState {
        let mut data = BTreeMap::new();
        data.insert("percentage".into(), json!(self.percentage));
        data.insert("minimum".into(), json!(self.minimum));
        data.insert("step".into(), json!(self.step));
        data.insert(
            "device".into(),
            self.device
                .as_ref()
                .map(|d| {
                    json!({
                        "name": d.name,
                        "type": d.kind,
                        "max": d.max,
                    })
                })
                .unwrap_or(Value::Null),
        );
        data.insert("backend".into(), json!("brightnessctl"));
        data.insert("external_backend".into(), json!(self.external_backend));
        data.insert("external_supported".into(), json!(self.external_supported));
        data.insert("backend_available".into(), json!(self.backend_available));
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data,
        }
    }
}

#[derive(Debug, Clone)]
pub enum CommandRequest {
    Set { percentage: u8 },
    Adjust { delta: i16 },
}

#[derive(Clone)]
pub struct Control {
    sender: mpsc::Sender<CommandRequest>,
    available: Arc<AtomicBool>,
}

impl Control {
    pub fn send(&self, command: CommandRequest) -> io::Result<()> {
        if !self.available.load(Ordering::Relaxed) {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "brightness backend is unavailable",
            ));
        }
        self.sender
            .send(command)
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "brightness provider stopped"))
    }
}

pub fn start(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    minimum: u8,
    step: u8,
    external_backend: String,
) -> (thread::JoinHandle<()>, Control) {
    let (sender, receiver) = mpsc::channel();
    let available = Arc::new(AtomicBool::new(false));
    let control = Control {
        sender,
        available: Arc::clone(&available),
    };
    let thread = thread::spawn(move || {
        run(
            bus,
            stop,
            minimum,
            step,
            external_backend,
            available,
            receiver,
        )
    });
    (thread, control)
}

fn run(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    minimum: u8,
    step: u8,
    external_backend: String,
    available: Arc<AtomicBool>,
    receiver: mpsc::Receiver<CommandRequest>,
) {
    let mut state = read_state(minimum, step, &external_backend);
    available.store(state.backend_available, Ordering::Relaxed);
    publish_snapshot(&bus, &state, "state_changed", false);
    let poll_interval = Duration::from_secs(2);
    let mut last_poll = std::time::Instant::now();

    while !stop.load(Ordering::Relaxed) {
        match receiver.recv_timeout(Duration::from_millis(200)) {
            Ok(command) => {
                if execute(&command, &state).is_ok() {
                    state = read_state(minimum, step, &external_backend);
                    available.store(state.backend_available, Ordering::Relaxed);
                    publish_snapshot(&bus, &state, "brightness_changed", true);
                } else {
                    available.store(false, Ordering::Relaxed);
                    state.percentage = None;
                    publish_snapshot(&bus, &state, "backend_unavailable", false);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // Poll for external brightness changes (e.g. keyboard brightness keys)
                if last_poll.elapsed() >= poll_interval {
                    let prev_pct = state.percentage;
                    state = read_state(minimum, step, &external_backend);
                    let updated_backend = state.backend_available;
                    available.store(updated_backend, Ordering::Relaxed);
                    // Only publish if value changed or backend became available
                    if state.percentage != prev_pct
                        || (updated_backend && !available.load(Ordering::Relaxed))
                    {
                        publish_snapshot(&bus, &state, "brightness_changed", true);
                    }
                    last_poll = std::time::Instant::now();
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
}

fn publish_snapshot(bus: &EventBus, state: &BrightnessState, event_type: &str, changed: bool) {
    let mut data = BTreeMap::new();
    if changed {
        data.insert("percentage".into(), json!(state.percentage));
    }
    let status = if state.backend_available {
        ProviderStatus::Available
    } else {
        ProviderStatus::Unavailable
    };
    let _ = bus.publish(BrightnessEvent {
        event_type: event_type.into(),
        data,
        snapshot: state.snapshot(status),
    });
}

fn read_state(minimum: u8, step: u8, external_backend: &str) -> BrightnessState {
    let device = discover_devices(Path::new("/sys/class/backlight"))
        .ok()
        .and_then(|d| select_device(&d));
    let percentage = device.as_ref().and_then(|d| read_percentage(&d.name));
    let backend_available =
        device.is_some() && command_available("brightnessctl") && percentage.is_some();
    let external_supported = external_backend == "ddcutil" && command_available("ddcutil");
    BrightnessState {
        device,
        percentage,
        minimum,
        step,
        external_backend: external_backend.into(),
        external_supported,
        backend_available,
    }
}

fn command_available(command: &str) -> bool {
    Command::new("sh")
        .args(["-c", "command -v -- \"$1\" >/dev/null 2>&1", "sh", command])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn discover_devices(root: &Path) -> io::Result<Vec<BacklightDevice>> {
    let mut devices = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        let kind = fs::read_to_string(path.join("type"))
            .unwrap_or_default()
            .trim()
            .to_owned();
        if kind.is_empty()
            || !path.join("max_brightness").is_file()
            || !path.join("brightness").is_file()
        {
            continue;
        }
        let max = fs::read_to_string(path.join("max_brightness"))
            .ok()
            .and_then(|v| v.trim().parse().ok())
            .unwrap_or(0);
        if max > 0 {
            devices.push(BacklightDevice {
                name: entry.file_name().to_string_lossy().into_owned(),
                kind,
                max,
            });
        }
    }
    Ok(devices)
}

pub fn select_device(devices: &[BacklightDevice]) -> Option<BacklightDevice> {
    devices.iter().cloned().min_by(|a, b| {
        device_rank(&a.kind)
            .cmp(&device_rank(&b.kind))
            .then_with(|| b.max.cmp(&a.max))
            .then_with(|| a.name.cmp(&b.name))
    })
}

fn device_rank(kind: &str) -> u8 {
    match kind {
        "platform" => 0,
        "raw" => 1,
        "firmware" => 2,
        _ => 3,
    }
}

fn read_percentage(name: &str) -> Option<u8> {
    let current = brightnessctl_value(name, "get")?;
    let max = brightnessctl_value(name, "max")?;
    (max > 0).then(|| {
        ((current as f64 / max as f64) * 100.0)
            .round()
            .clamp(0.0, 100.0) as u8
    })
}

fn brightnessctl_value(name: &str, operation: &str) -> Option<u32> {
    let output = Command::new("brightnessctl")
        .args(["-d", name, operation])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8_lossy(&output.stdout).trim().parse().ok()
}

fn execute(command: &CommandRequest, state: &BrightnessState) -> io::Result<()> {
    let device = state.device.as_ref().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::Unsupported,
            "no internal backlight device detected",
        )
    })?;
    let current = state.percentage.unwrap_or(state.minimum) as i16;
    let requested = match command {
        CommandRequest::Set { percentage } => *percentage as i16,
        CommandRequest::Adjust { delta } => current + *delta,
    };
    let percentage = clamp_percentage(requested, state.minimum);
    let status = Command::new("brightnessctl")
        .args(["-d", &device.name, "set", &format!("{percentage}%")])
        .status()?;
    status
        .success()
        .then_some(())
        .ok_or_else(|| io::Error::other("brightnessctl action failed"))
}

pub fn clamp_percentage(value: i16, minimum: u8) -> u8 {
    value.clamp(minimum as i16, 100) as u8
}

#[derive(Debug, Clone)]
struct BrightnessEvent {
    event_type: String,
    data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}
impl ProviderEvent for BrightnessEvent {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_platform_then_maximum_then_name() {
        let devices = vec![
            BacklightDevice {
                name: "acpi_video0".into(),
                kind: "firmware".into(),
                max: 100,
            },
            BacklightDevice {
                name: "intel_backlight".into(),
                kind: "raw".into(),
                max: 937,
            },
            BacklightDevice {
                name: "platform_panel".into(),
                kind: "platform".into(),
                max: 1,
            },
        ];
        assert_eq!(select_device(&devices).unwrap().name, "platform_panel");
    }

    #[test]
    fn chooses_largest_raw_device_and_tie_breaks_by_name() {
        let devices = vec![
            BacklightDevice {
                name: "b".into(),
                kind: "raw".into(),
                max: 100,
            },
            BacklightDevice {
                name: "a".into(),
                kind: "raw".into(),
                max: 100,
            },
            BacklightDevice {
                name: "c".into(),
                kind: "raw".into(),
                max: 200,
            },
        ];
        assert_eq!(select_device(&devices).unwrap().name, "c");
    }

    #[test]
    fn percentage_is_clamped_to_safe_floor_and_ceiling() {
        assert_eq!(clamp_percentage(-5, 10), 10);
        assert_eq!(clamp_percentage(50, 10), 50);
        assert_eq!(clamp_percentage(150, 10), 100);
    }
}
