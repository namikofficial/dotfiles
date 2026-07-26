use std::path::PathBuf;
use std::fs;

use noxflow_config::{ConfigLoader, ConfigError, display_config, env_profile_override};

fn fixture_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures")
}

fn tmp_dir() -> PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(1);
    let id = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("noxflow-config-test-{nanos}-{id}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

#[test]
fn default_config_has_current_schema_version() {
    let cfg = noxflow_config::default_config();
    assert_eq!(cfg.schema_version, 1);
    assert_eq!(cfg.appearance.density, "comfortable");
    assert_eq!(cfg.shell.name, "noxflow");
    assert!(cfg.providers.audio);
    assert_eq!(cfg.ai.temperature, 0.7);
}

// ---------------------------------------------------------------------------
// Loading from files
// ---------------------------------------------------------------------------

#[test]
fn loads_valid_config() {
    let dir = fixture_dir();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir)
        .load()
        .expect("valid config should load");
    // config.local.toml sets density = "compact"
    assert_eq!(cfg.appearance.density, "compact");
    // profiles/base.toml sets radius = 12 (overridden over config.toml's 14)
    assert_eq!(cfg.appearance.radius, 12);
    // profiles/laptop.toml sets power.profile = "balanced"
    assert_eq!(cfg.power.profile, "balanced");
    // config.local.toml sets wifi_backend = "iwd"
    assert_eq!(cfg.network.wifi_backend, "iwd");
}

#[test]
fn loads_empty_config_with_defaults() {
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), "schema_version = 1\n").unwrap();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect("empty config should load as defaults");
    assert_eq!(cfg.schema_version, 1);
    assert_eq!(cfg.appearance.density, "comfortable");
    assert_eq!(cfg.ai.max_tokens, 4096);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn machine_local_overrides_merge() {
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), r#"
schema_version = 1
[appearance]
density = "spacious"
radius = 16
"#).unwrap();
    fs::write(dir.join("config.local.toml"), r#"
[appearance]
radius = 20
"#).unwrap();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect("should merge local override");
    assert_eq!(cfg.appearance.density, "spacious"); // from base, not overridden
    assert_eq!(cfg.appearance.radius, 20);           // overridden by local
    let _ = fs::remove_dir_all(&dir);
}

// ---------------------------------------------------------------------------
// Profile loading
// ---------------------------------------------------------------------------

#[test]
fn profile_override_from_env_function() {
    let dir = fixture_dir();
    // The env_profile_override() helper reads NOXFLOW_PROFILE;
    // loader takes it explicitly so parallel tests don't interfere.
    let profile = env_profile_override().unwrap_or_else(|| "focus".into());
    let cfg = ConfigLoader::new()
        .with_config_dir(dir)
        .with_profile(profile)
        .load()
        .expect("should load focus profile");
    assert_eq!(cfg.appearance.profile, "material-focus");
    assert!(cfg.shell.reduced_motion); // from profiles/focus.toml
}

#[test]
fn profile_override_from_loader() {
    let dir = fixture_dir();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .with_profile("focus".into())
        .load()
        .expect("should load focus profile");
    assert_eq!(cfg.appearance.profile, "material-focus");
}

// ---------------------------------------------------------------------------
// Profile inheritance
// ---------------------------------------------------------------------------

#[test]
fn profile_inheritance_merges_correctly() {
    let dir = tmp_dir();
    fs::create_dir_all(dir.join("profiles")).unwrap();
    fs::write(dir.join("config.toml"), r#"
schema_version = 1
profile = "child"
"#).unwrap();
    fs::write(dir.join("profiles/child.toml"), r#"
extends = "parent"
[appearance]
density = "compact"
"#).unwrap();
    fs::write(dir.join("profiles/parent.toml"), r#"
[appearance]
radius = 18
mode = "light"
"#).unwrap();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect("inheritance should merge");
    assert_eq!(cfg.appearance.density, "compact"); // from child
    assert_eq!(cfg.appearance.radius, 18);           // from parent
    assert_eq!(cfg.appearance.mode, "light");        // from parent
    let _ = fs::remove_dir_all(&dir);
}

// ---------------------------------------------------------------------------
// Error cases
// ---------------------------------------------------------------------------

#[test]
fn circular_inheritance_detected() {
    let dir = fixture_dir();
    let err = ConfigLoader::new()
        .with_config_dir(dir)
        .with_profile("circular-a".into())
        .load()
        .expect_err("circular inheritance should fail");
    assert!(err.iter().any(|e| matches!(e, ConfigError::CircularInheritance { .. })));
}

#[test]
fn missing_profile_detected() {
    let dir = fixture_dir();
    let err = ConfigLoader::new()
        .with_config_dir(dir)
        .with_profile("nonexistent-parent".into())
        .load()
        .expect_err("missing parent should fail");
    assert!(err.iter().any(|e| matches!(e, ConfigError::ProfileNotFound { .. })));
}

#[test]
fn bad_schema_version_rejected() {
    let dir = fixture_dir();
    let err = ConfigLoader::new()
        .with_config_dir(dir)
        .with_profile("does-not-exist".into())
        .load()
        .expect_err("missing profile should fail");
    assert!(err.iter().any(|e| matches!(e, ConfigError::ProfileNotFound { .. })));
}

#[test]
fn schema_version_validation() {
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), "schema_version = 99\n").unwrap();
    let err = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect_err("bad schema version should fail");
    assert!(err.iter().any(|e| {
        if let ConfigError::Validation { path, .. } = e {
            path == "schema_version"
        } else {
            false
        }
    }));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn invalid_radius_rejected() {
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), r#"
schema_version = 1
[appearance]
radius = 99
"#).unwrap();
    let err = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect_err("radius 99 should fail");
    assert!(err.iter().any(|e| {
        if let ConfigError::Validation { path, .. } = e {
            path == "appearance.radius"
        } else {
            false
        }
    }));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn unknown_fields_are_safely_ignored() {
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), r#"
schema_version = 1
unknown_key = "this should be safely ignored"
[appearance]
density = "comfortable"
unknown_field = "also ignored"
"#).unwrap();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect("unknown fields should be ignored");
    assert_eq!(cfg.appearance.density, "comfortable");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn multiple_validation_errors_reported() {
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), r#"
schema_version = 99
[appearance]
density = "invalid"
radius = 99
[ai]
temperature = 3.5
max_tokens = 200000
"#).unwrap();
    let err = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect_err("multiple validation errors should be reported");
    assert!(err.len() >= 3);
    let paths: Vec<&str> = err.iter().filter_map(|e| {
        if let ConfigError::Validation { path, .. } = e { Some(path.as_str()) } else { None }
    }).collect();
    assert!(paths.contains(&"schema_version"));
    assert!(paths.contains(&"appearance.density"));
    assert!(paths.contains(&"appearance.radius"));
    let _ = fs::remove_dir_all(&dir);
}

// ---------------------------------------------------------------------------
// Redacted display
// ---------------------------------------------------------------------------

#[test]
fn display_config_redacts_api_key() {
    let mut cfg = noxflow_config::default_config();
    cfg.ai.api_key = Some("sk-supersecret-value".into());
    let output = display_config(&cfg);
    assert!(!output.contains("sk-supersecret-value"), "secret should be redacted");
    assert!(output.contains("__REDACTED__"), "should contain redaction marker");
}

// ---------------------------------------------------------------------------
// Runtime paths
// ---------------------------------------------------------------------------

#[test]
fn runtime_paths_are_resolved_from_environment() {
    let dir = fixture_dir();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir)
        .load()
        .expect("valid config should load");
    assert!(cfg.runtime.config_dir.display().to_string().contains("fixtures"));
    assert!(cfg.runtime.socket_path.display().to_string().ends_with("noxd.sock"));
    assert!(cfg.runtime.state_dir.display().to_string().ends_with("noxflow"));
    assert!(cfg.runtime.cache_dir.display().to_string().ends_with("noxflow"));
}

// ---------------------------------------------------------------------------
// Config structure sanity
// ---------------------------------------------------------------------------

#[test]
fn all_sections_present() {
    let cfg = noxflow_config::default_config();
    // appearance
    assert!(!cfg.appearance.profile.is_empty());
    assert!(!cfg.appearance.density.is_empty());
    assert!(cfg.appearance.radius > 0);
    // shell
    assert!(!cfg.shell.name.is_empty());
    assert!(!cfg.shell.fallback.is_empty());
    // providers
    assert!(cfg.providers.audio);
    // notifications
    assert!(cfg.notifications.timeout > 0);
    assert!(cfg.notifications.max_history > 0);
    // power
    assert!(!cfg.power.profile.is_empty());
    assert!(cfg.power.dim_display > 0);
    // network
    assert!(!cfg.network.wifi_backend.is_empty());
    // media
    assert!(cfg.media.mpris_integration);
    // developer
    assert!(!cfg.developer.editor.is_empty());
    assert!(!cfg.developer.terminal.is_empty());
    // ai
    assert!(cfg.ai.enabled);
    assert!(!cfg.ai.provider.is_empty());
    assert!(cfg.ai.temperature > 0.0);
    assert!(cfg.ai.max_tokens > 0);
    // fallback
    assert!(!cfg.fallback.shell.is_empty());
    assert!(!cfg.fallback.compositor.is_empty());
    assert!(!cfg.fallback.launcher.is_empty());
}

// ---------------------------------------------------------------------------
// no_env_leak – verifies parallel tests don't poison each other
// ---------------------------------------------------------------------------

#[test]
fn no_env_leak() {
    // This test should NOT find "focus" in a fresh tmp dir load.
    let dir = tmp_dir();
    fs::write(dir.join("config.toml"), r#"
schema_version = 1
[appearance]
density = "comfortable"
"#).unwrap();
    let cfg = ConfigLoader::new()
        .with_config_dir(dir.clone())
        .load()
        .expect("should load without profile error");
    assert_eq!(cfg.appearance.density, "comfortable");
    assert_eq!(cfg.appearance.profile, "material-expressive");
    let _ = fs::remove_dir_all(&dir);
}
