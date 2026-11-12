import XCTest
@testable import CocoaMQTT

final class LazyLoggingTests: XCTestCase {

    private final class RecordingLogger: CocoaMQTTLogger {
        private let lock = NSLock()
        private var _records: [(CocoaMQTTLoggerLevel, String)] = []

        var records: [(CocoaMQTTLoggerLevel, String)] {
            lock.lock()
            defer { lock.unlock() }
            return _records
        }

        override func log(level: CocoaMQTTLoggerLevel, message: String) {
            lock.lock()
            _records.append((level, message))
            lock.unlock()
        }
    }

    private final class DescriptionProbe: CustomStringConvertible {
        private(set) var evaluations = 0

        var description: String {
            evaluations += 1
            return "probe"
        }
    }

    private var originalLogger: CocoaMQTTLogger!

    override func setUp() {
        super.setUp()
        originalLogger = CocoaMQTTLogger.logger
    }

    override func tearDown() {
        CocoaMQTTLogger.logger = originalLogger
        super.tearDown()
    }

    func testMessagesBelowMinLevelAreNotBuilt() {
        let logger = RecordingLogger()
        logger.minLevel = .warning
        CocoaMQTTLogger.logger = logger
        let probe = DescriptionProbe()

        printDebug("debug \(probe)")
        printInfo("info \(probe)")

        XCTAssertEqual(probe.evaluations, 0)
        XCTAssertTrue(logger.records.isEmpty)
    }

    func testMessagesAtOrAboveMinLevelAreDelivered() {
        let logger = RecordingLogger()
        logger.minLevel = .info
        CocoaMQTTLogger.logger = logger
        let probe = DescriptionProbe()

        printDebug("debug \(probe)")
        printInfo("info \(probe)")
        printWarning("warning \(probe)")
        printError("error \(probe)")

        XCTAssertEqual(probe.evaluations, 3)
        XCTAssertEqual(logger.records.map(\.0), [.info, .warning, .error])
        XCTAssertEqual(logger.records.map(\.1), ["info probe", "warning probe", "error probe"])
    }

    func testMinLevelOffSuppressesEverything() {
        let logger = RecordingLogger()
        logger.minLevel = .off
        CocoaMQTTLogger.logger = logger
        let probe = DescriptionProbe()

        printError("error \(probe)")

        XCTAssertEqual(probe.evaluations, 0)
        XCTAssertTrue(logger.records.isEmpty)
    }

    func testIsEnabledFollowsMinLevel() {
        let logger = CocoaMQTTLogger()
        logger.minLevel = .info

        XCTAssertFalse(logger.isEnabled(.debug))
        XCTAssertTrue(logger.isEnabled(.info))
        XCTAssertTrue(logger.isEnabled(.error))
    }

    func testFrameBytesDoesNotLogPayloadWhenDebugDisabled() {
        let logger = RecordingLogger()
        logger.minLevel = .info
        CocoaMQTTLogger.logger = logger
        let frame = FramePublish(topic: "t", payload: [UInt8](repeating: 0x41, count: 1024), qos: .qos1, msgid: 1)

        _ = frame.bytes(version: "5.0")
        _ = frame.bytes(version: "3.1.1")

        XCTAssertTrue(logger.records.isEmpty)
    }

    func testFrameBytesLogsPayloadWhenDebugEnabled() {
        let logger = RecordingLogger()
        logger.minLevel = .debug
        CocoaMQTTLogger.logger = logger
        let frame = FramePublish(topic: "t", payload: [0x41, 0x42], qos: .qos1, msgid: 1)

        _ = frame.bytes(version: "5.0")

        XCTAssertTrue(logger.records.contains { $0.0 == .debug && $0.1 == "payload [65, 66]" })
    }
}
