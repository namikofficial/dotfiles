//! The synchronized provider state and event bus used by `noxd`.

use noxflow_ipc::{
    Action, EventEnvelope, ProviderState, ProviderStatus, Subscription, PROTOCOL_VERSION,
};
use serde_json::json;
use std::{
    collections::{BTreeMap, HashMap},
    sync::{mpsc, Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

pub mod providers;

pub const DEFAULT_QUEUE_CAPACITY: usize = 256;

struct IslandTestEvent {
    provider: String,
    event_type: String,
    data: BTreeMap<String, serde_json::Value>,
    snapshot: ProviderState,
}

impl ProviderEvent for IslandTestEvent {
    fn provider(&self) -> &str {
        &self.provider
    }
    fn event_type(&self) -> &str {
        &self.event_type
    }
    fn data(&self) -> BTreeMap<String, serde_json::Value> {
        self.data.clone()
    }
    fn snapshot(&self) -> ProviderState {
        self.snapshot.clone()
    }
}

/// Publish a synthetic Island event without invoking any hardware backend.
pub fn publish_island_test(bus: &EventBus, action: &Action) -> Result<(), String> {
    if let Action::IslandTestBrightness { percentage } = action {
        if *percentage > 100 {
            return Err("synthetic brightness must be between 0 and 100".into());
        }
    }
    let (provider, field, value, event_type) = match action {
        Action::IslandTestVolume { volume } => {
            ("audio", "output_volume", json!(volume), "state_changed")
        }
        Action::IslandTestOutputMute { muted } => {
            ("audio", "output_muted", json!(muted), "state_changed")
        }
        Action::IslandTestInputMute { muted } => {
            ("audio", "input_muted", json!(muted), "state_changed")
        }
        Action::IslandTestBrightness { percentage } => (
            "brightness",
            "percentage",
            json!(percentage),
            "brightness_changed",
        ),
        _ => return Err("not an Island test action".into()),
    };
    let mut snapshot = bus
        .snapshot()
        .get(provider)
        .cloned()
        .unwrap_or(ProviderState {
            provider: provider.into(),
            status: ProviderStatus::Available,
            data: BTreeMap::new(),
        });
    snapshot.data.insert(field.into(), value.clone());
    let mut data = snapshot.data.clone();
    data.insert(field.into(), value);
    bus.publish(IslandTestEvent {
        provider: provider.into(),
        event_type: event_type.into(),
        data,
        snapshot,
    })
    .map(|_| ())
    .map_err(|error| format!("unable to publish Island test event: {error:?}"))
}

fn timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn stream_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    format!(
        "{}-{}-{}",
        std::process::id(),
        nanos,
        STREAM_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    )
}

static STREAM_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

/// A provider owns the concrete payload type and converts it to the stable IPC shape.
pub trait ProviderEvent: Send + Sync + 'static {
    fn provider(&self) -> &str;
    fn event_type(&self) -> &str;
    fn schema_version(&self) -> u32 {
        1
    }
    fn data(&self) -> BTreeMap<String, serde_json::Value>;
    /// The state represented after this event has been applied.
    fn snapshot(&self) -> ProviderState;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BusError {
    AlreadyRegistered(String),
    UnknownProvider(String),
    Closed,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PublishResult {
    pub delivered: usize,
    pub dropped_subscribers: usize,
}

struct Subscriber {
    providers: Vec<String>,
    event_types: Vec<String>,
    sender: mpsc::SyncSender<EventEnvelope>,
}

struct State {
    providers: BTreeMap<String, ProviderState>,
    subscribers: HashMap<String, Subscriber>,
    sequence: u64,
    next_subscription: u64,
    closed: bool,
}

/// A cloneable, synchronized event bus. All subscriber queues are bounded.
#[derive(Clone)]
pub struct EventBus {
    stream_id: Arc<String>,
    queue_capacity: usize,
    state: Arc<Mutex<State>>,
}

pub struct EventSubscription {
    pub acknowledgement: Subscription,
    receiver: Option<mpsc::Receiver<EventEnvelope>>,
    bus: EventBus,
    disarmed: bool,
}

impl EventSubscription {
    pub fn recv(&self) -> Result<EventEnvelope, mpsc::RecvError> {
        self.receiver
            .as_ref()
            .expect("subscription receiver consumed")
            .recv()
    }

    pub fn try_recv(&self) -> Result<EventEnvelope, mpsc::TryRecvError> {
        self.receiver
            .as_ref()
            .expect("subscription receiver consumed")
            .try_recv()
    }

    pub fn into_parts(mut self) -> (Subscription, mpsc::Receiver<EventEnvelope>) {
        self.disarmed = true;
        (
            self.acknowledgement.clone(),
            self.receiver
                .take()
                .expect("subscription receiver already consumed"),
        )
    }
}

impl Drop for EventSubscription {
    fn drop(&mut self) {
        if !self.disarmed {
            self.bus.unsubscribe(&self.acknowledgement.subscription_id);
        }
    }
}

impl EventBus {
    pub fn new() -> Self {
        Self::with_queue_capacity(DEFAULT_QUEUE_CAPACITY)
    }

    pub fn with_queue_capacity(queue_capacity: usize) -> Self {
        assert!(
            queue_capacity > 0,
            "subscriber queue capacity must be positive"
        );
        Self {
            stream_id: Arc::new(stream_id()),
            queue_capacity,
            state: Arc::new(Mutex::new(State {
                providers: BTreeMap::new(),
                subscribers: HashMap::new(),
                sequence: 0,
                next_subscription: 1,
                closed: false,
            })),
        }
    }

    pub fn stream_id(&self) -> &str {
        self.stream_id.as_str()
    }

    pub fn register_provider(&self, snapshot: ProviderState) -> Result<(), BusError> {
        let mut state = self.state.lock().expect("event bus mutex poisoned");
        if state.closed {
            return Err(BusError::Closed);
        }
        if state.providers.contains_key(&snapshot.provider) {
            return Err(BusError::AlreadyRegistered(snapshot.provider));
        }
        state.providers.insert(snapshot.provider.clone(), snapshot);
        Ok(())
    }

    pub fn update_snapshot(&self, snapshot: ProviderState) -> Result<(), BusError> {
        let mut state = self.state.lock().expect("event bus mutex poisoned");
        if state.closed {
            return Err(BusError::Closed);
        }
        if !state.providers.contains_key(&snapshot.provider) {
            return Err(BusError::UnknownProvider(snapshot.provider));
        }
        state.providers.insert(snapshot.provider.clone(), snapshot);
        Ok(())
    }

    pub fn snapshot(&self) -> BTreeMap<String, ProviderState> {
        self.state
            .lock()
            .expect("event bus mutex poisoned")
            .providers
            .clone()
    }

    pub fn subscribe(
        &self,
        providers: Vec<String>,
        event_types: Vec<String>,
    ) -> Result<EventSubscription, BusError> {
        let (sender, receiver) = mpsc::sync_channel(self.queue_capacity);
        let mut state = self.state.lock().expect("event bus mutex poisoned");
        if state.closed {
            return Err(BusError::Closed);
        }
        let id = format!("sub-{}", state.next_subscription);
        state.next_subscription += 1;
        let snapshots = state
            .providers
            .iter()
            .filter(|(provider, _)| matches_filter(provider, &providers))
            .map(|(provider, snapshot)| (provider.clone(), snapshot.clone()))
            .collect();
        let acknowledgement = Subscription {
            subscription_id: id.clone(),
            stream_id: self.stream_id().to_owned(),
            sequence: state.sequence,
            snapshots,
        };
        state.subscribers.insert(
            id,
            Subscriber {
                providers,
                event_types,
                sender,
            },
        );
        drop(state);
        Ok(EventSubscription {
            acknowledgement,
            receiver: Some(receiver),
            bus: self.clone(),
            disarmed: false,
        })
    }

    pub fn unsubscribe(&self, subscription_id: &str) -> bool {
        self.state
            .lock()
            .expect("event bus mutex poisoned")
            .subscribers
            .remove(subscription_id)
            .is_some()
    }

    pub fn publish<E: ProviderEvent>(&self, event: E) -> Result<PublishResult, BusError> {
        let mut state = self.state.lock().expect("event bus mutex poisoned");
        if state.closed {
            return Err(BusError::Closed);
        }
        if !state.providers.contains_key(event.provider()) {
            return Err(BusError::UnknownProvider(event.provider().to_owned()));
        }
        state
            .providers
            .insert(event.provider().to_owned(), event.snapshot());
        state.sequence = state
            .sequence
            .checked_add(1)
            .expect("event sequence exhausted");
        let envelope = EventEnvelope {
            protocol_version: PROTOCOL_VERSION,
            timestamp: timestamp(),
            stream_id: self.stream_id().to_owned(),
            sequence: state.sequence,
            provider: event.provider().to_owned(),
            event_type: event.event_type().to_owned(),
            schema_version: event.schema_version(),
            data: event.data(),
        };
        let mut result = PublishResult::default();
        let mut dropped = Vec::new();
        for (id, subscriber) in &state.subscribers {
            if !matches_filter(&envelope.provider, &subscriber.providers)
                || !matches_filter(&envelope.event_type, &subscriber.event_types)
            {
                continue;
            }
            match subscriber.sender.try_send(envelope.clone()) {
                Ok(()) => result.delivered += 1,
                Err(mpsc::TrySendError::Full(_)) | Err(mpsc::TrySendError::Disconnected(_)) => {
                    dropped.push(id.clone());
                    result.dropped_subscribers += 1;
                }
            }
        }
        for id in dropped {
            state.subscribers.remove(&id);
        }
        Ok(result)
    }

    pub fn shutdown(&self) {
        let mut state = self.state.lock().expect("event bus mutex poisoned");
        state.closed = true;
        state.subscribers.clear();
    }
}

fn matches_filter(value: &str, filter: &[String]) -> bool {
    filter.is_empty() || filter.iter().any(|candidate| candidate == value)
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use noxflow_ipc::ProviderStatus;

    #[derive(Clone)]
    struct TestEvent {
        provider: &'static str,
        kind: &'static str,
        value: i64,
    }

    impl ProviderEvent for TestEvent {
        fn provider(&self) -> &str {
            self.provider
        }
        fn event_type(&self) -> &str {
            self.kind
        }
        fn data(&self) -> BTreeMap<String, serde_json::Value> {
            [("value".into(), self.value.into())].into_iter().collect()
        }
        fn snapshot(&self) -> ProviderState {
            ProviderState {
                provider: self.provider.into(),
                status: ProviderStatus::Available,
                data: self.data(),
            }
        }
    }

    fn bus(capacity: usize) -> EventBus {
        let bus = EventBus::with_queue_capacity(capacity);
        bus.register_provider(ProviderState {
            provider: "audio".into(),
            status: ProviderStatus::Pending,
            data: BTreeMap::new(),
        })
        .unwrap();
        bus.register_provider(ProviderState {
            provider: "network".into(),
            status: ProviderStatus::Pending,
            data: BTreeMap::new(),
        })
        .unwrap();
        bus
    }

    #[test]
    fn multiple_subscribers_and_filters() {
        let bus = bus(4);
        let audio = bus.subscribe(vec!["audio".into()], vec![]).unwrap();
        let all = bus.subscribe(vec![], vec!["changed".into()]).unwrap();
        bus.publish(TestEvent {
            provider: "audio",
            kind: "changed",
            value: 1,
        })
        .unwrap();
        bus.publish(TestEvent {
            provider: "network",
            kind: "updated",
            value: 2,
        })
        .unwrap();
        assert_eq!(audio.try_recv().unwrap().sequence, 1);
        assert_eq!(all.try_recv().unwrap().sequence, 1);
    }

    #[test]
    fn ordering_and_snapshot_boundary_are_stable() {
        let bus = bus(4);
        let first = bus.subscribe(vec!["audio".into()], vec![]).unwrap();
        bus.publish(TestEvent {
            provider: "audio",
            kind: "changed",
            value: 1,
        })
        .unwrap();
        let second = bus.subscribe(vec!["audio".into()], vec![]).unwrap();
        bus.publish(TestEvent {
            provider: "audio",
            kind: "changed",
            value: 2,
        })
        .unwrap();
        assert_eq!(
            std::iter::from_fn(|| first.try_recv().ok())
                .map(|event| event.sequence)
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
        assert_eq!(second.acknowledgement.sequence, 1);
        assert_eq!(
            std::iter::from_fn(|| second.try_recv().ok())
                .map(|event| event.sequence)
                .collect::<Vec<_>>(),
            vec![2]
        );
        assert_eq!(
            bus.snapshot()["audio"].data["value"],
            serde_json::Value::from(2)
        );
    }

    #[test]
    fn overflow_drops_only_slow_subscriber() {
        let bus = bus(1);
        let slow = bus.subscribe(vec!["audio".into()], vec![]).unwrap();
        let fast = bus.subscribe(vec!["audio".into()], vec![]).unwrap();
        bus.publish(TestEvent {
            provider: "audio",
            kind: "changed",
            value: 1,
        })
        .unwrap();
        assert!(fast.try_recv().is_ok());
        let result = bus
            .publish(TestEvent {
                provider: "audio",
                kind: "changed",
                value: 2,
            })
            .unwrap();
        assert_eq!(result.dropped_subscribers, 1);
        assert!(slow.try_recv().is_ok());
        assert_eq!(
            bus.publish(TestEvent {
                provider: "audio",
                kind: "changed",
                value: 3
            })
            .unwrap()
            .delivered,
            0
        );
    }

    #[test]
    fn shutdown_closes_subscribers_after_queued_events() {
        let bus = bus(2);
        let subscription = bus.subscribe(vec![], vec![]).unwrap();
        bus.publish(TestEvent {
            provider: "audio",
            kind: "changed",
            value: 1,
        })
        .unwrap();
        bus.shutdown();
        assert_eq!(
            std::iter::from_fn(|| subscription.try_recv().ok()).count(),
            1
        );
        assert!(matches!(
            subscription.try_recv(),
            Err(mpsc::TryRecvError::Disconnected)
        ));
        assert_eq!(
            bus.publish(TestEvent {
                provider: "audio",
                kind: "changed",
                value: 2
            }),
            Err(BusError::Closed)
        );
    }

    #[test]
    fn island_test_publishes_without_hardware_access() {
        let bus = bus(2);
        let subscription = bus.subscribe(vec!["audio".into()], vec![]).unwrap();
        publish_island_test(&bus, &Action::IslandTestVolume { volume: 55 }).unwrap();
        let event = subscription.try_recv().unwrap();
        assert_eq!(event.provider, "audio");
        assert_eq!(event.event_type, "state_changed");
        assert_eq!(event.data["output_volume"], 55);
        assert_eq!(bus.snapshot()["audio"].data["output_volume"], 55);
    }
}
