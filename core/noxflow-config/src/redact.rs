use crate::Config;

// ---------------------------------------------------------------------------
// Redacted display
// ---------------------------------------------------------------------------

/// Serialize the resolved `Config` to pretty JSON, with sensitive fields
/// replaced by `"__REDACTED__"` and runtime paths included.
pub fn display_config(config: &Config) -> String {
    // Serialize Config – `runtime` is skipped by serde.
    let mut root: serde_json::Value =
        serde_json::to_value(config).unwrap_or(serde_json::Value::Null);

    // Attach runtime paths so the user sees the resolved paths.
    if let serde_json::Value::Object(ref mut map) = root {
        let runtime = serde_json::to_value(&config.runtime).unwrap_or(serde_json::Value::Null);
        map.insert("runtime".into(), runtime);
    }

    redact_value(&mut root);

    serde_json::to_string_pretty(&root).unwrap_or_else(|_| "{}".into())
}

fn redact_value(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::Object(map) => {
            let keys: Vec<String> = map.keys().cloned().collect();
            for key in keys {
                if is_secret_field(&key) {
                    map.insert(key, serde_json::Value::String("__REDACTED__".into()));
                } else if let Some(val) = map.get_mut(&key) {
                    redact_value(val);
                }
            }
        }
        serde_json::Value::Array(arr) => {
            for item in arr.iter_mut() {
                redact_value(item);
            }
        }
        _ => {}
    }
}

fn is_secret_field(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.ends_with("_key")
        || lower.ends_with("_token")
        || lower.ends_with("_secret")
        || lower.ends_with("_password")
        || lower == "api_key"
        || lower == "apikey"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_api_key() {
        let mut config = Config::default();
        config.ai.api_key = Some("sk-supersecret".into());

        let output = display_config(&config);
        assert!(output.contains("__REDACTED__"));
        assert!(!output.contains("sk-supersecret"));
    }
}
