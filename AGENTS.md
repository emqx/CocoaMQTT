# Repository Guidelines

## Project Structure & Module Organization
- `Source/` contains the library code. Core MQTT clients live in `CocoaMQTT.swift` (v3.1.1) and `CocoaMQTT5.swift` (v5), with transport and parsing split into files like `CocoaMQTTSocket.swift`, `CocoaMQTTWebSocket.swift`, and `Frame*.swift`.
- `CocoaMQTTTests/` contains XCTest targets for frame encoding/decoding, delivery queue behavior, storage, and broker integration.
- `Example/Example/` is the sample iOS app for manual validation.
- Package/dependency manifests are at the repo root: `Package.swift`, `CocoaMQTT.podspec`, and `Cartfile`.

## Build, Test, and Development Commands
- `swift build` — build Swift Package Manager targets.
- `swift test` — run all XCTest cases via SwiftPM.
- `xcodebuild -project CocoaMQTT.xcodeproj -scheme CocoaMQTT -derivedDataPath . build test` — CI-aligned build + test flow.
- `carthage update --platform iOS,macOS,tvOS --use-xcframeworks` — refresh Carthage artifacts when validating integration changes.

## Coding Style & Naming Conventions
- Use Swift 5 conventions with 4-space indentation and braces on the same line.
- Types/protocols use `UpperCamelCase`; properties/functions use `lowerCamelCase`.
- Keep file names aligned to primary type (`FramePublish.swift`, `MqttDecodeSubAck.swift`).
- Preserve public API compatibility and Obj-C interoperability (`@objc`) when touching delegate-facing interfaces.

## Testing Guidelines
- Framework: XCTest (`CocoaMQTTTests`).
- Name tests with `test...` and keep assertions focused on a single behavior.
- Prefer deterministic unit tests for frame parsing/serialization; add integration tests only when protocol flow requires it.
- Broker-dependent tests expect local endpoints (for example `localhost:1883` and websocket `:8083`), so start a local MQTT broker before full test runs.

## Commit & Pull Request Guidelines
- Follow the existing history style: concise imperative subjects (e.g., `Fix frame publish crash`) and optional prefixes like `fix:`/`chore:`.
- Keep commits scoped to one logical change and include related tests in the same commit.
- PRs should include: what changed, why, linked issue(s), and exact verification commands run.
- For `Example/` UI or behavior changes, include screenshots or a short screen recording.
