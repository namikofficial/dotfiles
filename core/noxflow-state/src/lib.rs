//! Versioned, user-private persistent state for NoxFlow.

use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

pub const CURRENT_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct ProviderHealth {
    pub status: String,
    pub failures: u64,
    pub last_error: Option<String>,
}

impl Default for ProviderHealth {
    fn default() -> Self {
        Self {
            status: "unknown".into(),
            failures: 0,
            last_error: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct PersistentState {
    pub schema_version: u32,
    pub active_appearance_profile: Option<String>,
    pub last_working_shell: Option<String>,
    pub last_successful_daemon_version: Option<String>,
    pub dnd_enabled: bool,
    pub preferred_audio_output_id: Option<String>,
    pub last_selected_monitor_profile: Option<String>,
    pub provider_health_summary: BTreeMap<String, ProviderHealth>,
    pub crash_counters: BTreeMap<String, u64>,
    pub last_fallback_reason: Option<String>,
}

impl Default for PersistentState {
    fn default() -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            active_appearance_profile: None,
            last_working_shell: None,
            last_successful_daemon_version: None,
            dnd_enabled: false,
            preferred_audio_output_id: None,
            last_selected_monitor_profile: None,
            provider_health_summary: BTreeMap::new(),
            crash_counters: BTreeMap::new(),
            last_fallback_reason: None,
        }
    }
}

#[derive(Debug)]
pub enum StateError {
    Io(io::Error),
    InvalidToml(String),
    UnsupportedSchema(u32),
    Serialize(String),
}

impl std::fmt::Display for StateError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(f, "state I/O error: {error}"),
            Self::InvalidToml(error) => write!(f, "invalid state TOML: {error}"),
            Self::UnsupportedSchema(version) => {
                write!(f, "unsupported state schema version: {version}")
            }
            Self::Serialize(error) => write!(f, "could not serialize state: {error}"),
        }
    }
}

impl std::error::Error for StateError {}
impl From<io::Error> for StateError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LoadInfo {
    pub recovered: bool,
    pub migrated: bool,
}

#[derive(Debug)]
pub struct StateStore {
    path: PathBuf,
    state: PersistentState,
    dirty: bool,
    recovered: bool,
}

impl StateStore {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            state: PersistentState::default(),
            dirty: false,
            recovered: false,
        }
    }

    pub fn load(path: impl Into<PathBuf>) -> Result<(Self, LoadInfo), StateError> {
        let path = path.into();
        let mut store = Self::new(path.clone());
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Ok((
                    store,
                    LoadInfo {
                        recovered: false,
                        migrated: false,
                    },
                ));
            }
            Err(error) => return Err(error.into()),
        };

        let text = match std::str::from_utf8(&bytes) {
            Ok(text) => text,
            Err(_) => {
                quarantine(&path)?;
                store.recovered = true;
                store.dirty = true;
                return Ok((
                    store,
                    LoadInfo {
                        recovered: true,
                        migrated: false,
                    },
                ));
            }
        };
        let value: toml::Value = match toml::from_str(text) {
            Ok(value) => value,
            Err(_error) => {
                quarantine(&path)?;
                store.recovered = true;
                store.dirty = true;
                return Ok((
                    store,
                    LoadInfo {
                        recovered: true,
                        migrated: false,
                    },
                ));
            }
        };
        let version = value
            .get("schema_version")
            .and_then(toml::Value::as_integer)
            .unwrap_or(0) as u32;
        if version > CURRENT_SCHEMA_VERSION {
            quarantine(&path)?;
            store.recovered = true;
            store.dirty = true;
            return Ok((
                store,
                LoadInfo {
                    recovered: true,
                    migrated: false,
                },
            ));
        }
        let migrated = version < CURRENT_SCHEMA_VERSION;
        store.state = match value.try_into() {
            Ok(state) => state,
            Err(_error) => {
                quarantine(&path)?;
                store.recovered = true;
                store.dirty = true;
                return Ok((
                    store,
                    LoadInfo {
                        recovered: true,
                        migrated: false,
                    },
                ));
            }
        };
        store.state.schema_version = CURRENT_SCHEMA_VERSION;
        store.dirty = migrated;
        Ok((
            store,
            LoadInfo {
                recovered: false,
                migrated,
            },
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn state(&self) -> &PersistentState {
        &self.state
    }
    pub fn state_mut(&mut self) -> &mut PersistentState {
        self.dirty = true;
        &mut self.state
    }
    pub fn is_dirty(&self) -> bool {
        self.dirty
    }
    pub fn was_recovered(&self) -> bool {
        self.recovered
    }

    pub fn save(&mut self) -> Result<(), StateError> {
        let parent = self.path.parent().ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "state path has no parent")
        })?;
        fs::create_dir_all(parent)?;
        set_private_dir(parent)?;
        self.state.schema_version = CURRENT_SCHEMA_VERSION;
        let contents = toml::to_string_pretty(&self.state)
            .map_err(|error| StateError::Serialize(error.to_string()))?;
        let temp = temporary_path(&self.path);
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temp)?;
            set_private_file(&file)?;
            std::io::Write::write_all(&mut file, contents.as_bytes())?;
            file.sync_all()?;
            fs::rename(&temp, &self.path)?;
            set_private_file(&File::open(&self.path)?)?;
            File::open(parent)?.sync_all()?;
            Ok::<(), io::Error>(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result.map_err(StateError::Io)?;
        self.dirty = false;
        Ok(())
    }
}

fn temporary_path(path: &Path) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    path.with_file_name(format!(
        ".{}.tmp-{}-{}",
        path.file_name().unwrap_or_default().to_string_lossy(),
        std::process::id(),
        nonce
    ))
}

fn quarantine(path: &Path) -> io::Result<()> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let mut candidate = path.with_file_name(format!(
        "{}.corrupt-{}",
        path.file_name().unwrap_or_default().to_string_lossy(),
        stamp
    ));
    let mut suffix = 0;
    while candidate.exists() {
        suffix += 1;
        candidate = path.with_file_name(format!(
            "{}.corrupt-{}-{suffix}",
            path.file_name().unwrap_or_default().to_string_lossy(),
            stamp
        ));
    }
    fs::rename(path, candidate)
}

fn set_private_dir(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}

fn set_private_file(file: &File) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}

pub fn default_state_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".local/state"))
        .join("noxflow/state.toml")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp() -> PathBuf {
        std::env::temp_dir().join(format!(
            "noxflow-state-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    #[test]
    fn first_run_and_missing_directory() {
        let path = temp().join("nested/state.toml");
        let (mut store, info) = StateStore::load(&path).unwrap();
        assert_eq!(store.state(), &PersistentState::default());
        assert!(!info.recovered);
        store.state_mut().last_working_shell = Some("noxflow".into());
        store.save().unwrap();
        assert!(path.exists());
        let _ = fs::remove_dir_all(path.parent().unwrap().parent().unwrap());
    }

    #[test]
    fn atomic_replacement_leaves_only_final_file() {
        let dir = temp();
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.toml");
        let (mut store, _) = StateStore::load(&path).unwrap();
        store.save().unwrap();
        store.state_mut().dnd_enabled = true;
        store.save().unwrap();
        assert!(fs::read_to_string(&path)
            .unwrap()
            .contains("dnd_enabled = true"));
        assert_eq!(fs::read_dir(dir).unwrap().count(), 1);
        let _ = fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn invalid_toml_is_quarantined_and_reset() {
        let dir = temp();
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.toml");
        fs::write(&path, "not = [valid").unwrap();
        let (store, info) = StateStore::load(&path).unwrap();
        assert!(info.recovered && store.was_recovered() && !path.exists());
        assert_eq!(fs::read_dir(dir).unwrap().count(), 1);
        let _ = fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn schema_zero_is_migrated() {
        let dir = temp();
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.toml");
        fs::write(&path, "schema_version = 0\nlast_working_shell = 'wayle'\n").unwrap();
        let (store, info) = StateStore::load(&path).unwrap();
        assert!(info.migrated && store.is_dirty());
        assert_eq!(store.state().schema_version, 1);
        assert_eq!(store.state().last_working_shell.as_deref(), Some("wayle"));
        let _ = fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn unsupported_schema_is_quarantined_and_reset() {
        let dir = temp();
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.toml");
        fs::write(&path, "schema_version = 99\n").unwrap();
        let (store, info) = StateStore::load(&path).unwrap();
        assert!(info.recovered && store.was_recovered() && !path.exists());
        let _ = fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn write_failure_keeps_dirty_state() {
        let dir = temp();
        fs::create_dir_all(&dir).unwrap();
        let blocker = dir.join("blocker");
        fs::write(&blocker, "file").unwrap();
        let mut store = StateStore::new(blocker.join("state.toml"));
        store.state_mut().dnd_enabled = true;
        assert!(store.save().is_err() && store.is_dirty() && store.state().dnd_enabled);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn permission_failure_is_returned() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let dir = temp();
            fs::create_dir_all(&dir).unwrap();
            fs::set_permissions(&dir, fs::Permissions::from_mode(0o500)).unwrap();
            let path = dir.join("state.toml");
            let mut store = StateStore::new(path);
            store.state_mut().dnd_enabled = true;
            let result = store.save();
            if result.is_err() {
                assert!(
                    matches!(result, Err(StateError::Io(error)) if error.kind() == io::ErrorKind::PermissionDenied)
                );
            }
            fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
            let _ = fs::remove_dir_all(dir);
        }
    }

    #[test]
    fn private_permissions_are_applied() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let path = temp().join("state.toml");
            let (mut store, _) = StateStore::load(&path).unwrap();
            store.save().unwrap();
            assert_eq!(
                fs::metadata(path.parent().unwrap())
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o700
            );
            assert_eq!(
                fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
            let _ = fs::remove_dir_all(path.parent().unwrap());
        }
    }
}
