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
    time::{Duration, SystemTime},
};

pub const PROVIDER: &str = "hyprland";

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct HyprlandState {
    pub focused_monitor: String,
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
            "focused_monitor".into(),
            self.focused_monitor.clone().into(),
        );
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
        // IPC event frames are also used as the QML provider snapshot. Keep
        // the event payload, but include the refreshed complete state so
        // window/workspace changes cannot leave the shell with stale arrays.
        let mut data = self.snapshot.data.clone();
        data.extend(self.data.clone());
        data
    }
    fn snapshot(&self) -> ProviderState {
        self.snapshot.clone()
    }
}

pub fn socket_dir() -> Option<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")?;
    // Prefer the explicit instance signature when the daemon was launched from
    // a Hyprland session (hyprctl/terminal environment).
    if let Some(signature) = env::var_os("HYPRLAND_INSTANCE_SIGNATURE") {
        let dir = PathBuf::from(&runtime).join("hypr").join(signature);
        if dir.join(".socket2.sock").exists() {
            return Some(dir);
        }
    }
    // systemd user services never inherit HYPRLAND_INSTANCE_SIGNATURE, so
    // discover the newest live instance under $XDG_RUNTIME_DIR/hypr/ — the
    // same resolution hyprctl itself uses.
    let hypr_root = PathBuf::from(&runtime).join("hypr");
    let mut best: Option<(SystemTime, PathBuf)> = None;
    if let Ok(entries) = std::fs::read_dir(&hypr_root) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.join(".socket2.sock").exists() {
                continue;
            }
            if let Ok(metadata) = std::fs::metadata(&path) {
                if let Ok(modified) = metadata.modified() {
                    if best.as_ref().map(|(t, _)| modified > *t).unwrap_or(true) {
                        best = Some((modified, path));
                    }
                }
            }
        }
    }
    best.map(|(_, path)| path)
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
                            if let Some((event, refreshes)) = apply_event(&line, &state) {
                                // Publish the event-backed state first. Socket queries are
                                // authoritative reconciliation and must never delay visible
                                // workspace/window focus feedback.
                                let _ = bus.publish(event);
                                let mut reconciled = false;
                                for query in refreshes {
                                    reconciled |= refresh_query(&dir, query, &state).is_ok();
                                }
                                if reconciled {
                                    if let Ok(current) = state.lock() {
                                        let _ = bus.publish(HyprlandEvent {
                                            event_type: "state_reconciled".into(),
                                            data: BTreeMap::new(),
                                            snapshot: current.data(ProviderStatus::Available),
                                        });
                                    }
                                }
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
        // fullscreen/layout endpoints were removed from Hyprland ≥ 0.56
        // ("unknown request"); both fields are driven by events instead.
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
    // Hyprland 0.56 removed the fullscreenstate/layout JSON endpoints.
    // These fields remain event-driven and start with their safe defaults.
    recompute_flags(&mut current);
    Ok(event)
}

fn array(value: &Value) -> Vec<Value> {
    value.as_array().cloned().unwrap_or_default()
}

fn recompute_flags(state: &mut HyprlandState) {
    if let Some(name) = state.monitors.iter().find_map(|monitor| {
        monitor
            .get("focused")
            .and_then(Value::as_bool)
            .filter(|focused| *focused)
            .and_then(|_| monitor.get("name"))
            .and_then(Value::as_str)
    }) {
        state.focused_monitor = name.to_owned();
    }
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

fn apply_event(line: &str, state: &Mutex<HyprlandState>) -> Option<(HyprlandEvent, Vec<Query>)> {
    let (kind, payload) = line.split_once(">>")?;
    let kind = kind.trim();
    let mut current = state.lock().ok()?;
    let refreshes = match kind {
        "workspace" => {
            set_active_workspace(&mut current, None, json!({"name": normalize(payload)}));
            vec![Query::Workspaces, Query::ActiveWorkspace, Query::Monitors]
        }
        "workspacev2" => {
            let (id, name) = split_once(payload);
            set_active_workspace(&mut current, None, workspace_value(id, name));
            vec![Query::Workspaces, Query::ActiveWorkspace, Query::Monitors]
        }
        "focusedmon" => {
            let (monitor, workspace) = split_once(payload);
            current.focused_monitor = monitor.clone();
            set_active_workspace(&mut current, Some(&monitor), json!({"name": workspace}));
            vec![Query::ActiveWorkspace, Query::Monitors]
        }
        "focusedmonv2" => {
            let (monitor, workspace_id) = split_once(payload);
            current.focused_monitor = monitor.clone();
            set_active_workspace(
                &mut current,
                Some(&monitor),
                workspace_value(workspace_id, String::new()),
            );
            vec![Query::ActiveWorkspace, Query::Monitors]
        }
        "openwindow" | "closewindow" | "movewindow" | "urgent" | "windowtitle" => {
            if kind == "closewindow" {
                clear_active_window_if_address(&mut current, payload);
            }
            vec![Query::Windows, Query::Workspaces, Query::ActiveWindow]
        }
        "windowtitlev2" => {
            let (address, title) = split_once(payload);
            update_window_title(&mut current, &address, &title);
            Vec::new()
        }
        "activewindow" => {
            apply_active_window_payload(&mut current, payload);
            vec![Query::ActiveWindow]
        }
        "activewindowv2" => {
            apply_active_window_address(&mut current, payload);
            vec![Query::ActiveWindow]
        }
        "monitoradded" | "monitorremoved" | "monitoraddedv2" | "monitorremovedv2" => {
            vec![Query::Monitors, Query::Workspaces]
        }
        "fullscreen" => {
            current.fullscreen = payload.trim() == "1";
            Vec::new()
        }
        "changefloating" | "changefloatingmode" => {
            current.floating = payload.rsplit(',').next().unwrap_or(payload).trim() == "1";
            Vec::new()
        }
        "activelayout" => {
            current.layout = payload
                .rsplit_once(',')
                .map(|(_, v)| normalize(v))
                .unwrap_or_else(|| normalize(payload));
            Vec::new()
        }
        "submap" => {
            current.submap = normalize(payload);
            Vec::new()
        }
        _ => return None,
    };
    recompute_flags(&mut current);
    let mut data = BTreeMap::new();
    data.insert("payload".into(), Value::String(normalize(payload)));
    let event = HyprlandEvent {
        event_type: normalize(kind),
        data,
        snapshot: current.data(ProviderStatus::Available),
    };
    Some((event, refreshes))
}

fn refresh_query(dir: &Path, query: Query, state: &Mutex<HyprlandState>) -> io::Result<()> {
    let request = match query {
        Query::Workspaces => "j/workspaces",
        Query::ActiveWorkspace => "j/activeworkspace",
        Query::Windows => "j/clients",
        Query::ActiveWindow => "j/activewindow",
        Query::Monitors => "j/monitors",
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
        Query::Workspaces => current.workspaces = array(&value),
        Query::ActiveWorkspace => current.active_workspace = Some(value),
    }
    recompute_flags(&mut current);
    Ok(())
}

fn split_once(payload: &str) -> (String, String) {
    payload
        .split_once(',')
        .map(|(first, rest)| (normalize(first), normalize(rest)))
        .unwrap_or_else(|| (normalize(payload), String::new()))
}

fn workspace_value(id: String, name: String) -> Value {
    if name.is_empty() {
        json!({"id": id.parse::<i64>().ok().map(Value::from).unwrap_or(Value::String(id))})
    } else {
        json!({"id": id.parse::<i64>().ok().map(Value::from).unwrap_or(Value::String(id)), "name": name})
    }
}

fn set_active_workspace(state: &mut HyprlandState, monitor: Option<&str>, workspace: Value) {
    state.active_workspace = Some(workspace.clone());
    let Some(monitor_name) = monitor else { return };
    for entry in &mut state.monitors {
        if entry.get("name").and_then(Value::as_str) == Some(monitor_name) {
            if let Some(object) = entry.as_object_mut() {
                object.insert("activeWorkspace".into(), workspace.clone());
                object.insert("active_workspace".into(), workspace.clone());
            }
        }
    }
}

fn same_address(left: &str, right: &str) -> bool {
    left.trim().trim_start_matches("0x") == right.trim().trim_start_matches("0x")
}

fn active_address(state: &HyprlandState) -> String {
    state
        .active_window
        .as_ref()
        .and_then(|window| window.get("address"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned()
}

fn clear_active_window_if_address(state: &mut HyprlandState, address: &str) {
    if same_address(&active_address(state), address) {
        state.active_window = None;
    }
}

fn apply_active_window_address(state: &mut HyprlandState, payload: &str) {
    let address = normalize(payload);
    if address.is_empty() {
        state.active_window = None;
        return;
    }
    state.active_window = state
        .windows
        .iter()
        .find(|window| {
            window
                .get("address")
                .and_then(Value::as_str)
                .map(|candidate| same_address(candidate, &address))
                .unwrap_or(false)
        })
        .cloned()
        .or_else(|| Some(json!({"address": address})));
}

fn apply_active_window_payload(state: &mut HyprlandState, payload: &str) {
    let (class, title) = split_once(payload);
    if class.is_empty() && title.is_empty() {
        state.active_window = None;
        return;
    }
    let cached = state.windows.iter().find(|window| {
        window.get("class").and_then(Value::as_str) == Some(class.as_str())
            && window.get("title").and_then(Value::as_str) == Some(title.as_str())
    });
    state.active_window = cached.cloned().or_else(|| {
        Some(normalize_window(json!({
            "class": class,
            "title": title,
        })))
    });
}

fn update_window_title(state: &mut HyprlandState, address: &str, title: &str) {
    for window in &mut state.windows {
        let matches = window
            .get("address")
            .and_then(Value::as_str)
            .map(|candidate| same_address(candidate, address))
            .unwrap_or(false);
        if matches {
            if let Some(object) = window.as_object_mut() {
                object.insert("title".into(), Value::String(title.to_owned()));
            }
        }
    }
    if same_address(&active_address(state), address) {
        if let Some(object) = state.active_window.as_mut().and_then(Value::as_object_mut) {
            object.insert("title".into(), Value::String(title.to_owned()));
        }
    }
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
    // Match hyprctl exactly: the request is written bare and the server reads
    // until EOF. A trailing newline is rejected as "unknown request" on
    // Hyprland ≥ 0.56.
    stream.write_all(request.as_bytes())?;
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
        assert!(apply_event("not-an-event", &Mutex::new(HyprlandState::default())).is_none());
    }
    #[test]
    fn event_names_and_payloads_are_normalized() {
        let e = apply_event("submap>>  resize\0", &Mutex::new(HyprlandState::default())).unwrap();
        assert_eq!(e.0.event_type, "submap");
        assert_eq!(e.0.snapshot.data["submap"], "resize");
    }

    #[test]
    fn fixture_events_cover_representative_state_changes() {
        let state = Mutex::new(HyprlandState::default());
        let mut seen = Vec::new();
        for line in include_str!("../../tests/fixtures/hyprland/events.ndjson").lines() {
            if let Some((event, _)) = apply_event(line, &state) {
                seen.push(event.event_type);
            }
        }
        assert_eq!(
            seen,
            [
                "workspace",
                "workspacev2",
                "focusedmon",
                "focusedmonv2",
                "activewindow",
                "activewindowv2",
                "windowtitlev2",
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

    #[test]
    fn workspace_events_apply_before_reconciliation() {
        let state = Mutex::new(HyprlandState {
            workspaces: vec![json!({"id": 1, "name": "1"})],
            monitors: vec![
                json!({"name": "eDP-1", "focused": true, "activeWorkspace": {"id": 1, "name": "1"}}),
            ],
            ..HyprlandState::default()
        });
        let (event, refreshes) = apply_event("focusedmon>>eDP-1,3", &state).unwrap();
        assert_eq!(event.snapshot.data["focused_monitor"], "eDP-1");
        assert_eq!(event.snapshot.data["active_workspace"]["name"], "3");
        assert_eq!(
            event.snapshot.data["monitors"][0]["activeWorkspace"]["name"],
            "3"
        );
        assert_eq!(
            event.snapshot.data["workspaces"].as_array().unwrap().len(),
            1
        );
        assert_eq!(refreshes, vec![Query::ActiveWorkspace, Query::Monitors]);
    }

    #[test]
    fn v2_workspace_and_window_events_are_normalized() {
        let state = Mutex::new(HyprlandState {
            windows: vec![json!({"address": "0xabc", "class": "kitty", "title": "Old"})],
            ..HyprlandState::default()
        });
        let (focus, _) = apply_event("activewindowv2>>abc", &state).unwrap();
        assert_eq!(focus.snapshot.data["active_window"]["title"], "Old");
        let (title, refreshes) = apply_event("windowtitlev2>>0xabc,One, two", &state).unwrap();
        assert_eq!(title.snapshot.data["active_window"]["title"], "One, two");
        assert!(refreshes.is_empty());
        let (workspace, _) = apply_event("workspacev2>>7,dev", &state).unwrap();
        assert_eq!(workspace.snapshot.data["active_workspace"]["id"], 7);
        assert_eq!(workspace.snapshot.data["active_workspace"]["name"], "dev");
    }

    #[test]
    fn legacy_active_window_preserves_titles_with_commas_and_empty_focus() {
        let state = Mutex::new(HyprlandState::default());
        let (event, _) = apply_event("activewindow>>firefox,Docs, issue 42", &state).unwrap();
        assert_eq!(
            event.snapshot.data["active_window"]["application_id"],
            "firefox"
        );
        assert_eq!(
            event.snapshot.data["active_window"]["title"],
            "Docs, issue 42"
        );
        let (empty, _) = apply_event("activewindow>>,", &state).unwrap();
        assert_eq!(empty.snapshot.data["active_window"], Value::Null);
    }

    #[test]
    fn closing_the_active_window_clears_it_without_waiting_for_query() {
        let state = Mutex::new(HyprlandState {
            active_window: Some(json!({"address": "0xabc", "title": "Terminal"})),
            ..HyprlandState::default()
        });
        let (event, _) = apply_event("closewindow>>abc", &state).unwrap();
        assert_eq!(event.snapshot.data["active_window"], Value::Null);
    }
}
