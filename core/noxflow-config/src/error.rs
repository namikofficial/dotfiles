use std::path::PathBuf;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("I/O error reading {path}: {source}")]
    Io {
        path: PathBuf,
        source: std::io::Error,
    },

    #[error("TOML parse error in {path}: {source}")]
    Parse {
        path: PathBuf,
        source: toml::de::Error,
    },

    #[error("validation error at `{path}`: {message}")]
    Validation { path: String, message: String },

    #[error("profile `{name}` not found (looked at {path})")]
    ProfileNotFound { name: String, path: PathBuf },

    #[error("circular profile inheritance: `{name}` appears twice in chain {chain:?}")]
    CircularInheritance { name: String, chain: Vec<String> },

    #[error("config error: {0}")]
    Other(String),
}

impl ConfigError {
    pub fn validation(path: impl Into<String>, message: impl Into<String>) -> Self {
        Self::Validation {
            path: path.into(),
            message: message.into(),
        }
    }
}
