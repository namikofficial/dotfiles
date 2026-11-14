//! The repository's configuration files must stay valid instances of the
//! schema they document.
//!
//! The daemon ignores unknown keys so that a newer file still loads on an
//! older daemon (see `unknown_fields_are_safely_ignored`). That tolerance
//! is for files the daemon did not write. The two files in this repository
//! are written by hand, and a key the schema does not know is dead weight:
//! it reads as if it configures something and does nothing.
//!
//! The contract this file pins down:
//!
//!   * every key in the file is a key the schema knows;
//!   * the file loads through the production loader, including the named
//!     profile chain and the daemon's own validation.

use std::fs;
use std::path::{Path, PathBuf};

use noxflow_config::{unknown_keys_in_file, ConfigLoader};

/// The files that describe the daemon's configuration.
fn repository_config_files() -> Vec<PathBuf> {
    let root = repo_root();
    vec![
        root.join("config").join("default.toml"),
        root.join("configs").join("noxflow").join("config.toml"),
    ]
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .canonicalize()
        .expect("the repository root exists")
}

/// Stage a configuration file the way the loader expects to find it: the
/// file itself, and the named profiles beside it.
fn staging_dir(config_file: &Path) -> PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(1);
    let id = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    let dir = std::env::temp_dir().join(format!("noxflow-repo-config-{nanos}-{id}"));
    fs::create_dir_all(&dir).unwrap();

    fs::copy(config_file, dir.join("config.toml")).unwrap();

    let profiles_src = repo_root().join("config").join("profiles");
    if profiles_src.is_dir() {
        let profiles_dst = dir.join("profiles");
        fs::create_dir_all(&profiles_dst).unwrap();
        for entry in fs::read_dir(&profiles_src).unwrap() {
            let entry = entry.unwrap();
            if entry.path().extension().is_some_and(|ext| ext == "toml") {
                fs::copy(entry.path(), profiles_dst.join(entry.file_name())).unwrap();
            }
        }
    }

    dir
}

#[test]
fn repository_config_files_use_only_schema_keys() {
    for file in repository_config_files() {
        let unknown = unknown_keys_in_file(&file).unwrap_or_else(|e| {
            panic!("{} could not be read: {e}", file.display());
        });
        assert!(
            unknown.is_empty(),
            "{} sets keys the schema does not know: {unknown:?}\n\
             A key the daemon ignores still reads as if it configures something.",
            file.display()
        );
    }
}

#[test]
fn repository_config_files_load_through_the_production_loader() {
    for file in repository_config_files() {
        let dir = staging_dir(&file);
        let loaded = ConfigLoader::new()
            .with_config_dir(dir.clone())
            .load()
            .unwrap_or_else(|errors| {
                panic!(
                    "{} does not load: {errors:?}\n\
                     The daemon would refuse this configuration.",
                    file.display()
                )
            });

        assert_eq!(loaded.schema_version, 1);
        assert!(!loaded.shell.name.is_empty());
        fs::remove_dir_all(&dir).ok();
    }
}
