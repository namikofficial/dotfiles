//! Event-driven MPRIS media provider.

use crate::{EventBus, ProviderEvent};
use noxflow_ipc::{ProviderState, ProviderStatus};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    fs, io,
    io::Read,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use zbus::{
    blocking::{Connection, MessageIterator, Proxy},
    zvariant::{Array, OwnedValue},
    MatchRule,
};

pub const PROVIDER: &str = "media";
const PLAYER_INTERFACE: &str = "org.mpris.MediaPlayer2.Player";
const DBUS_SERVICE: &str = "org.freedesktop.DBus";
const DBUS_PATH: &str = "/org/freedesktop/DBus";
const DBUS_INTERFACE: &str = "org.freedesktop.DBus";
const PLAYER_PATH: &str = "/org/mpris/MediaPlayer2";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlayerChoice {
    pub name: String,
    pub status: String,
    pub last_interaction: u64,
    pub usable: bool,
}

/// Selects a player using the provider's documented priority order.
pub fn select_active_player(
    players: &[PlayerChoice],
    pinned: Option<&str>,
    default_player: &str,
) -> Option<String> {
    if let Some(name) = pinned {
        if players.iter().any(|p| p.name == name && p.usable) {
            return Some(name.to_owned());
        }
    }
    players
        .iter()
        .filter(|p| p.usable && p.status == "Playing")
        .max_by_key(|p| (p.last_interaction, std::cmp::Reverse(p.name.clone())))
        .or_else(|| {
            players
                .iter()
                .find(|p| p.usable && p.name == default_player)
        })
        .or_else(|| {
            players
                .iter()
                .filter(|p| p.usable)
                .max_by_key(|p| (p.last_interaction, std::cmp::Reverse(p.name.clone())))
        })
        .map(|p| p.name.clone())
}

#[derive(Debug, Clone, Default)]
struct PlayerState {
    name: String,
    identity: String,
    desktop_entry: String,
    status: String,
    title: Option<String>,
    artist: Vec<String>,
    album: Option<String>,
    artwork_url: Option<String>,
    artwork_cache: Option<String>,
    position_us: Option<i64>,
    position_updated_at: u64,
    duration_us: Option<i64>,
    volume: Option<f64>,
    shuffle: Option<bool>,
    repeat: Option<String>,
    can_seek: bool,
    can_control: bool,
    last_interaction: u64,
}

impl PlayerState {
    fn usable(&self) -> bool {
        self.can_control || self.status != "Stopped"
    }

    fn choice(&self) -> PlayerChoice {
        PlayerChoice {
            name: self.name.clone(),
            status: self.status.clone(),
            last_interaction: self.last_interaction,
            usable: self.usable(),
        }
    }

    fn value(&self) -> Value {
        json!({
            "name": self.name, "identity": self.identity, "desktop_entry": self.desktop_entry,
            "playback_status": self.status, "title": self.title, "artist": self.artist,
            "album": self.album, "artwork_url": self.artwork_url, "artwork_cache": self.artwork_cache,
            "position": self.position_us, "position_updated_at": self.position_updated_at,
            "duration": self.duration_us, "volume": self.volume, "shuffle": self.shuffle,
            "repeat": self.repeat, "can_seek": self.can_seek, "can_control": self.can_control,
        })
    }
}

#[derive(Debug, Clone)]
struct MediaState {
    players: BTreeMap<String, PlayerState>,
    active: Option<String>,
    pinned: Option<String>,
    default_player: String,
}

impl MediaState {
    fn snapshot(&self, status: ProviderStatus) -> ProviderState {
        let choices: Vec<_> = self.players.values().map(PlayerState::value).collect();
        let active = self
            .active
            .as_ref()
            .and_then(|name| self.players.get(name))
            .map(PlayerState::value);
        ProviderState {
            provider: PROVIDER.into(),
            status,
            data: BTreeMap::from([
                ("players".into(), json!(choices)),
                (
                    "available_players".into(),
                    json!(self.players.keys().collect::<Vec<_>>()),
                ),
                (
                    "active_player".into(),
                    self.active
                        .clone()
                        .map(Value::String)
                        .unwrap_or(Value::Null),
                ),
                ("active".into(), active.unwrap_or(Value::Null)),
            ]),
        }
    }
}

#[derive(Debug, Clone)]
pub enum CommandRequest {
    Play,
    Pause,
    PlayPause,
    Previous,
    Next,
    Seek { offset_us: i64 },
    SelectPlayer { player: String },
}

pub type ControlSender = mpsc::Sender<CommandRequest>;

#[derive(Debug, Clone)]
pub struct ArtworkCacheConfig {
    pub enabled: bool,
    pub directory: PathBuf,
    pub max_bytes: u64,
    pub ttl: Duration,
}

pub fn start(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    enabled: bool,
    default_player: String,
    cache: ArtworkCacheConfig,
) -> (thread::JoinHandle<()>, ControlSender) {
    let (sender, receiver) = mpsc::channel();
    let control = sender.clone();
    let thread = thread::spawn(move || run(bus, stop, receiver, enabled, default_player, cache));
    (thread, control)
}

fn run(
    bus: EventBus,
    stop: Arc<AtomicBool>,
    receiver: mpsc::Receiver<CommandRequest>,
    enabled: bool,
    default_player: String,
    cache: ArtworkCacheConfig,
) {
    let mut state = MediaState {
        players: BTreeMap::new(),
        active: None,
        pinned: None,
        default_player,
    };
    if !enabled {
        let _ = bus.update_snapshot(state.snapshot(ProviderStatus::Unavailable));
        return;
    }
    let connection = match Connection::session() {
        Ok(connection) => connection,
        Err(_) => {
            let _ = bus.update_snapshot(state.snapshot(ProviderStatus::Unavailable));
            return;
        }
    };
    let signal_rx = subscribe_signals(&connection);
    let mut refresh = true;
    while !stop.load(Ordering::Relaxed) {
        while let Ok(command) = receiver.try_recv() {
            if let Err(error) = execute(&connection, &mut state, command) {
                eprintln!(
                    "{{\"provider\":\"media\",\"event\":\"action_failed\",\"error\":{}}}",
                    json!(error.to_string())
                );
            }
            refresh = true;
        }
        if signal_rx
            .as_ref()
            .map(|rx| rx.try_recv().is_ok())
            .unwrap_or(true)
        {
            refresh = true;
        }
        if refresh {
            match read_players(&connection, &mut state, &cache) {
                Ok(()) => {
                    publish(&bus, &state, "state_changed");
                }
                Err(_) => {
                    state.players.clear();
                    state.active = None;
                    let _ = bus.update_snapshot(state.snapshot(ProviderStatus::Unavailable));
                }
            }
            refresh = false;
        } else {
            thread::sleep(Duration::from_millis(50));
        }
    }
}

fn publish(bus: &EventBus, state: &MediaState, event_type: &str) {
    let snapshot = state.snapshot(if state.players.is_empty() {
        ProviderStatus::Unavailable
    } else {
        ProviderStatus::Available
    });
    let _ = bus.publish(MediaEvent {
        event_type: event_type.into(),
        data: snapshot.data.clone(),
        snapshot,
    });
}

struct MediaEvent {
    event_type: String,
    data: BTreeMap<String, Value>,
    snapshot: ProviderState,
}
impl ProviderEvent for MediaEvent {
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

fn subscribe_signals(connection: &Connection) -> Option<mpsc::Receiver<()>> {
    let (tx, rx) = mpsc::channel();
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .build();
    let connection = connection.clone();
    thread::spawn(move || {
        let Ok(mut messages) = MessageIterator::for_match_rule(rule, &connection, Some(128)) else {
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

fn dbus_proxy<'a>(connection: &'a Connection) -> zbus::Result<Proxy<'a>> {
    Proxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE)
}

fn player_proxy<'a>(connection: &'a Connection, name: &'a str) -> zbus::Result<Proxy<'a>> {
    Proxy::new(connection, name, PLAYER_PATH, PLAYER_INTERFACE)
}

fn read_players(
    connection: &Connection,
    state: &mut MediaState,
    cache: &ArtworkCacheConfig,
) -> zbus::Result<()> {
    let names: Vec<String> = dbus_proxy(connection)?.call("ListNames", &())?;
    let names: Vec<_> = names
        .into_iter()
        .filter(|name| name.starts_with("org.mpris.MediaPlayer2."))
        .collect();
    let mut players = BTreeMap::new();
    for dbus_name in names {
        let player_name = short_name(&dbus_name);
        if let Ok(player) = read_player(
            connection,
            &dbus_name,
            &player_name,
            state.players.get(&player_name),
            cache,
        ) {
            players.insert(player_name, player);
        }
    }
    state.players = players;
    let choices: Vec<_> = state.players.values().map(PlayerState::choice).collect();
    state.active = select_active_player(&choices, state.pinned.as_deref(), &state.default_player);
    Ok(())
}

fn read_player(
    connection: &Connection,
    dbus_name: &str,
    name: &str,
    previous: Option<&PlayerState>,
    cache: &ArtworkCacheConfig,
) -> zbus::Result<PlayerState> {
    let player = player_proxy(connection, dbus_name)?;
    let metadata: HashMap<String, OwnedValue> = player.get_property("Metadata").unwrap_or_default();
    let status: String = player
        .get_property("PlaybackStatus")
        .unwrap_or_else(|_| "Stopped".into());
    let artwork_url = string_value(metadata.get("mpris:artUrl"));
    let artwork_cache = artwork_url
        .as_deref()
        .and_then(|url| cache_artwork(url, cache).ok().flatten());
    let now = unix_now();
    let position_us = player
        .get_property::<i64>("Position")
        .ok()
        .or_else(|| previous.and_then(|p| p.position_us));
    Ok(PlayerState {
        name: name.into(),
        identity: player.get_property("Identity").unwrap_or_default(),
        desktop_entry: player.get_property("DesktopEntry").unwrap_or_default(),
        status: status.clone(),
        title: string_value(metadata.get("xesam:title")),
        artist: string_list(metadata.get("xesam:artist")),
        album: string_value(metadata.get("xesam:album")),
        artwork_url,
        artwork_cache,
        position_us,
        position_updated_at: if position_us != previous.and_then(|p| p.position_us) {
            now
        } else {
            previous.map(|p| p.position_updated_at).unwrap_or(now)
        },
        duration_us: integer_value(metadata.get("mpris:length")),
        volume: player.get_property("Volume").ok(),
        shuffle: player.get_property("Shuffle").ok(),
        repeat: player.get_property("LoopStatus").ok(),
        can_seek: player.get_property("CanSeek").unwrap_or(false),
        can_control: player.get_property("CanControl").unwrap_or(false),
        last_interaction: if status == "Playing" {
            now
        } else {
            previous.map(|p| p.last_interaction).unwrap_or(now)
        },
    })
}

fn execute(
    connection: &Connection,
    state: &mut MediaState,
    command: CommandRequest,
) -> io::Result<()> {
    let player_name = match &command {
        CommandRequest::SelectPlayer { player } => {
            state.pinned = Some(player.clone());
            player.clone()
        }
        _ => state
            .active
            .clone()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no active media player"))?,
    };
    let dbus_name = if player_name.starts_with("org.mpris.MediaPlayer2.") {
        player_name.clone()
    } else {
        format!("org.mpris.MediaPlayer2.{player_name}")
    };
    let proxy = player_proxy(connection, &dbus_name).map_err(io::Error::other)?;
    let method = match command {
        CommandRequest::Play => "Play",
        CommandRequest::Pause => "Pause",
        CommandRequest::PlayPause => "PlayPause",
        CommandRequest::Previous => "Previous",
        CommandRequest::Next => "Next",
        CommandRequest::Seek { offset_us } => {
            proxy
                .call_method("Seek", &(offset_us,))
                .map_err(io::Error::other)?;
            return Ok(());
        }
        CommandRequest::SelectPlayer { .. } => return Ok(()),
    };
    proxy.call_method(method, &()).map_err(io::Error::other)?;
    if let Some(player) = state.players.get_mut(&player_name) {
        player.last_interaction = unix_now();
        state.active = Some(player_name);
    }
    Ok(())
}

fn string_value(value: Option<&OwnedValue>) -> Option<String> {
    value.and_then(|v| v.downcast_ref::<String>().ok())
}
fn string_list(value: Option<&OwnedValue>) -> Vec<String> {
    value
        .and_then(|v| v.downcast_ref::<Array>().ok())
        .map(|values| {
            values
                .inner()
                .iter()
                .filter_map(|v| v.downcast_ref::<String>().ok())
                .collect()
        })
        .unwrap_or_default()
}
fn integer_value(value: Option<&OwnedValue>) -> Option<i64> {
    value.and_then(|v| v.downcast_ref::<i64>().ok())
}
fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}
fn short_name(name: &str) -> String {
    name.strip_prefix("org.mpris.MediaPlayer2.")
        .unwrap_or(name)
        .to_owned()
}

fn cache_artwork(url: &str, config: &ArtworkCacheConfig) -> io::Result<Option<String>> {
    if !config.enabled || !(url.starts_with("http://") || url.starts_with("https://")) {
        return Ok(None);
    }
    fs::create_dir_all(&config.directory)?;
    let key = format!("{:x}", md5::compute(url.as_bytes()));
    let target = config.directory.join(key);
    if let Ok(metadata) = fs::metadata(&target) {
        if metadata
            .modified()
            .ok()
            .and_then(|t| t.elapsed().ok())
            .map(|age| age <= config.ttl)
            .unwrap_or(false)
        {
            return Ok(Some(target.display().to_string()));
        }
    }
    let response = ureq::get(url)
        .timeout(Duration::from_secs(10))
        .call()
        .map_err(io::Error::other)?;
    let mut bytes = Vec::new();
    response
        .into_reader()
        .take(config.max_bytes.saturating_add(1))
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > config.max_bytes {
        return Ok(None);
    }
    enforce_cache_limit(
        &config.directory,
        config.max_bytes,
        bytes.len() as u64,
        &target,
    )?;
    let temporary = target.with_extension("tmp");
    fs::write(&temporary, bytes)?;
    fs::rename(&temporary, &target)?;
    Ok(Some(target.display().to_string()))
}

fn enforce_cache_limit(
    directory: &Path,
    max_bytes: u64,
    incoming: u64,
    target: &Path,
) -> io::Result<()> {
    let mut files = fs::read_dir(directory)?
        .filter_map(Result::ok)
        .filter(|entry| entry.path().is_file() && entry.path() != target)
        .filter_map(|entry| {
            entry
                .metadata()
                .ok()
                .map(|metadata| (entry.path(), metadata))
        })
        .collect::<Vec<_>>();
    let mut total = files
        .iter()
        .map(|(_, metadata)| metadata.len())
        .sum::<u64>();
    files.sort_by_key(|(_, metadata)| metadata.modified().ok());
    while total.saturating_add(incoming) > max_bytes {
        let Some((path, metadata)) = files.first().cloned() else {
            break;
        };
        files.remove(0);
        total = total.saturating_sub(metadata.len());
        let _ = fs::remove_file(path);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn player(name: &str, status: &str, interaction: u64) -> PlayerChoice {
        PlayerChoice {
            name: name.into(),
            status: status.into(),
            last_interaction: interaction,
            usable: true,
        }
    }

    #[test]
    fn playing_player_wins_over_default() {
        let players = vec![player("spotify", "Paused", 10), player("vlc", "Playing", 1)];
        assert_eq!(
            select_active_player(&players, None, "spotify"),
            Some("vlc".into())
        );
    }

    #[test]
    fn pinned_player_wins_until_unusable() {
        let players = vec![
            player("spotify", "Paused", 10),
            player("vlc", "Playing", 20),
        ];
        assert_eq!(
            select_active_player(&players, Some("spotify"), "vlc"),
            Some("spotify".into())
        );
        let mut unavailable = players.clone();
        unavailable[0].usable = false;
        assert_eq!(
            select_active_player(&unavailable, Some("spotify"), "vlc"),
            Some("vlc".into())
        );
    }

    #[test]
    fn default_and_recent_interaction_are_fallbacks() {
        let players = vec![player("spotify", "Paused", 1), player("vlc", "Paused", 2)];
        assert_eq!(
            select_active_player(&players, None, "spotify"),
            Some("spotify".into())
        );
        assert_eq!(
            select_active_player(&players, None, "missing"),
            Some("vlc".into())
        );
    }
}
