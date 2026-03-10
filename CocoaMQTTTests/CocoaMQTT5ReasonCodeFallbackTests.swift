import Foundation
import XCTest
@testable import CocoaMQTT

final class CocoaMQTT5ReasonCodeFallbackTests: XCTestCase {

    private final class SocketStub: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    override func setUp() {
        super.setUp()
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
    }

    override func tearDown() {
        CocoaMQTTStorage()?.setMQTTVersion("3.1.1")
        super.tearDown()
    }

    func testDisconnectFallsBackToNormalDisconnectionForInvalidReasonCode() {
        let socket = SocketStub()
        let mqtt5 = CocoaMQTT5(clientID: "mq5-disconnect-fallback-\(UUID().uuidString)", socket: socket)
        let reader = CocoaMQTTReader(socket: socket, delegate: mqtt5)

        var callbackReasonCode: CocoaMQTTDISCONNECTReasonCode?
        mqtt5.didDisconnectReasonCode = { _, reasonCode in
            callbackReasonCode = reasonCode
        }

        guard let frame = FrameDisconnect(packetFixedHeaderType: FrameType.disconnect.rawValue, bytes: [0xFF]) else {
            XCTFail("Expected DISCONNECT frame to decode in MQTT5 mode")
            return
        }
        XCTAssertNil(frame.receiveReasonCode)

        mqtt5.didReceive(reader, disconnect: frame)

        XCTAssertEqual(callbackReasonCode, .normalDisconnection)
    }

    func testAuthFallsBackToSuccessForInvalidReasonCode() {
        let socket = SocketStub()
        let mqtt5 = CocoaMQTT5(clientID: "mq5-auth-fallback-\(UUID().uuidString)", socket: socket)
        let reader = CocoaMQTTReader(socket: socket, delegate: mqtt5)

        var callbackReasonCode: CocoaMQTTAUTHReasonCode?
        mqtt5.didAuthReasonCode = { _, reasonCode in
            callbackReasonCode = reasonCode
        }

        guard let frame = FrameAuth(packetFixedHeaderType: FrameType.auth.rawValue, bytes: [0xFF]) else {
            XCTFail("Expected AUTH frame to decode in MQTT5 mode")
            return
        }
        XCTAssertNil(frame.receiveReasonCode)

        mqtt5.didReceive(reader, auth: frame)

        XCTAssertEqual(callbackReasonCode, .success)
    }
}
