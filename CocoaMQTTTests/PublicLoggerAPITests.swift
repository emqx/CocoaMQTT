import XCTest
import CocoaMQTT

final class PublicLoggerAPITests: XCTestCase {
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            usleep(10_000)
        }
        return condition()
    }

    func testLoggerMinLevelIsPubliclyAccessible() {
        let original = CocoaMQTTLogger.logger.minLevel
        defer { CocoaMQTTLogger.logger.minLevel = original }

        CocoaMQTTLogger.logger.minLevel = .debug
        XCTAssertEqual(CocoaMQTTLogger.logger.minLevel, .debug)
    }

    func testLoggerMinLevelConcurrentAccessDoesNotDeadlock() {
        let original = CocoaMQTTLogger.logger.minLevel
        defer { CocoaMQTTLogger.logger.minLevel = original }

        let queue = DispatchQueue(label: "tests.public.logger.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for idx in 0..<200 {
            group.enter()
            queue.async {
                CocoaMQTTLogger.logger.minLevel = (idx % 2 == 0) ? .warning : .error
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(waitUntil(timeout: 2) { [.warning, .error].contains(CocoaMQTTLogger.logger.minLevel) })

        let readQueue = DispatchQueue(label: "tests.public.logger.concurrent.read", attributes: .concurrent)
        let readGroup = DispatchGroup()
        for _ in 0..<200 {
            readGroup.enter()
            readQueue.async {
                _ = CocoaMQTTLogger.logger.minLevel
                readGroup.leave()
            }
        }

        XCTAssertEqual(readGroup.wait(timeout: .now() + 10), .success)
    }
}
