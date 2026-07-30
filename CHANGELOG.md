# Changelog

## 2.4.0

CocoaMQTT 2.4.0 is the stable, long-term-maintenance baseline for the 2.x
architecture. It preserves CocoaAsyncSocket and the Starscream fallback while
collecting the correctness and compatibility work completed after 2.3.0.

Highlights:

- hardened MQTT 3.1.1 and MQTT 5 reconnect, session, QoS, keepalive, and
  graceful-disconnect lifecycles;
- fixed concurrent publish, callback, delivery, and connection-state races;
- added configurable packet-read, socket-write, and WebSocket message limits;
- unified TCP and Foundation WebSocket server trust configuration;
- added PEM/DER and PKCS#12 client identities, including mutual TLS over TCP and
  Foundation WebSockets;
- added Swift 6 consumer checks and visionOS compile verification;
- retained legacy decoder and `ConcurrentAtomic.mutate` entry points needed by
  2.3 source consumers.

Compatibility note:

- `ThreadSafeDictionary.Iterator` now iterates over a stable dictionary snapshot
  instead of indexing the live mutable dictionary. Code that explicitly names
  the old concrete `IndexingIterator<ThreadSafeDictionary<...>>` type must use
  type inference or the `Sequence` APIs. `for-in` and `map` use snapshot
  iteration. Index-based Collection access is not safe across concurrent
  mutations; use `snapshot()` for multi-step indexed access.
- `ConcurrentAtomic` property assignment and `mutate` remain source-compatible
  but now execute synchronously. They return only after applying the mutation,
  so code must not rely on the former fire-and-forget ordering. A mutation
  closure must not read from or write to the same wrapper because that would
  re-enter its synchronization barrier. Use the new `withMutation` API when the
  transform needs to return a value.
- Deprecated decoder overloads without a `protocolVersion` now assume MQTT 5
  packet data. Use the explicit overload when decoding MQTT 3.1.1 data.
