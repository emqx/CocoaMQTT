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
        CocoaMQTTStorage()?.setMQTTVersion("5.0")

        let mqtt5 = CocoaMQTT5(clientID: "fallback-disconnect-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil)
        let disconnect = FrameDisconnect(packetFixedHeaderType: FrameType.disconnect.rawValue, bytes: [0xFF])

        var callbackReasonCode: CocoaMQTTDISCONNECTReasonCode?
        mqtt5.didDisconnectReasonCode = { _, reasonCode in
            callbackReasonCode = reasonCode
        }

        XCTAssertNotNil(disconnect)
        mqtt5.didReceive(reader, disconnect: disconnect!)

        XCTAssertEqual(callbackReasonCode, .normalDisconnection)
    }

    func testAuthFallsBackToSuccessForInvalidReasonCode() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")

        let mqtt5 = CocoaMQTT5(clientID: "fallback-auth-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil)
        let auth = FrameAuth(packetFixedHeaderType: FrameType.auth.rawValue, bytes: [0xFF])

        var callbackReasonCode: CocoaMQTTAUTHReasonCode?
        mqtt5.didAuthReasonCode = { _, reasonCode in
            callbackReasonCode = reasonCode
        }

        XCTAssertNotNil(auth)
        mqtt5.didReceive(reader, auth: auth!)

        XCTAssertEqual(callbackReasonCode, .success)
    }
}
