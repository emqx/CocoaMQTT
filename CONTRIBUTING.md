# Contributing to CocoaMQTT

Thank you for helping improve CocoaMQTT. Before opening a pull request, choose
its base branch deliberately: the repository default is the maintained 2.x
line, while CocoaMQTT 3 is developed separately.

## Choose the target branch

| Change | Pull request base |
| --- | --- |
| CocoaMQTT 3 architecture, features, or breaking changes | `master` |
| Security, protocol-correctness, regression, or compatibility fix needed only by the maintained 2.x line | `release/2.x` |
| Fix applicable to both lines | `master` first, followed by a reviewed cherry-pick or equivalent 2.x pull request |
| Documentation describing only one release line | The branch that owns that documentation |

GitHub initially selects `release/2.x` because it is the default branch. Change
the base to `master` before opening a CocoaMQTT 3 pull request.

Do not merge `master` into `release/2.x`. The branches have intentionally
different transport architectures and compatibility policies. See the
[2.x maintenance policy](MAINTENANCE.md) for the stable branch scope.

## Before coding

- Search existing issues and pull requests.
- For behavior changes, describe the observed and expected MQTT behavior.
- Reproduce bugs with the smallest practical test case.
- Keep public API and Objective-C delegate compatibility unless the issue and
  pull request explicitly justify a CocoaMQTT 3 breaking change.

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
pod lib lint CocoaMQTT.podspec --allow-warnings --skip-tests
```

Broker-dependent tests expect local MQTT listeners such as `localhost:1883`
and WebSocket `localhost:8083`. Start a local MQTT broker before running the
full integration suite.

Use focused deterministic XCTest coverage for frame parsing, state machines,
and regressions. Add integration tests when transport or protocol flow cannot
be validated reliably with a unit test.

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
