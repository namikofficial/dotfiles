use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::ConfigError;

pub const CURRENT_SCHEMA_VERSION: u32 = 1;

// ---------------------------------------------------------------------------
// Runtime paths – always set from the environment, never from TOML files
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigPaths {
    pub config_dir: PathBuf,
    pub runtime_dir: PathBuf,
    pub state_dir: PathBuf,
    pub cache_dir: PathBuf,
    pub socket_path: PathBuf,
}

impl Default for ConfigPaths {
    fn default() -> Self {
        let home = home_dir();
        let config_dir = xdg_var("XDG_CONFIG_HOME")
            .unwrap_or_else(|| home.join(".config"))
            .join("noxflow");
        let runtime_dir = xdg_var("XDG_RUNTIME_DIR").unwrap_or_else(|| PathBuf::from("/tmp"));
        let state_dir = xdg_var("XDG_STATE_HOME")
            .unwrap_or_else(|| home.join(".local").join("state"))
            .join("noxflow");
        let cache_dir = xdg_var("XDG_CACHE_HOME")
            .unwrap_or_else(|| home.join(".cache"))
            .join("noxflow");
        let socket_path = runtime_dir.join("noxflow").join("noxd.sock");
        Self {
            config_dir,
            runtime_dir,
            state_dir,
            cache_dir,
            socket_path,
        }
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn xdg_var(name: &str) -> Option<PathBuf> {
    std::env::var_os(name).map(PathBuf::from)
}

// ---------------------------------------------------------------------------
// Top-level configuration model
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub schema_version: u32,
    /// Named configuration profile to load (e.g. "laptop", "focus").
    /// Corresponds to a file at `{config_dir}/profiles/{name}.toml`.
    pub profile: Option<String>,
    pub appearance: AppearanceConfig,
    pub shell: ShellConfig,
    pub providers: ProvidersConfig,
    pub notifications: NotificationsConfig,
    pub power: PowerConfig,
    pub network: NetworkConfig,
    pub media: MediaConfig,
    pub audio: AudioConfig,
    pub brightness: BrightnessConfig,
    pub developer: DeveloperConfig,
    pub ai: AiConfig,
    pub fallback: FallbackConfig,
    /// Runtime paths set from the environment. Never read from TOML.
    #[serde(skip)]
    pub runtime: ConfigPaths,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            profile: None,
            appearance: AppearanceConfig::default(),
            shell: ShellConfig::default(),
            providers: ProvidersConfig::default(),
            notifications: NotificationsConfig::default(),
            power: PowerConfig::default(),
            network: NetworkConfig::default(),
            media: MediaConfig::default(),
            audio: AudioConfig::default(),
            brightness: BrightnessConfig::default(),
            developer: DeveloperConfig::default(),
            ai: AiConfig::default(),
            fallback: FallbackConfig::default(),
            runtime: ConfigPaths::default(),
        }
    }
}

// ---------------------------------------------------------------------------
// Section structs
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AppearanceConfig {
    pub profile: String,
    pub density: String,
    pub radius: u8,
    pub mode: String,
    pub motion: String,
    pub transparency: String,
}

impl Default for AppearanceConfig {
    fn default() -> Self {
        Self {
            profile: "material-expressive".into(),
            density: "comfortable".into(),
            radius: 14,
            mode: "dark".into(),
            motion: "fluid".into(),
            transparency: "balanced".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ShellConfig {
    pub name: String,
    pub fallback: String,
    pub reduced_motion: bool,
}

impl Default for ShellConfig {
    fn default() -> Self {
        Self {
            name: "noxflow".into(),
            fallback: "wayle".into(),
            reduced_motion: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ProvidersConfig {
    pub audio: bool,
    pub network: bool,
    pub bluetooth: bool,
    pub battery: bool,
    pub media: bool,
    pub hyprland: bool,
    pub clipboard: bool,
}

impl Default for ProvidersConfig {
    fn default() -> Self {
        Self {
            audio: true,
            network: true,
            bluetooth: true,
            battery: true,
            media: true,
            hyprland: true,
            clipboard: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct NotificationsConfig {
    pub timeout: u64,
    pub max_history: usize,
    pub sounds_enabled: bool,
    pub dnd_enabled: bool,
    pub dnd_schedule_start: String,
    pub dnd_schedule_end: String,
}

impl Default for NotificationsConfig {
    fn default() -> Self {
        Self {
            timeout: 8,
            max_history: 100,
            sounds_enabled: false,
            dnd_enabled: false,
            dnd_schedule_start: "22:00".into(),
            dnd_schedule_end: "08:00".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct PowerConfig {
    pub profile: String,
    pub dim_display: u64,
    pub screen_off: u64,
    pub suspend: u64,
    pub hybrid_sleep: bool,
}

impl Default for PowerConfig {
    fn default() -> Self {
        Self {
            profile: "balanced".into(),
            dim_display: 300,
            screen_off: 600,
            suspend: 1800,
            hybrid_sleep: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct NetworkConfig {
    pub wifi_backend: String,
    pub vpn_autoconnect: bool,
    pub metered_connection: String,
    pub dns: String,
}

impl Default for NetworkConfig {
    fn default() -> Self {
        Self {
            wifi_backend: "iwd".into(),
            vpn_autoconnect: false,
            metered_connection: "detect".into(),
            dns: "system".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct MediaConfig {
    pub mpris_integration: bool,
    pub osd_enabled: bool,
    pub osd_timeout: u64,
    pub default_player: String,
    pub artwork_cache_enabled: bool,
    pub artwork_cache_dir: String,
    pub artwork_cache_max_bytes: u64,
    pub artwork_cache_ttl: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AudioConfig {
    pub max_volume: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct BrightnessConfig {
    pub minimum: u8,
    pub step: u8,
    pub external_backend: String,
}

impl Default for BrightnessConfig {
    fn default() -> Self {
        Self {
            minimum: 10,
            step: 5,
            external_backend: "none".into(),
        }
    }
}

impl Default for AudioConfig {
    fn default() -> Self {
        Self { max_volume: 100 }
    }
}

impl Default for MediaConfig {
    fn default() -> Self {
        Self {
            mpris_integration: true,
            osd_enabled: true,
            osd_timeout: 2,
            default_player: "spotify".into(),
            artwork_cache_enabled: false,
            artwork_cache_dir: String::new(),
            artwork_cache_max_bytes: 50 * 1024 * 1024,
            artwork_cache_ttl: 7 * 24 * 60 * 60,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct DeveloperConfig {
    pub editor: String,
    pub terminal: String,
    pub git_editor_integration: bool,
    pub project_path: String,
}

impl Default for DeveloperConfig {
    fn default() -> Self {
        Self {
            editor: "neovim".into(),
            terminal: "kitty".into(),
            git_editor_integration: true,
            project_path: "~/Documents/code".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AiConfig {
    pub enabled: bool,
    pub provider: String,
    pub endpoint: String,
    pub model: String,
    pub fallback_provider: String,
    pub temperature: f64,
    pub max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub api_key: Option<String>,
}

impl Default for AiConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            provider: "local".into(),
            endpoint: "http://127.0.0.1:8080/v1".into(),
            model: "qwen3-4b-local".into(),
            fallback_provider: "cerebras".into(),
            temperature: 0.7,
            max_tokens: 4096,
            api_key: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct FallbackConfig {
    pub shell: String,
    pub compositor: String,
    pub launcher: String,
    pub panel: String,
    pub term: String,
}

impl Default for FallbackConfig {
    fn default() -> Self {
        Self {
            shell: "wayle".into(),
            compositor: "hyprland".into(),
            launcher: "rofi".into(),
            panel: "wayle".into(),
            term: "kitty".into(),
        }
    }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

impl Config {
    pub fn validate(&self) -> Result<(), Vec<ConfigError>> {
        let mut errors: Vec<ConfigError> = Vec::new();

        // schema version
        if self.schema_version != CURRENT_SCHEMA_VERSION {
            errors.push(ConfigError::validation(
                "schema_version",
                format!(
                    "expected version {CURRENT_SCHEMA_VERSION}, got {}",
                    self.schema_version
                ),
            ));
        }

        // appearance
        let valid_densities = ["compact", "comfortable", "spacious"];
        if !valid_densities.contains(&self.appearance.density.as_str()) {
            errors.push(ConfigError::validation(
                "appearance.density",
                format!(
                    "unknown density '{}'; expected one of {:?}",
                    self.appearance.density, valid_densities
                ),
            ));
        }
        if self.appearance.radius > 36 {
            errors.push(ConfigError::validation(
                "appearance.radius",
                format!("value {} out of range 0–36", self.appearance.radius),
            ));
        }
        let valid_modes = ["dark", "light"];
        if !valid_modes.contains(&self.appearance.mode.as_str()) {
            errors.push(ConfigError::validation(
                "appearance.mode",
                format!(
                    "unknown mode '{}'; expected one of {:?}",
                    self.appearance.mode, valid_modes
                ),
            ));
        }

        // shell
        if self.shell.name.is_empty() {
            errors.push(ConfigError::validation("shell.name", "must not be empty"));
        }
        if self.shell.fallback.is_empty() {
            errors.push(ConfigError::validation(
                "shell.fallback",
                "must not be empty",
            ));
        }

        // notifications
        if self.notifications.timeout == 0 || self.notifications.timeout > 3600 {
            errors.push(ConfigError::validation(
                "notifications.timeout",
                format!("value {} out of range 1–3600", self.notifications.timeout),
            ));
        }

        // power
        let valid_power = ["performance", "balanced", "power-saver"];
        if !valid_power.contains(&self.power.profile.as_str()) {
            errors.push(ConfigError::validation(
                "power.profile",
                format!(
                    "unknown profile '{}'; expected one of {:?}",
                    self.power.profile, valid_power
                ),
            ));
        }

        if self.audio.max_volume == 0 {
            errors.push(ConfigError::validation(
                "audio.max_volume",
                "must be greater than zero",
            ));
        }

        if self.brightness.minimum > 100 {
            errors.push(ConfigError::validation(
                "brightness.minimum",
                format!("value {} out of range 0–100", self.brightness.minimum),
            ));
        }
        if self.brightness.step == 0 || self.brightness.step > 100 {
            errors.push(ConfigError::validation(
                "brightness.step",
                format!("value {} out of range 1–100", self.brightness.step),
            ));
        }
        if !["none", "ddcutil"].contains(&self.brightness.external_backend.as_str()) {
            errors.push(ConfigError::validation(
                "brightness.external_backend",
                "expected one of [none, ddcutil]",
            ));
        }

        // ai
        if !(0.0..=2.0).contains(&self.ai.temperature) {
            errors.push(ConfigError::validation(
                "ai.temperature",
                format!("value {} out of range 0.0–2.0", self.ai.temperature),
            ));
        }
        if self.ai.max_tokens == 0 || self.ai.max_tokens > 128_000 {
            errors.push(ConfigError::validation(
                "ai.max_tokens",
                format!("value {} out of range 1–128000", self.ai.max_tokens),
            ));
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }
}
