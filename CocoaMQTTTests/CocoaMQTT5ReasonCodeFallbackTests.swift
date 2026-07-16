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

    func testDisconnectFallsBackToNormalDisconnectionForInvalidReasonCode() {
        let mqtt5 = CocoaMQTT5(clientID: "mq5-disconnect-fallback-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil, protocolVersion: .v5)
        let frame = FrameDisconnect(packetFixedHeaderType: FrameType.disconnect.rawValue, bytes: [0xFF], protocolVersion: .v5)

        XCTAssertNotNil(frame)
        XCTAssertNil(frame?.receiveReasonCode)

        var receivedReasonCode: CocoaMQTTDISCONNECTReasonCode?
        mqtt5.didDisconnectReasonCode = { _, reasonCode in
            receivedReasonCode = reasonCode
        }

        mqtt5.didReceive(reader, disconnect: frame!)

        XCTAssertEqual(receivedReasonCode, .normalDisconnection)
    }

    func testAuthFallsBackToSuccessForInvalidReasonCode() {
        let mqtt5 = CocoaMQTT5(clientID: "mq5-auth-fallback-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil, protocolVersion: .v5)
        let frame = FrameAuth(packetFixedHeaderType: FrameType.auth.rawValue, bytes: [0xFF], protocolVersion: .v5)

        XCTAssertNotNil(frame)
        XCTAssertNil(frame?.receiveReasonCode)

        var receivedReasonCode: CocoaMQTTAUTHReasonCode?
        mqtt5.didAuthReasonCode = { _, reasonCode in
            receivedReasonCode = reasonCode
        }

        mqtt5.didReceive(reader, auth: frame!)

        XCTAssertEqual(receivedReasonCode, .success)
    }
}
