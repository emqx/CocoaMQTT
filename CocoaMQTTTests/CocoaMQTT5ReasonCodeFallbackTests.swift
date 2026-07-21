import Foundation
import XCTest
@testable import CocoaMQTT

final class CocoaMQTT5ReasonCodeFallbackTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    func testDisconnectRejectsInvalidReasonCode() {
        let frame = FrameDisconnect(packetFixedHeaderType: FrameType.disconnect.rawValue, bytes: [0xFF], protocolVersion: .v5)
        XCTAssertNil(frame)
    }

    func testAuthRejectsInvalidReasonCode() {
        let frame = FrameAuth(packetFixedHeaderType: FrameType.auth.rawValue, bytes: [0xFF], protocolVersion: .v5)
        XCTAssertNil(frame)
    }
}
