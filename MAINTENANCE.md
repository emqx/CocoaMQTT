# CocoaMQTT 2.x maintenance policy

`release/2.x` is the long-term maintenance line for CocoaMQTT 2. Its first
release is 2.4.0, based on commit
`c09666c86084212736d68fa7c652d20ed4753c4c`, the final `master` commit before
the CocoaMQTT 3 transport architecture changes.

## Scope

The 2.x line accepts:

- security and protocol-correctness fixes;
- regressions and high-impact bug fixes;
- compatibility fixes for supported Apple platforms, Swift, Swift Package
  Manager, and CocoaPods;
- documentation and test improvements needed to support those fixes.

The 2.x line does not accept new transport architecture, dependency migrations,
minimum-platform increases, or broad new features. CocoaAsyncSocket remains the
TCP transport, and Starscream remains the fallback WebSocket transport on older
supported Apple operating systems.

Applicable fixes developed on `master` should be reviewed and cherry-picked
into `release/2.x`; the branches must not be merged wholesale.

## Compatibility

Patch releases in this line preserve the 2.4 public API and supported platform
matrix. CI builds both package products, validates CocoaPods, and checks the
public API against both 2.3.0 and the pull request base commit.

Stable tags are created through the `Release CocoaMQTT 2.x` workflow after it
revalidates release metadata, API compatibility, package tests, and CocoaPods.

`ThreadSafeDictionary.Iterator` intentionally changed from an index-based live
iterator to a dictionary snapshot iterator. Restoring the old concrete iterator
would reintroduce invalid-index crashes during concurrent mutation. The type
continues to conform to `Collection`, while ordinary iteration uses a stable
snapshot. Index-based Collection access is not safe across mutations; use
`snapshot()` for multi-step indexed access.

The deprecated decoder overloads without an explicit protocol version assume
MQTT 5 packet data. `ConcurrentAtomic` property assignment and `mutate` retain
their 2.3 source signatures but execute synchronously in 2.4. A mutation
closure must not read from or write to the same wrapper.

## Support lifetime

CocoaMQTT 2.x will be maintained for at least 12 months after CocoaMQTT 3.0.0
is released. Any end-of-life date will be announced at least six months in
advance in the repository README and GitHub releases.
