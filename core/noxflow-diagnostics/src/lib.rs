//! Safe, journald-friendly diagnostics shared by NoxFlow binaries.

use serde_json::{json, Map, Value};
use std::{
    collections::HashMap,
    panic::PanicHookInfo,
    sync::Mutex,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub fn timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Emit one structured record. Only explicitly supplied safe fields are accepted.
pub fn log(
    component: &str,
    level: &str,
    event: &str,
    provider: Option<&str>,
    request_id: Option<&str>,
    message: Option<&str>,
) {
    let mut record = Map::new();
    record.insert("timestamp".into(), json!(timestamp()));
    record.insert("level".into(), json!(level));
    record.insert("event".into(), json!(event));
    record.insert("component".into(), json!(component));
    record.insert("pid".into(), json!(std::process::id()));
    if let Some(provider) = provider {
        record.insert("provider".into(), json!(provider));
    }
    if let Some(request_id) = request_id {
        record.insert("request_id".into(), json!(request_id));
    }
    if let Some(message) = message {
        record.insert("message".into(), json!(sanitize(message)));
    }
    eprintln!("{}", Value::Object(record));
}

pub fn sanitize(value: &str) -> String {
    let lower = value.to_ascii_lowercase();
    if [
        "password",
        "secret",
        "token",
        "api_key",
        "clipboard",
        "authorization",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        "redacted diagnostic value".into()
    } else {
        value.chars().take(512).collect()
    }
}

pub fn install_panic_hook(component: &'static str) {
    std::panic::set_hook(Box::new(move |info| panic_record(component, info)));
}

fn panic_record(component: &str, info: &PanicHookInfo<'_>) {
    let location = info
        .location()
        .map(|location| format!("{}:{}", location.file(), location.line()));
    let payload = info
        .payload()
        .downcast_ref::<&str>()
        .copied()
        .or_else(|| info.payload().downcast_ref::<String>().map(String::as_str))
        .unwrap_or("panic payload unavailable");
    log(
        component,
        "error",
        "panic",
        None,
        None,
        Some(&format!(
            "thread={:?}; location={}; {}",
            std::thread::current().name(),
            location.as_deref().unwrap_or("unknown"),
            sanitize(payload)
        )),
    );
}

#[derive(Default)]
struct FailureState {
    last: Option<Instant>,
    suppressed: u64,
}

/// Per-provider burst limiter. The first failure is emitted, repeats are counted,
/// and the next allowed failure includes the suppressed count.
pub struct ProviderFailureLimiter {
    interval: Duration,
    state: Mutex<HashMap<String, FailureState>>,
}

impl ProviderFailureLimiter {
    pub fn new(interval: Duration) -> Self {
        Self {
            interval,
            state: Mutex::new(HashMap::new()),
        }
    }

    pub fn record(&self, provider: &str) -> Option<u64> {
        let mut state = self
            .state
            .lock()
            .expect("diagnostics limiter mutex poisoned");
        let entry = state.entry(provider.to_owned()).or_default();
        let now = Instant::now();
        match entry.last {
            Some(last) if now.duration_since(last) < self.interval => {
                entry.suppressed += 1;
                None
            }
            _ => {
                let suppressed = entry.suppressed;
                entry.last = Some(now);
                entry.suppressed = 0;
                Some(suppressed)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_sensitive_words_and_limits_length() {
        assert_eq!(
            sanitize("clipboard contents: secret"),
            "redacted diagnostic value"
        );
        assert_eq!(sanitize(&"x".repeat(600)).len(), 512);
    }

    #[test]
    fn limiter_emits_first_and_summary_after_interval() {
        let limiter = ProviderFailureLimiter::new(Duration::from_millis(1));
        assert_eq!(limiter.record("hyprland"), Some(0));
        assert_eq!(limiter.record("hyprland"), None);
        std::thread::sleep(Duration::from_millis(3));
        assert_eq!(limiter.record("hyprland"), Some(1));
        assert_eq!(limiter.record("audio"), Some(0));
    }
}
