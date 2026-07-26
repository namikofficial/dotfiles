use std::collections::HashSet;
use std::path::{Path, PathBuf};
use toml::Table;
use toml::Value;

use crate::{Config, ConfigError, ConfigPaths, CURRENT_SCHEMA_VERSION};

// ---------------------------------------------------------------------------
// ConfigLoader
// ---------------------------------------------------------------------------

/// Builds and loads the resolved `Config` from TOML files and environment.
///
/// Loading order (later values override earlier ones):
/// 1. Code defaults
/// 2. `config.toml` in the config directory
/// 3. Named profile chain under `profiles/{name}.toml`
/// 4. `config.local.toml` (machine-local overrides – highest file priority)
/// 5. Runtime paths from environment variables (never from TOML)
pub struct ConfigLoader {
    config_dir: Option<PathBuf>,
    profile_override: Option<String>,
}

impl Default for ConfigLoader {
    fn default() -> Self {
        Self::new()
    }
}

impl ConfigLoader {
    pub fn new() -> Self {
        Self {
            config_dir: None,
            profile_override: None,
        }
    }

    /// Override the configuration directory (default: `$XDG_CONFIG_HOME/noxflow`).
    pub fn with_config_dir(mut self, dir: PathBuf) -> Self {
        self.config_dir = Some(dir);
        self
    }

    /// Override the active profile name (takes precedence over the `profile`
    /// field in `config.toml`).  Callers that want `$NOXFLOW_PROFILE`
    /// support can read that variable and pass it here.
    pub fn with_profile(mut self, profile: String) -> Self {
        self.profile_override = Some(profile);
        self
    }

    /// Load, merge, and validate the full configuration.
    pub fn load(&self) -> Result<Config, Vec<ConfigError>> {
        let config_dir = self
            .config_dir
            .clone()
            .unwrap_or_else(resolve_config_dir);

        // Accumulator – tables override in merge order.
        // Start empty; `toml::Value::try_into` will fill defaults for missing keys.
        let mut merged = Table::new();

        // 1. Base config
        let base_path = config_dir.join("config.toml");
        if base_path.exists() {
            let table = load_toml_file(&base_path).map_err(|e| vec![e])?;
            merge_tables(&mut merged, table);
        }

        // 2. Determine active profile
        //    `with_profile()` takes precedence over the file-level `profile` key.
        let active_profile: Option<String> = self
            .profile_override
            .clone()
            .or_else(|| {
                merged
                    .get("profile")
                    .and_then(|v| v.as_str())
                    .map(String::from)
            });

        // 3. Resolve and merge profile chain
        if let Some(ref profile_name) = active_profile {
            let chain = resolve_profile_chain(&config_dir, profile_name)?;
            for profile_table in chain {
                merge_tables(&mut merged, profile_table);
            }
        }

        // 4. Machine-local overrides (gitignored) – highest TOML priority
        let local_path = config_dir.join("config.local.toml");
        if local_path.exists() {
            let table = load_toml_file(&local_path).map_err(|e| vec![e])?;
            merge_tables(&mut merged, table);
        }

        // 5. Deserialize merged tables into Config
        let toml_value = Value::Table(merged);
        let mut config: Config = toml_value
            .try_into()
            .map_err(|e| {
                vec![ConfigError::Other(format!(
                    "failed to deserialize configuration: {e}"
                ))]
            })?;

        // 6. Set runtime paths from environment (never from TOML)
        config.runtime = resolve_runtime_paths(&config_dir);

        // 7. Validate
        if let Err(errors) = config.validate() {
            return Err(errors);
        }

        Ok(config)
    }
}

// ---------------------------------------------------------------------------
// Public helper functions
// ---------------------------------------------------------------------------

/// Resolve the configuration directory from environment or home.
pub fn resolve_config_dir() -> PathBuf {
    let home = home_dir();
    std::env::var_os("NOXFLOW_CONFIG_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .map(|p| p.join("noxflow"))
        })
        .unwrap_or_else(|| home.join(".config").join("noxflow"))
}

/// Quick socket path for CLI use without loading the full config.
pub fn default_socket_path() -> PathBuf {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    runtime.join("noxflow").join("noxd.sock")
}

/// Returns a default `Config` with environment-resolved paths.
pub fn default_config() -> Config {
    let mut cfg = Config::default();
    cfg.schema_version = CURRENT_SCHEMA_VERSION;
    cfg.runtime = resolve_runtime_paths(&resolve_config_dir());
    cfg
}

/// Read `NOXFLOW_PROFILE` from the environment, if set.
pub fn env_profile_override() -> Option<String> {
    std::env::var("NOXFLOW_PROFILE").ok()
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn resolve_runtime_paths(config_dir: &Path) -> ConfigPaths {
    let home = home_dir();
    let runtime_dir = xdg_or("XDG_RUNTIME_DIR", || PathBuf::from("/tmp"));
    let state_dir =
        xdg_or("XDG_STATE_HOME", || home.join(".local").join("state"))
            .join("noxflow");
    let cache_dir =
        xdg_or("XDG_CACHE_HOME", || home.join(".cache")).join("noxflow");
    let socket_path = runtime_dir.join("noxflow").join("noxd.sock");
    ConfigPaths {
        config_dir: config_dir.to_owned(),
        runtime_dir,
        state_dir,
        cache_dir,
        socket_path,
    }
}

fn xdg_or(name: &str, fallback: impl FnOnce() -> PathBuf) -> PathBuf {
    std::env::var_os(name)
        .map(PathBuf::from)
        .unwrap_or_else(fallback)
}

fn load_toml_file(path: &Path) -> Result<Table, ConfigError> {
    let content = std::fs::read_to_string(path).map_err(|e| ConfigError::Io {
        path: path.to_owned(),
        source: e,
    })?;
    content
        .parse::<Table>()
        .map_err(|e| ConfigError::Parse {
            path: path.to_owned(),
            source: e,
        })
}

fn merge_tables(base: &mut Table, overlay: Table) {
    for (key, val) in overlay {
        if let Some(existing) = base.get_mut(&key) {
            merge_values(existing, val);
        } else {
            base.insert(key, val);
        }
    }
}

fn merge_values(base: &mut Value, overlay: Value) {
    match (base, overlay) {
        (Value::Table(base_t), Value::Table(overlay_t)) => {
            for (key, val) in overlay_t {
                if let Some(existing) = base_t.get_mut(&key) {
                    merge_values(existing, val);
                } else {
                    base_t.insert(key, val);
                }
            }
        }
        (base, overlay) => *base = overlay,
    }
}

/// Resolve a profile chain, returning tables in leaf-overrides-root order.
fn resolve_profile_chain(
    config_dir: &Path,
    profile_name: &str,
) -> Result<Vec<Table>, Vec<ConfigError>> {
    let profiles_dir = config_dir.join("profiles");
    let mut chain: Vec<Table> = Vec::new();
    let mut visited: HashSet<String> = HashSet::new();
    let mut current = profile_name.to_string();

    loop {
        if !visited.insert(current.clone()) {
            let chain_names: Vec<String> = visited.iter().cloned().collect();
            return Err(vec![ConfigError::CircularInheritance {
                name: current,
                chain: chain_names,
            }]);
        }

        let path = profiles_dir.join(format!("{current}.toml"));
        if !path.exists() {
            return Err(vec![ConfigError::ProfileNotFound {
                name: current,
                path,
            }]);
        }

        let table = load_toml_file(&path).map_err(|e| vec![e])?;
        let extends = table
            .get("extends")
            .and_then(|v| v.as_str())
            .map(String::from);

        chain.push(table);

        match extends {
            Some(parent) => current = parent,
            None => break,
        }
    }

    // Reverse so root is first, leaf overrides root.
    chain.reverse();
    Ok(chain)
}
