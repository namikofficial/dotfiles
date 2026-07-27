//! Event-driven Hyprland state provider.
//!
//! Hyprland exposes two local sockets per instance: `.socket.sock` for JSON
//! commands and `.socket2.sock` for newline-delimited events.  Keeping this
//! code here (instead of shelling out to `hyprctl`) also makes it usable in
//! tests with a pair of Unix socket fixtures.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{Action, ProviderState, ProviderStatus};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    env,
    io::{self, BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

pub const PROVIDER: &str = "hyprland";

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct HyprlandState {
    pub active_workspace: Option<Value>,
    pub workspaces: Vec<Value>,
    pub active_window: Option<Value>,
    pub windows: Vec<Value>,
    pub monitors: Vec<Value>,
    pub fullscreen: bool,
    pub floating: bool,
    pub urgent_windows: Vec<String>,
    pub special_workspaces: Vec<Value>,
    pub submap: String,
    pub layout: String,
}

impl HyprlandState {
    fn data(&self, status: ProviderStatus) -> ProviderState {
        let mut data = BTreeMap::new();
        data.insert(
            "active_workspace".into(),
            self.active_workspace.clone().unwrap_or(Value::Null),
        );
        data.insert("workspaces".into(), json!(self.workspaces));
        data.insert(
            "active_window".into(),
            self.active_window.clone().unwrap_or(Value::Null),
        );
        data.insert("windows".into(), json!(self.windows));
        data.insert("monitors".into(), json!(self.monitors));
        data.insert("fullscreen".into(), self.fullscreen.into());
        data.insert("floating".into(), self.floating.into());
        data.insert("urgent_windows".into(), json!(self.urgent_windows));
        data.insert("special_workspaces".into(), json!(self.special_workspaces));
        data.insert("submap".into(), self.submap.clone().into());
        data.insert("layout".into(), self.layout.clone().into());
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum Query {
    Workspaces,
    ActiveWorkspace,
    Windows,
    ActiveWindow,
    Monitors,
    Fullscreen,
    Layout,
}

#[derive(Debug, Clone)]
pub struct HyprlandEvent {
    pub event_type: String,
    pub data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}

impl ProviderEvent for HyprlandEvent {
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

pub fn socket_dir() -> Option<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")?;
    let signature = env::var_os("HYPRLAND_INSTANCE_SIGNATURE")?;
    Some(PathBuf::from(runtime).join("hypr").join(signature))
}

/// Dispatch a workspace action through Hyprland's command socket.
pub fn dispatch_workspace(action: &Action) -> io::Result<()> {
    let directory = socket_dir().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::NotFound,
            "Hyprland runtime socket is unavailable",
        )
    })?;
    let command = match action {
        Action::WorkspaceFocus { workspace } => {
            if workspace.is_empty() || workspace.contains('\n') {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "workspace name is invalid",
                ));
            }
            format!("dispatch workspace {workspace}")
        }
        Action::WorkspaceCycle { delta } if *delta == 1 => "dispatch workspace e+1".into(),
        Action::WorkspaceCycle { delta } if *delta == -1 => "dispatch workspace e-1".into(),
        Action::WorkspaceCycle { .. } => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "workspace cycle delta must be -1 or 1",
            ))
        }
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "action is not a workspace action",
            ))
        }
    };
    let mut stream = UnixStream::connect(directory.join(".socket.sock"))?;
    stream.write_all(command.as_bytes())?;
    stream.shutdown(std::net::Shutdown::Write)
}

/// Start the provider worker. The returned thread exits when `stop` is set.
pub fn start(bus: EventBus, stop: Arc<AtomicBool>) -> thread::JoinHandle<()> {
    thread::spawn(move || run(bus, stop, socket_dir))
}

fn run<F>(bus: EventBus, stop: Arc<AtomicBool>, directory: F)
where
    F: Fn() -> Option<PathBuf>,
{
    let state = Arc::new(Mutex::new(HyprlandState::default()));
    let mut unavailable_sent = false;
    while !stop.load(Ordering::Relaxed) {
        let Some(dir) = directory() else {
            thread::sleep(Duration::from_secs(1));
            continue;
        };
        match connect_and_sync(&dir, &state) {
            Ok(events) => {
                unavailable_sent = false;
                if let Ok(snapshot) = state.lock().map(|s| s.data(ProviderStatus::Available)) {
                    let _ = bus.update_snapshot(snapshot);
                }
                events.set_read_timeout(Some(Duration::from_secs(1))).ok();
                let reader = BufReader::new(events.try_clone().expect("event socket clone"));
                for line in reader.lines() {
                    if stop.load(Ordering::Relaxed) {
                        break;
                    }
                    match line {
                        Ok(line) => {
                            if let Some(event) = apply_event(&line, &state, &dir) {
                                let _ = bus.publish(event);
                            }
                        }
                        Err(_) => break,
                    }
                }
                let _ = events.shutdown(std::net::Shutdown::Both);
            }
            Err(_) => {
                if !unavailable_sent {
                    unavailable_sent = true;
                    if let Ok(snapshot) = state.lock().map(|s| s.data(ProviderStatus::Unavailable))
                    {
                        let _ = bus.update_snapshot(snapshot);
                    }
                }
                thread::sleep(Duration::from_millis(500));
            }
        }
    }
}

fn connect_and_sync(dir: &Path, state: &Mutex<HyprlandState>) -> io::Result<UnixStream> {
    let event = UnixStream::connect(dir.join(".socket2.sock"))?;
    let queries = [
        (Query::Workspaces, "j/workspaces"),
        (Query::ActiveWorkspace, "j/activeworkspace"),
        (Query::Windows, "j/clients"),
        (Query::ActiveWindow, "j/activewindow"),
        (Query::Monitors, "j/monitors"),
        (Query::Fullscreen, "j/fullscreenstate"),
        (Query::Layout, "j/layouts"),
    ];
    let mut values = HashMap::new();
    for (kind, request) in queries {
        let response = query_json(dir, request)?;
        if let Ok(value) = serde_json::from_str::<Value>(&response) {
            values.insert(kind, value);
        }
    }
    let mut current = state
        .lock()
        .map_err(|_| io::Error::other("state poisoned"))?;
    current.workspaces = values
        .get(&Query::Workspaces)
        .map(array)
        .unwrap_or_default();
    current.active_workspace = values.get(&Query::ActiveWorkspace).cloned();
    current.windows = values
        .get(&Query::Windows)
        .map(array)
        .unwrap_or_default()
        .into_iter()
        .map(normalize_window)
        .collect();
    current.active_window = values
        .get(&Query::ActiveWindow)
        .cloned()
        .map(normalize_window);
    current.monitors = values.get(&Query::Monitors).map(array).unwrap_or_default();
    current.fullscreen = values
        .get(&Query::Fullscreen)
        .and_then(Value::as_object)
        .and_then(|v| v.get("fullscreen"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    current.layout = values
        .get(&Query::Layout)
        .and_then(|v| v.as_array())
        .and_then(|v| v.first())
        .and_then(|v| v.get("name"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .into();
    recompute_flags(&mut current);
    Ok(event)
}

fn array(value: &Value) -> Vec<Value> {
    value.as_array().cloned().unwrap_or_default()
}

fn recompute_flags(state: &mut HyprlandState) {
    state.urgent_windows = state
        .windows
        .iter()
        .filter(|w| w.get("urgent").and_then(Value::as_bool).unwrap_or(false))
        .filter_map(|w| w.get("address").and_then(Value::as_str).map(str::to_owned))
        .collect();
    state.special_workspaces = state
        .workspaces
        .iter()
        .filter(|w| {
            w.get("name")
                .and_then(Value::as_str)
                .map(|n| n.starts_with("special:"))
                .unwrap_or(false)
        })
        .cloned()
        .collect();
    state.floating = state
        .active_window
        .as_ref()
        .and_then(|w| w.get("floating"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
}

fn apply_event(line: &str, state: &Mutex<HyprlandState>, dir: &Path) -> Option<HyprlandEvent> {
    let (kind, payload) = line.split_once(">>")?;
    let kind = kind.trim();
    let mut current = state.lock().ok()?;
    let needs = match kind {
        "workspace" | "focusedmon" => {
            current.active_workspace = Some(json!({"name": normalize(payload)}));
            Some(Query::ActiveWorkspace)
        }
        "openwindow" | "closewindow" | "movewindow" | "urgent" | "windowtitle" => {
            Some(Query::Windows)
        }
        "activewindow" => Some(Query::ActiveWindow),
        "monitoradded" | "monitorremoved" | "monitoraddedv2" | "monitorremovedv2" => {
            Some(Query::Monitors)
        }
        "fullscreen" => {
            current.fullscreen = payload.trim() == "1";
            None
        }
        "changefloating" => {
            current.floating = payload.trim() == "1";
            None
        }
        "activelayout" => {
            current.layout = normalize(payload);
            None
        }
        "submap" => {
            current.submap = normalize(payload);
            None
        }
        _ => return None,
    };
    drop(current);
    if let Some(query) = needs {
        refresh_query(dir, query, state).ok();
    }
    let current = state.lock().ok()?;
    let mut data = BTreeMap::new();
    data.insert("payload".into(), Value::String(normalize(payload)));
    Some(HyprlandEvent {
        event_type: normalize(kind),
        data,
        snapshot: current.data(ProviderStatus::Available),
    })
}

fn refresh_query(dir: &Path, query: Query, state: &Mutex<HyprlandState>) -> io::Result<()> {
    let request = match query {
        Query::Workspaces | Query::ActiveWorkspace => "j/activeworkspace",
        Query::Windows => "j/clients",
        Query::ActiveWindow => "j/activewindow",
        Query::Monitors => "j/monitors",
        Query::Fullscreen => "j/fullscreenstate",
        Query::Layout => "j/layouts",
    };
    let response = query_json(dir, request)?;
    let value: Value = serde_json::from_str(&response).map_err(io::Error::other)?;
    let mut current = state
        .lock()
        .map_err(|_| io::Error::other("state poisoned"))?;
    match query {
        Query::Windows => {
            current.windows = array(&value).into_iter().map(normalize_window).collect()
        }
        Query::ActiveWindow => current.active_window = Some(normalize_window(value)),
        Query::Monitors => current.monitors = array(&value),
        Query::Fullscreen => {
            current.fullscreen = value
                .get("fullscreen")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        }
        Query::Layout => {
            current.layout = value
                .as_array()
                .and_then(|v| v.first())
                .and_then(|v| v.get("name"))
                .and_then(Value::as_str)
                .unwrap_or("")
                .into()
        }
        Query::ActiveWorkspace | Query::Workspaces => current.active_workspace = Some(value),
    }
    recompute_flags(&mut current);
    Ok(())
}

fn normalize(value: &str) -> String {
    value.trim().replace('\0', "")
}

fn normalize_window(mut value: Value) -> Value {
    if let Some(object) = value.as_object_mut() {
        for key in ["class", "initialClass", "appid", "title", "initialTitle"] {
            if let Some(text) = object.get(key).and_then(Value::as_str).map(normalize) {
                object.insert(key.into(), Value::String(text));
            }
        }
        let application_id = object
            .get("appid")
            .or_else(|| object.get("class"))
            .and_then(Value::as_str)
            .map(str::to_owned);
        if let Some(application_id) = application_id {
            object.insert("application_id".into(), Value::String(application_id));
        }
        if !object.contains_key("title") {
            object.insert("title".into(), Value::String(String::new()));
        }
    }
    value
}

fn query_json(dir: &Path, request: &str) -> io::Result<String> {
    let mut stream = UnixStream::connect(dir.join(".socket.sock"))?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.write_all(format!("{request}\n").as_bytes())?;
    stream.shutdown(std::net::Shutdown::Write)?;
    let mut bytes = Vec::new();
    io::Read::read_to_end(&mut stream, &mut bytes)?;
    String::from_utf8(bytes).map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_events_are_ignored() {
        assert!(apply_event(
            "not-an-event",
            &Mutex::new(HyprlandState::default()),
            Path::new("/missing")
        )
        .is_none());
    }
    #[test]
    fn event_names_and_payloads_are_normalized() {
        let e = apply_event(
            "submap>>  resize\0",
            &Mutex::new(HyprlandState::default()),
            Path::new("/missing"),
        )
        .unwrap();
        assert_eq!(e.event_type, "submap");
        assert_eq!(e.snapshot.data["submap"], "resize");
    }

    #[test]
    fn fixture_events_cover_representative_state_changes() {
        let state = Mutex::new(HyprlandState::default());
        let mut seen = Vec::new();
        for line in include_str!("../../tests/fixtures/hyprland/events.ndjson").lines() {
            if let Some(event) = apply_event(line, &state, Path::new("/missing")) {
                seen.push(event.event_type);
            }
        }
        assert_eq!(
            seen,
            [
                "workspace",
                "activewindow",
                "fullscreen",
                "changefloating",
                "urgent",
                "submap",
                "activelayout"
            ]
        );
    }

    #[test]
    fn application_id_and_title_are_normalized() {
        let window =
            normalize_window(json!({"class": " org.example.App ", "title": "  Hello\u{0000}  "}));
        assert_eq!(window["application_id"], "org.example.App");
        assert_eq!(window["title"], "Hello");
    }
}
