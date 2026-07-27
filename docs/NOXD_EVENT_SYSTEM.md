# noxd event system

`noxd` owns provider state and distributes provider changes through one
synchronized event bus. Providers publish typed Rust values; only the IPC
writer converts those values into newline-delimited JSON.

## Ownership and synchronization

`EventBus` contains the provider snapshot map, subscriber registry, stream ID,
and sequence counter behind one `Mutex`. Registration, subscription, snapshot
capture, and publication are serialized together. A publish updates the
provider snapshot and then assigns the next sequence number, so a subscription
acknowledgement has an exact snapshot boundary.

The bus has no global mutable state. `EventBus` is cloneable because clones
share the synchronized state. Providers do not access subscriber channels
directly.

## Provider API

Providers register an initial `ProviderState`. Each provider owns its event
payload type and implements `ProviderEvent`, supplying:

- provider ID;
- event type;
- payload schema version;
- JSON-compatible event data;
- the resulting provider snapshot.

The power provider polls UPower and power-profiles-daemon through D-Bus. It
publishes `battery_low` and `battery_critical` only when UPower's warning level
transitions into the corresponding severity; repeated observations are
suppressed until the battery recovers or begins charging.

Publishing an event updates the canonical snapshot and delivers the event to
matching subscribers. Publishing an unregistered provider is rejected. This
slice defines the bus only; system provider implementations are intentionally
out of scope. The audio provider publishes state and device changes from the
PipeWire-Pulse `pactl subscribe` stream rather than polling `wpctl`.

## Subscriptions and snapshots

Subscriptions filter by provider and event type. Empty filters mean all values.
The bus creates a bounded queue and registers it before returning the
acknowledgement. The acknowledgement contains the subscription ID, daemon
stream ID, sequence boundary, and matching provider snapshots. Events delivered
after that point have a greater sequence number.

The daemon uses a dedicated writer per client. Responses and unsolicited event
messages share that writer, ensuring the subscription acknowledgement is
written before its live events. Provider publication never writes to a socket.

## Backpressure and cleanup

Every bus subscriber queue has a capacity of 256 events by default. Tests can
construct a bus with a smaller capacity. Publication uses non-blocking
`try_send`:

- a full or disconnected queue removes only that subscriber;
- other subscribers continue receiving events;
- the affected client must reconnect and obtain a fresh snapshot.

The daemon-to-writer bridge is bounded as well. If the client cannot keep up,
the bus queue eventually fills and the subscriber is dropped rather than
blocking a provider or creating an unbounded queue.

Unsubscribe removes the subscriber and closes its receiver. Client disconnects
perform the same cleanup for every subscription owned by that connection.

## Wire metadata and ordering

Each event includes protocol version, Unix timestamp in seconds, provider,
event type, schema version, stream ID, and a monotonically increasing sequence
number. Sequence numbers are scoped to the stream ID, which changes for every
daemon instance. Clients can therefore detect a gap or restart and request a
fresh snapshot.

## Shutdown

Shutdown marks the bus closed, rejects new subscriptions and publications, and
drops all subscriber senders. Receivers can drain events already queued, then
observe stream closure. Client event-forwarding threads and writers are joined
after the listener stops, and no provider task is allowed to wait on a client
socket.
