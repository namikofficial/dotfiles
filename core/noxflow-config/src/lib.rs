//! NoxFlow configuration loading, validation, and profile merging.
//!
//! Config files live under `$XDG_CONFIG_HOME/noxflow/` (default
//! `~/.config/noxflow/`). The loader discovers and merges:
//!
//! 1. **`config.toml`** – base user configuration
//! 2. **`config.local.toml`** – machine-local overrides (gitignored)
//! 3. **`profiles/{name}.toml`** – named profile chain (set via the `profile`
//!    key in `config.toml`, the `NOXFLOW_PROFILE` environment variable, or the
//!    `ConfigLoader::with_profile` builder)
//! 4. **Environment variables** – runtime paths (`XDG_RUNTIME_DIR`, etc.)

mod config;
mod error;
mod loader;
mod redact;

pub use config::*;
pub use error::ConfigError;
pub use loader::*;
pub use redact::display_config;
