//! The versioned JSON contract shared by noxd, noxctl, and Quickshell.
//!
//! The Unix socket transport uses UTF-8 newline-delimited JSON (NDJSON): every
//! request and response is one compact JSON object terminated by `\\n`.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

pub const PROTOCOL_VERSION: u32 = 1;
pub const SUPPORTED_PROTOCOL_VERSIONS: &[u32] = &[PROTOCOL_VERSION];
pub const SOCKET_DIRECTORY: &str = "noxflow";
pub const SOCKET_NAME: &str = "noxd.sock";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RequestEnvelope {
    #[serde(rename = "version")]
    pub protocol_version: u32,
    #[serde(rename = "id")]
    pub request_id: String,
    #[serde(flatten)]
    pub request: Request,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "method", content = "params", rename_all = "snake_case")]
pub enum Request {
    Ping,
    GetVersion,
    GetState,
    GetProviderState {
        provider: String,
    },
    Subscribe {
        providers: Vec<String>,
        event_types: Vec<String>,
    },
    Unsubscribe {
        subscription_id: String,
    },
    SetSetting {
        key: String,
        value: Value,
    },
    RunAction {
        action: Action,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Lock,
    Suspend,
    Reboot,
    PowerOff,
    RefreshProviders,
    SetProfile {
        profile: String,
    },
    AudioSetVolume {
        target: AudioTarget,
        volume: u8,
    },
    AudioAdjustVolume {
        target: AudioTarget,
        delta: i16,
    },
    AudioToggleMute {
        target: AudioTarget,
    },
    AudioSetDefault {
        target: AudioTarget,
        selector: String,
    },
    BrightnessSet {
        percentage: u8,
    },
    BrightnessAdjust {
        delta: i16,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AudioTarget {
    Output,
    Input,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ResponseEnvelope {
    #[serde(rename = "version")]
    pub protocol_version: u32,
    #[serde(rename = "id")]
    pub request_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Response>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<IpcError>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", content = "data", rename_all = "snake_case")]
pub enum Response {
    Pong,
    Version(VersionInfo),
    State(State),
    ProviderState(ProviderState),
    Subscription(Subscription),
    SettingUpdated(SettingUpdated),
    ActionAccepted(ActionAccepted),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct VersionInfo {
    pub daemon_version: String,
    pub protocol_version: u32,
    pub supported_protocol_versions: Vec<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct State {
    pub timestamp: u64,
    #[serde(default)]
    pub providers: BTreeMap<String, ProviderState>,
    #[serde(default)]
    pub settings: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderState {
    pub provider: String,
    pub status: ProviderStatus,
    #[serde(default)]
    pub data: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProviderStatus {
    Available,
    Unavailable,
    Degraded,
    Pending,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Subscription {
    pub subscription_id: String,
    pub stream_id: String,
    pub sequence: u64,
    #[serde(default)]
    pub snapshots: BTreeMap<String, ProviderState>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SettingUpdated {
    pub key: String,
    pub value: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ActionAccepted {
    pub action: Action,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EventEnvelope {
    #[serde(rename = "version")]
    pub protocol_version: u32,
    pub timestamp: u64,
    pub stream_id: String,
    pub sequence: u64,
    pub provider: String,
    pub event_type: String,
    pub schema_version: u32,
    #[serde(default)]
    pub data: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IpcError {
    pub code: ErrorCode,
    pub message: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub details: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    InvalidRequest,
    UnsupportedProtocolVersion,
    UnknownMethod,
    InvalidParams,
    UnknownProvider,
    UnknownSetting,
    UnknownAction,
    Unsupported,
    NotSubscribed,
    Internal,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeError {
    InvalidJson(String),
    MissingRequestId,
    UnsupportedProtocolVersion { request_id: String, requested: u32 },
    InvalidRequest(String),
}

pub fn decode_request(input: &str) -> Result<RequestEnvelope, DecodeError> {
    let value: Value =
        serde_json::from_str(input).map_err(|error| DecodeError::InvalidJson(error.to_string()))?;
    let request_id = value
        .get("id")
        .and_then(Value::as_str)
        .ok_or(DecodeError::MissingRequestId)?
        .to_owned();
    let version = value
        .get("version")
        .and_then(Value::as_u64)
        .ok_or_else(|| DecodeError::InvalidRequest("missing version".into()))?
        as u32;
    if !SUPPORTED_PROTOCOL_VERSIONS.contains(&version) {
        return Err(DecodeError::UnsupportedProtocolVersion {
            request_id,
            requested: version,
        });
    }
    serde_json::from_value(value).map_err(|error| DecodeError::InvalidRequest(error.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_round_trips() {
        let envelope = RequestEnvelope {
            protocol_version: 1,
            request_id: "req-7".into(),
            request: Request::RunAction {
                action: Action::Lock,
            },
        };
        let json = serde_json::to_string(&envelope).unwrap();
        assert_eq!(decode_request(&json).unwrap(), envelope);
    }

    #[test]
    fn unknown_fields_are_ignored() {
        let request =
            decode_request(r#"{"version":1,"id":"1","method":"ping","future":true}"#).unwrap();
        assert_eq!(request.request, Request::Ping);
    }

    #[test]
    fn unsupported_version_is_detected() {
        assert_eq!(
            decode_request(r#"{"version":99,"id":"abc","method":"ping"}"#),
            Err(DecodeError::UnsupportedProtocolVersion {
                request_id: "abc".into(),
                requested: 99
            })
        );
    }

    #[test]
    fn response_references_request_id() {
        let response = ResponseEnvelope {
            protocol_version: 1,
            request_id: "req-1".into(),
            result: Some(Response::Pong),
            error: None,
        };
        let json = serde_json::to_value(response).unwrap();
        assert_eq!(json["id"], "req-1");
        assert_eq!(json["result"]["type"], "pong");
    }

    #[test]
    fn event_contains_required_metadata() {
        let event = EventEnvelope {
            protocol_version: 1,
            timestamp: 123,
            stream_id: "test-stream".into(),
            sequence: 1,
            provider: "audio".into(),
            event_type: "volume_changed".into(),
            schema_version: 1,
            data: BTreeMap::new(),
        };
        let json = serde_json::to_value(event).unwrap();
        assert_eq!(json["timestamp"], 123);
        assert_eq!(json["provider"], "audio");
        assert_eq!(json["event_type"], "volume_changed");
    }
}
