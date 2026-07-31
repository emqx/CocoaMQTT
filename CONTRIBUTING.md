# Contributing to CocoaMQTT

Thank you for helping improve CocoaMQTT. This copy of the contribution guide
describes CocoaMQTT 3 development on `master`. The repository default remains
the maintained `release/2.x` line until CocoaMQTT 3 is ready, so contributors
must choose the pull request base deliberately.

## Choose the target branch

| Change | Pull request base |
| --- | --- |
| CocoaMQTT 3 architecture, features, or breaking changes | `master` |
| Security, protocol-correctness, regression, or compatibility fix needed only by the maintained 2.x line | `release/2.x` |
| Fix applicable to both lines | `master` first, followed by a reviewed cherry-pick or equivalent 2.x pull request |
| Documentation describing only one release line | The branch that owns that documentation |

GitHub initially selects `release/2.x` because it is the default branch. Change
the base to `master` before opening a CocoaMQTT 3 pull request.

Do not merge either branch wholesale into the other. They have intentionally
different transport architectures, version metadata, dependencies, and
compatibility policies. Share an applicable change through a reviewed
cherry-pick or an equivalent branch-specific implementation. See the
[2.x maintenance policy](https://github.com/emqx/CocoaMQTT/blob/release/2.x/MAINTENANCE.md)
for the stable branch scope.

## Before coding

- Search existing issues and pull requests.
- For behavior changes, describe the observed and expected MQTT behavior.
- Reproduce bugs with the smallest practical test case.
- Discuss broad architecture or public API changes in an issue before
  implementation.
- Preserve public API and Objective-C delegate compatibility unless an issue
  explicitly approves a CocoaMQTT 3 breaking change and its migration path.

## CocoaMQTT 3 design principles

- Keep the MQTT 3.1.1 and MQTT 5 public facades while moving protocol-neutral
  lifecycle behavior into shared, testable components.
- Keep protocol differences explicit rather than selecting behavior through
  global mutable state.
- Validate transport changes against TCP, TLS, mutual TLS, WebSocket,
  disconnect, timeout, and reconnect behavior as applicable.
- Document minimum-platform, dependency, and migration impact for every
  intentional breaking change.

## Build and test

From the repository root:

```bash
swift build
swift test
xcodebuild \
  -project CocoaMQTT.xcodeproj \
  -scheme "Mac Framework" \
  -derivedDataPath . \
  build
```

Broker-dependent tests expect local MQTT listeners such as `localhost:1883`
and WebSocket `localhost:8083`. Start a local MQTT broker before running the
full integration suite.

Use focused deterministic XCTest coverage for frame parsing, state machines,
and regressions. Add integration tests when transport or protocol flow cannot
be validated reliably with a unit test.

CocoaMQTT 3 snapshots are currently distributed through Swift Package Manager,
not CocoaPods. When a change touches shared source or CocoaPods packaging that
must remain valid before the 3.0 distribution policy is finalized, also run:

```bash
pod lib lint CocoaMQTT.podspec --allow-warnings --skip-tests
```

## Code style

- Follow Swift 5 conventions with four-space indentation.
- Use `UpperCamelCase` for types and protocols and `lowerCamelCase` for
  properties and functions.
- Keep file names aligned with their primary type.
- Keep commits scoped to one logical change and include related tests.

## Pull requests

Every pull request should include:

- what changed and why;
- the linked issue or a clear explanation when no issue is needed;
- compatibility and migration impact;
- exact verification commands run;
- screenshots or a short recording for Example app UI changes.

All review conversations must be resolved, and required CI checks must pass,
before merging.
