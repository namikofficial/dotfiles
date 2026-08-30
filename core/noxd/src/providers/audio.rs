//! Event-driven PipeWire audio provider.
//!
//! PipeWire's PulseAudio compatibility protocol provides the stable `pactl
//! subscribe` event stream and JSON object representation.  We use that
//! protocol for both observation and mutations; there is no periodic state
//! poll.  This also works with WirePlumber's normal PipeWire-Pulse setup.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{AudioTarget, ProviderState, ProviderStatus};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    io::{self, BufRead, BufReader},
    os::fd::AsRawFd,
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::Duration,
};

pub const PROVIDER: &str = "audio";

#[derive(Debug, Clone, PartialEq)]
pub struct AudioDevice {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub volume: u8,
    pub muted: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AudioStream {
    pub id: u32,
    pub name: String,
    pub application: Option<String>,
    pub direction: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct AudioState {
    pub default_output: Option<AudioDevice>,
    pub default_input: Option<AudioDevice>,
    pub output_volume: u8,
    pub input_volume: u8,
    pub output_muted: bool,
    pub input_muted: bool,
    pub outputs: Vec<AudioDevice>,
    pub inputs: Vec<AudioDevice>,
    pub streams: Vec<AudioStream>,
}

impl AudioState {
    fn snapshot(&self, status: ProviderStatus, max_volume: u8) -> ProviderState {
        let device = |d: &AudioDevice| {
            json!({
                "id": d.id, "name": d.name, "description": d.description,
                "volume": d.volume, "muted": d.muted,
            })
        };
        let stream = |s: &AudioStream| {
            json!({
                "id": s.id, "name": s.name, "application": s.application,
                "direction": s.direction,
            })
        };
        let mut data = BTreeMap::new();
        data.insert(
            "default_output".into(),
            self.default_output
                .as_ref()
                .map(device)
                .unwrap_or(Value::Null),
        );
        data.insert(
            "default_input".into(),
            self.default_input
                .as_ref()
                .map(device)
                .unwrap_or(Value::Null),
        );
        data.insert("output_volume".into(), json!(self.output_volume));
        data.insert("input_volume".into(), json!(self.input_volume));
        data.insert("output_muted".into(), json!(self.output_muted));
        data.insert("input_muted".into(), json!(self.input_muted));
        data.insert(
            "outputs".into(),
            json!(self.outputs.iter().map(device).collect::<Vec<_>>()),
        );
        data.insert(
            "inputs".into(),
            json!(self.inputs.iter().map(device).collect::<Vec<_>>()),
        );
        data.insert(
            "streams".into(),
            json!(self.streams.iter().map(stream).collect::<Vec<_>>()),
        );
        data.insert("max_volume".into(), json!(max_volume));
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AudioEvent {
    pub event_type: String,
    pub data: BTreeMap<String, Value>,
    pub snapshot: ProviderState,
}
impl ProviderEvent for AudioEvent {
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

#[derive(Debug, Clone)]
pub enum CommandRequest {
    SetVolume {
        target: AudioTarget,
        value: u8,
    },
    AdjustVolume {
        target: AudioTarget,
        delta: i16,
    },
    ToggleMute {
        target: AudioTarget,
    },
    SetDefault {
        target: AudioTarget,
        selector: String,
    },
}

pub type ControlSender = mpsc::Sender<CommandRequest>;

pub fn start(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    max_volume: u8,
) -> (thread::JoinHandle<()>, ControlSender) {
    let (sender, receiver) = mpsc::channel();
    let thread = thread::spawn(move || run(bus, stop, max_volume, receiver));
    (thread, sender)
}

fn run(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    max_volume: u8,
    receiver: mpsc::Receiver<CommandRequest>,
) {
    let action_stop = Arc::clone(&stop);
    let action_bus = bus.clone();
    thread::spawn(move || {
        while !action_stop.load(Ordering::Relaxed) {
            match receiver.recv_timeout(Duration::from_millis(200)) {
                Ok(command) => {
                    let _ = execute(command, max_volume);
                    let _ = refresh_and_publish(&action_bus, max_volume, "state_changed");
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(_) => break,
            }
        }
    });

    while !stop.load(Ordering::Relaxed) {
        let mut child = match Command::new("pactl")
            .arg("subscribe")
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(child) => child,
            Err(_) => {
                publish_unavailable(&bus, max_volume);
                thread::sleep(Duration::from_secs(1));
                continue;
            }
        };
        let _ = refresh_and_publish(&bus, max_volume, "state_changed");
        if let Some(stdout) = child.stdout.take() {
            set_nonblocking(stdout.as_raw_fd());
            let mut reader = BufReader::new(stdout);
            let mut line = String::new();
            while !stop.load(Ordering::Relaxed) {
                line.clear();
                match reader.read_line(&mut line) {
                    Ok(0) => break,
                    Ok(_) => {
                        if let Some(event) = subscribed_event_type(&line) {
                            let _ = refresh_and_publish(&bus, max_volume, event);
                        }
                    }
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(100))
                    }
                    Err(_) => break,
                }
            }
        }
        let _ = child.kill();
        let _ = child.wait();
    }
}

/// Map only audio-state events to provider refreshes.
///
/// Every `pactl` command creates short-lived PulseAudio client events. Refreshing
/// on those events launches more `pactl` commands, producing an unbounded
/// feedback loop across noxd, PipeWire, PipeWire-Pulse, and WirePlumber.
fn subscribed_event_type(line: &str) -> Option<&'static str> {
    if [
        " on sink #",
        " on source #",
        " on sink-input #",
        " on source-output #",
        " on server #",
    ]
    .iter()
    .any(|facility| line.contains(facility))
    {
        Some("state_changed")
    } else if line.contains(" on card #") || line.contains(" on module #") {
        Some("devices_changed")
    } else {
        None
    }
}

fn set_nonblocking(fd: i32) {
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        if flags >= 0 {
            let _ = libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
    }
}

fn pactl_json(args: &[&str]) -> io::Result<Value> {
    let output = Command::new("pactl")
        .args(["-f", "json"])
        .args(args)
        .output()?;
    if !output.status.success() {
        return Err(io::Error::other(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(io::Error::other)
}

fn pactl_text(args: &[&str]) -> io::Result<String> {
    let output = Command::new("pactl").args(args).output()?;
    if !output.status.success() {
        return Err(io::Error::other(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn number(v: &Value, key: &str) -> Option<u32> {
    v.get(key).and_then(Value::as_u64).map(|n| n as u32)
}
fn percent(v: &Value) -> u8 {
    v.get("front-left")
        .or_else(|| v.as_object().and_then(|o| o.values().next()))
        .and_then(|x| x.get("value_percent"))
        .and_then(Value::as_str)
        .and_then(|s| s.trim_end_matches('%').parse::<f32>().ok())
        .map(|n| n.round().clamp(0.0, 100.0) as u8)
        .unwrap_or(0)
}
fn device(v: &Value) -> Option<AudioDevice> {
    Some(AudioDevice {
        id: number(v, "index")?,
        name: v.get("name")?.as_str()?.into(),
        description: v
            .get("description")
            .and_then(Value::as_str)
            .unwrap_or("")
            .into(),
        volume: percent(v.get("volume")?),
        muted: v.get("mute").and_then(Value::as_bool).unwrap_or(false),
    })
}

pub fn parse_state(
    sinks: &Value,
    sources: &Value,
    sink_inputs: &Value,
    source_outputs: &Value,
    default_sink: Option<&str>,
    default_source: Option<&str>,
) -> AudioState {
    let outputs = sinks
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(device)
        .collect::<Vec<_>>();
    let inputs = sources
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(device)
        .collect::<Vec<_>>();
    let default_output = outputs
        .iter()
        .find(|d| Some(d.name.as_str()) == default_sink)
        .cloned();
    let default_input = inputs
        .iter()
        .find(|d| Some(d.name.as_str()) == default_source)
        .cloned();
    let streams = |value: &Value, direction: &str| {
        value
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|v| {
                Some(AudioStream {
                    id: number(v, "index")?,
                    name: v.get("name").and_then(Value::as_str).unwrap_or("").into(),
                    application: v
                        .get("properties")
                        .and_then(|p| p.get("application.name"))
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    direction: direction.into(),
                })
            })
            .collect::<Vec<_>>()
    };
    AudioState {
        output_volume: default_output.as_ref().map(|d| d.volume).unwrap_or(0),
        input_volume: default_input.as_ref().map(|d| d.volume).unwrap_or(0),
        output_muted: default_output.as_ref().map(|d| d.muted).unwrap_or(false),
        input_muted: default_input.as_ref().map(|d| d.muted).unwrap_or(false),
        default_output,
        default_input,
        outputs,
        inputs,
        streams: [
            streams(sink_inputs, "output"),
            streams(source_outputs, "input"),
        ]
        .concat(),
    }
}

pub fn clamp_volume(value: i16, max_volume: u8) -> u8 {
    value.clamp(0, max_volume as i16) as u8
}

pub fn resolve_device(devices: &[AudioDevice], selector: &str) -> io::Result<String> {
    if let Ok(id) = selector.parse::<u32>() {
        if devices.iter().any(|device| device.id == id) {
            return Ok(format!("#{id}"));
        }
    }
    let matches = devices
        .iter()
        .filter(|device| device.name == selector)
        .collect::<Vec<_>>();
    match matches.as_slice() {
        [device] => Ok(device.name.clone()),
        [] => Err(io::Error::new(
            io::ErrorKind::NotFound,
            "audio device not found",
        )),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "audio device selector is ambiguous",
        )),
    }
}

fn refresh_and_publish(bus: &EventBus, max_volume: u8, event_type: &str) -> io::Result<()> {
    let default_sink = pactl_text(&["get-default-sink"]).ok();
    let default_source = pactl_text(&["get-default-source"]).ok();
    let state = parse_state(
        &pactl_json(&["list", "sinks"])?,
        &pactl_json(&["list", "sources"])?,
        &pactl_json(&["list", "sink-inputs"])?,
        &pactl_json(&["list", "source-outputs"])?,
        default_sink.as_deref(),
        default_source.as_deref(),
    );
    let snapshot = state.snapshot(ProviderStatus::Available, max_volume);
    let mut data = BTreeMap::new();
    data.insert("output_volume".into(), json!(state.output_volume));
    data.insert("input_volume".into(), json!(state.input_volume));
    data.insert("output_muted".into(), json!(state.output_muted));
    data.insert("input_muted".into(), json!(state.input_muted));
    let _ = bus.publish(AudioEvent {
        event_type: event_type.into(),
        data,
        snapshot,
    });
    Ok(())
}

fn publish_unavailable(bus: &EventBus, max_volume: u8) {
    let snapshot = AudioState::default().snapshot(ProviderStatus::Unavailable, max_volume);
    let _ = bus.update_snapshot(snapshot);
}

fn execute(command: CommandRequest, max_volume: u8) -> io::Result<()> {
    let status = match command {
        CommandRequest::SetVolume { target, value } => Command::new("pactl")
            .args([
                "set-volume",
                target_name(&target),
                &format!("{}%", clamp_volume(value as i16, max_volume)),
            ])
            .status()?,
        CommandRequest::AdjustVolume { target, delta } => {
            let list = match target {
                AudioTarget::Output => pactl_json(&["list", "sinks"]),
                AudioTarget::Input => pactl_json(&["list", "sources"]),
            }?;
            let default_name = pactl_text(&[if matches!(target, AudioTarget::Output) {
                "get-default-sink"
            } else {
                "get-default-source"
            }])
            .unwrap_or_default();
            let current = list
                .as_array()
                .and_then(|items| {
                    items.iter().find(|item| {
                        item.get("name").and_then(Value::as_str) == Some(default_name.as_str())
                    })
                })
                .and_then(device)
                .map(|d| d.volume)
                .unwrap_or(0);
            let next = clamp_volume(current as i16 + delta, max_volume);
            Command::new("pactl")
                .args(["set-volume", target_name(&target), &format!("{next}%")])
                .status()?
        }
        CommandRequest::ToggleMute { target } => Command::new("pactl")
            .args(["set-mute", target_name(&target), "toggle"])
            .status()?,
        CommandRequest::SetDefault { target, selector } => {
            let list = match target {
                AudioTarget::Output => pactl_json(&["list", "sinks"]),
                AudioTarget::Input => pactl_json(&["list", "sources"]),
            }?;
            let devices = list
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(device)
                .collect::<Vec<_>>();
            let resolved = resolve_device(&devices, &selector)?;
            Command::new("pactl")
                .args([
                    match target {
                        AudioTarget::Output => "set-default-sink",
                        AudioTarget::Input => "set-default-source",
                    },
                    &resolved,
                ])
                .status()?
        }
    };
    if status.success() {
        Ok(())
    } else {
        Err(io::Error::other("pactl action failed"))
    }
}

fn target_name(target: &AudioTarget) -> &'static str {
    match target {
        AudioTarget::Output => "@DEFAULT_SINK@",
        AudioTarget::Input => "@DEFAULT_SOURCE@",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_devices_and_streams() {
        let d = json!([{"index":1,"name":"speaker","description":"Speakers","mute":false,"volume":{"front-left":{"value_percent":"42%"}}}]);
        let s = parse_state(
            &d,
            &d,
            &json!([]),
            &json!([]),
            Some("speaker"),
            Some("speaker"),
        );
        assert_eq!(s.output_volume, 42);
        assert_eq!(s.default_output.unwrap().id, 1);
    }
    #[test]
    fn selector_state_is_unambiguous_by_id_or_name() {
        let d =
            json!([{"index":1,"name":"speaker","description":"Speakers","mute":false,"volume":{}}]);
        let s = parse_state(
            &d,
            &json!([]),
            &json!([]),
            &json!([]),
            Some("speaker"),
            None,
        );
        assert_eq!(s.outputs[0].id, 1);
        assert_eq!(resolve_device(&s.outputs, "1").unwrap(), "#1");
        assert_eq!(resolve_device(&s.outputs, "speaker").unwrap(), "speaker");
        assert!(resolve_device(&s.outputs, "missing").is_err());
    }
    #[test]
    fn volume_is_clamped_to_configured_maximum() {
        assert_eq!(clamp_volume(-5, 100), 0);
        assert_eq!(clamp_volume(50, 100), 50);
        assert_eq!(clamp_volume(150, 100), 100);
    }

    #[test]
    fn subscription_refreshes_only_for_audio_state_events() {
        assert_eq!(
            subscribed_event_type("Event 'change' on sink #42"),
            Some("state_changed")
        );
        assert_eq!(
            subscribed_event_type("Event 'new' on source-output #7"),
            Some("state_changed")
        );
        assert_eq!(
            subscribed_event_type("Event 'change' on card #1"),
            Some("devices_changed")
        );
        assert_eq!(subscribed_event_type("Event 'new' on client #99"), None);
        assert_eq!(subscribed_event_type("Event 'remove' on client #99"), None);
    }
}
