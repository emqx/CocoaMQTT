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

    private func makeReader() -> CocoaMQTTReader {
        CocoaMQTTReader(socket: SocketSpy(), delegate: nil)
    }

    func testDisconnectFallsBackToNormalDisconnectionForInvalidReasonCode() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")

        let mqtt5 = CocoaMQTT5(clientID: "mq5-disconnect-fallback-\(UUID().uuidString)")
        var captured: CocoaMQTTDISCONNECTReasonCode?
        mqtt5.didDisconnectReasonCode = { _, reason in
            captured = reason
        }

        let frame = FrameDisconnect(packetFixedHeaderType: FrameType.disconnect.rawValue, bytes: [0x7F])
        XCTAssertNotNil(frame)

        mqtt5.didReceive(makeReader(), disconnect: frame!)
        XCTAssertEqual(captured, .normalDisconnection)
    }

    func testAuthFallsBackToSuccessForInvalidReasonCode() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")

        let mqtt5 = CocoaMQTT5(clientID: "mq5-auth-fallback-\(UUID().uuidString)")
        var captured: CocoaMQTTAUTHReasonCode?
        mqtt5.didAuthReasonCode = { _, reason in
            captured = reason
        }

        let frame = FrameAuth(packetFixedHeaderType: FrameType.auth.rawValue, bytes: [0x7F])
        XCTAssertNotNil(frame)

        mqtt5.didReceive(makeReader(), auth: frame!)
        XCTAssertEqual(captured, .success)
    }
}
