//! Schema introspection.
//!
//! The daemon ignores keys it does not know, so a configuration file written
//! for a newer daemon still loads on an older one. That tolerance is right
//! for files the daemon did not write, but it also means a hand-written file
//! can carry keys that do nothing while reading as if they configure
//! something.
//!
//! These helpers answer the question "which keys in this file does the
//! schema not know?", by comparing the file against the schema itself.

use std::path::Path;

use toml::Table;
use toml::Value;

use crate::{AiConfig, Config, ConfigError};

/// Every key the schema understands, as dotted paths ("appearance.radius").
pub fn schema_keys() -> Vec<String> {
    // The two optional fields have to be filled in: TOML has no null, and
    // serialising a None would fail rather than omit the key.
    let probe = Config {
        profile: Some("schema-probe".to_string()),
        ai: AiConfig {
            api_key: Some("schema-probe".to_string()),
            ..AiConfig::default()
        },
        ..Config::default()
    };

    let value = toml::Value::try_from(&probe).expect("the default config is representable in TOML");
    let table = value.as_table().expect("a struct serialises to a table");
    let mut keys = Vec::new();
    collect_keys(table, "", &mut keys);
    keys
}

/// The keys in a table that the schema does not know.
pub fn unknown_keys(table: &Table) -> Vec<String> {
    let known = schema_keys();
    let mut present = Vec::new();
    collect_keys(table, "", &mut present);
    present
        .into_iter()
        .filter(|key| !known.iter().any(|known_key| known_key == key))
        .collect()
}

/// The keys in a TOML file that the schema does not know.
pub fn unknown_keys_in_file(path: &Path) -> Result<Vec<String>, ConfigError> {
    let content = std::fs::read_to_string(path).map_err(|e| ConfigError::Io {
        path: path.to_owned(),
        source: e,
    })?;
    let table = content.parse::<Table>().map_err(|e| ConfigError::Parse {
        path: path.to_owned(),
        source: e,
    })?;
    Ok(unknown_keys(&table))
}

fn collect_keys(table: &Table, prefix: &str, out: &mut Vec<String>) {
    for (key, value) in table {
        let path = if prefix.is_empty() {
            key.clone()
        } else {
            format!("{prefix}.{key}")
        };
        match value {
            Value::Table(inner) => {
                out.push(path.clone());
                collect_keys(inner, &path, out);
            }
            _ => out.push(path),
        }
    }
}
