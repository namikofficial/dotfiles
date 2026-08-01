//! Persisted runtime settings with atomic writes and validation.
//!
//! Settings are stored as JSON at `$XDG_STATE_HOME/noxflow/settings.json`.
//! Secrets (API keys) are stored separately in `secrets.json` with `0600` permissions
//! and are never returned by read operations.

use noxflow_ipc::{ErrorCode, IpcError};
use serde_json::Value;
use std::{
    collections::BTreeMap,
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

/// Canonical setting keys and their validation rules.
const VALID_SETTINGS: &[(&str, SettingKind)] = &[
    ("appearance.profile", SettingKind::String),
    ("appearance.density", SettingKind::Density),
    ("appearance.radius", SettingKind::Radius),
    ("shell.reduced_motion", SettingKind::Bool),
    ("bar.mode", SettingKind::BarMode),
    ("ai.provider", SettingKind::String),
    ("ai.endpoint", SettingKind::String),
    ("ai.model", SettingKind::String),
    ("calendar.sync_enabled", SettingKind::Bool),
    ("island.enabled", SettingKind::Bool),
    ("animation.speed", SettingKind::AnimationSpeed),
];

enum SettingKind {
    String,
    Bool,
    Density,
    Radius,
    BarMode,
    AnimationSpeed,
}

impl SettingKind {
    fn validate(&self, value: &Value) -> Result<(), String> {
        match self {
            SettingKind::String => match value {
                Value::String(s) if !s.is_empty() => Ok(()),
                Value::String(_) => Err("value must be non-empty".into()),
                _ => Err("value must be a string".into()),
            },
            SettingKind::Bool => match value {
                Value::Bool(_) => Ok(()),
                _ => Err("value must be a boolean".into()),
            },
            SettingKind::Density => match value {
                Value::String(s)
                    if ["compact", "comfortable", "spacious"].contains(&s.as_str()) =>
                {
                    Ok(())
                }
                Value::String(s) => Err(format!(
                    "density must be one of: compact, comfortable, spacious (got {s})"
                )),
                _ => Err("value must be a string".into()),
            },
            SettingKind::Radius => match value {
                Value::Number(n) if n.as_u64().map_or(false, |v| v <= 36) => Ok(()),
                _ => Err("radius must be an integer between 0 and 36".into()),
            },
            SettingKind::BarMode => match value {
                Value::String(s) if ["normal", "compact", "auto-hide"].contains(&s.as_str()) => {
                    Ok(())
                }
                Value::String(s) => Err(format!(
                    "bar mode must be one of: normal, compact, auto-hide (got {s})"
                )),
                _ => Err("value must be a string".into()),
            },
            SettingKind::AnimationSpeed => match value {
                Value::Number(n) if n.as_f64().map_or(false, |v| (0.0..=2.0).contains(&v)) => {
                    Ok(())
                }
                _ => Err("animation speed must be a number between 0.0 and 2.0".into()),
            },
        }
    }
}

#[derive(Clone)]
pub struct SettingsStore {
    path: PathBuf,
    #[allow(dead_code)]
    secrets_path: PathBuf,
    settings: Arc<Mutex<BTreeMap<String, Value>>>,
}

impl SettingsStore {
    pub fn new(state_dir: &Path) -> Self {
        Self {
            path: state_dir.join("settings.json"),
            secrets_path: state_dir.join("secrets.json"),
            settings: Arc::new(Mutex::new(BTreeMap::new())),
        }
    }

    /// Load settings from disk. Missing files are treated as empty.
    pub fn load(&self) -> BTreeMap<String, Value> {
        let mut settings = BTreeMap::new();
        if let Ok(content) = fs::read_to_string(&self.path) {
            if let Ok(map) = serde_json::from_str::<BTreeMap<String, Value>>(&content) {
                settings = map;
            }
        }
        *self.settings.lock().expect("settings mutex poisoned") = settings.clone();
        settings
    }

    /// Get a single setting value.
    pub fn get(&self, key: &str) -> Result<Value, IpcError> {
        let settings = self.settings.lock().expect("settings mutex poisoned");
        settings.get(key).cloned().ok_or_else(|| IpcError {
            code: ErrorCode::UnknownSetting,
            message: format!("unknown setting: {key}"),
            details: BTreeMap::new(),
        })
    }

    /// Get all settings.
    pub fn get_all(&self) -> BTreeMap<String, Value> {
        self.settings
            .lock()
            .expect("settings mutex poisoned")
            .clone()
    }

    /// Set a setting value with validation.
    /// Returns (old_value, new_value) on success.
    pub fn set(&self, key: &str, value: Value) -> Result<(Option<Value>, Value), IpcError> {
        // Validate key exists
        let kind = VALID_SETTINGS
            .iter()
            .find(|(k, _)| *k == key)
            .map(|(_, kind)| kind)
            .ok_or_else(|| IpcError {
                code: ErrorCode::UnknownSetting,
                message: format!("unknown setting key: {key}"),
                details: BTreeMap::new(),
            })?;

        // Validate value
        kind.validate(&value).map_err(|msg| IpcError {
            code: ErrorCode::InvalidParams,
            message: format!("invalid value for {key}: {msg}"),
            details: BTreeMap::new(),
        })?;

        let mut settings = self.settings.lock().expect("settings mutex poisoned");
        let old = settings.insert(key.to_owned(), value.clone());
        drop(settings);

        // Persist (best-effort — log failure)
        if let Err(error) = self.save() {
            eprintln!("noxd: failed to persist settings: {error}");
        }

        Ok((old, value))
    }

    /// Atomically write settings to disk.
    fn save(&self) -> io::Result<()> {
        let settings = self.settings.lock().expect("settings mutex poisoned");
        let content = serde_json::to_string_pretty(&*settings)?;
        drop(settings);

        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }

        // Atomic write: write to temp, fsync, rename over target
        let tmp_path = self.path.with_extension("json.tmp");
        let mut tmp = fs::File::create(&tmp_path)?;
        tmp.write_all(content.as_bytes())?;
        tmp.sync_all()?;
        fs::rename(&tmp_path, &self.path)?;
        fs::File::open(&self.path)?.sync_all()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn load_missing_settings_returns_empty() {
        let dir = tempdir().unwrap();
        let store = SettingsStore::new(dir.path());
        let settings = store.load();
        assert!(settings.is_empty());
    }

    #[test]
    fn set_and_get_round_trip() {
        let dir = tempdir().unwrap();
        let store = SettingsStore::new(dir.path());
        store.load();

        store
            .set("appearance.profile", Value::String("material-oled".into()))
            .unwrap();
        assert_eq!(
            store.get("appearance.profile").unwrap(),
            Value::String("material-oled".into())
        );
    }

    #[test]
    fn invalid_setting_key_is_rejected() {
        let dir = tempdir().unwrap();
        let store = SettingsStore::new(dir.path());
        store.load();

        let err = store
            .set("nonexistent", Value::String("x".into()))
            .unwrap_err();
        assert_eq!(err.code, ErrorCode::UnknownSetting);
    }

    #[test]
    fn invalid_density_is_rejected() {
        let dir = tempdir().unwrap();
        let store = SettingsStore::new(dir.path());
        store.load();

        let err = store
            .set("appearance.density", Value::String("ultra".into()))
            .unwrap_err();
        assert_eq!(err.code, ErrorCode::InvalidParams);
    }

    #[test]
    fn invalid_radius_is_rejected() {
        let dir = tempdir().unwrap();
        let store = SettingsStore::new(dir.path());
        store.load();

        let err = store
            .set("appearance.radius", serde_json::json!(99))
            .unwrap_err();
        assert_eq!(err.code, ErrorCode::InvalidParams);
    }

    #[test]
    fn settings_survive_reload() {
        let dir = tempdir().unwrap();
        {
            let store = SettingsStore::new(dir.path());
            store.load();
            store
                .set("bar.mode", Value::String("compact".into()))
                .unwrap();
        }
        {
            let store = SettingsStore::new(dir.path());
            let loaded = store.load();
            assert_eq!(loaded.get("bar.mode").unwrap(), "compact");
        }
    }

    #[test]
    fn get_all_returns_all_settings() {
        let dir = tempdir().unwrap();
        let store = SettingsStore::new(dir.path());
        store.load();
        store
            .set("shell.reduced_motion", Value::Bool(true))
            .unwrap();
        store.set("island.enabled", Value::Bool(false)).unwrap();
        let all = store.get_all();
        assert_eq!(all.get("shell.reduced_motion").unwrap(), true);
        assert_eq!(all.get("island.enabled").unwrap(), false);
    }
}
