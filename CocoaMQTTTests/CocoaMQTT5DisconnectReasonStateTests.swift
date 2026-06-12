import Foundation
import XCTest
@testable import CocoaMQTT

final class CocoaMQTT5DisconnectReasonStateTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false
        private(set) var disconnectCount = 0
        private(set) var writes: [Data] = []

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {
            disconnectCount += 1
        }
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
            writes.append(data)
        }
    }

    private struct DisconnectSnapshot {
        let source: CocoaMQTT5DisconnectReasonSource?
        let reasonCode: CocoaMQTTDISCONNECTReasonCode?
        let error: Error?
    }

    private final class DelegateSpy: NSObject, CocoaMQTT5Delegate {
        private(set) var disconnectSnapshots: [DisconnectSnapshot] = []
        private(set) var receivedDisconnectReasonCodes: [CocoaMQTTDISCONNECTReasonCode] = []

        func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}

        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {
            receivedDisconnectReasonCodes.append(reasonCode)
        }

        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
        func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
        func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}

        func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
            let reason = mqtt5.lastDisconnectReason
            disconnectSnapshots.append(DisconnectSnapshot(
                source: reason?.source,
                reasonCode: reason?.reasonCode,
                error: err
            ))
        }
    }

    func testManualDisconnectReasonIsReadableInDisconnectCallback() {
        let socket = SocketSpy()
        let delegate = DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "manual-disconnect-reason-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate

        mqtt5.disconnect()

        XCTAssertNil(mqtt5.lastDisconnectReason)
        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertTrue(socket.writes.contains { $0.first == FrameType.disconnect.rawValue })

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(delegate.disconnectSnapshots.count, 1)
        XCTAssertEqual(delegate.disconnectSnapshots[0].source, .local)
        XCTAssertEqual(delegate.disconnectSnapshots[0].reasonCode, .normalDisconnection)
        XCTAssertNil(delegate.disconnectSnapshots[0].error)
        XCTAssertEqual(mqtt5.lastDisconnectReason?.source, .local)
        XCTAssertEqual(mqtt5.lastDisconnectReason?.reasonCode, .normalDisconnection)
    }

    func testCustomManualDisconnectReasonIsReadableInDisconnectCallback() {
        let socket = SocketSpy()
        let delegate = DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "manual-custom-disconnect-reason-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate

        mqtt5.disconnect(reasonCode: .disconnectWithWillMessage, userProperties: ["reason": "manual"])
        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(delegate.disconnectSnapshots.count, 1)
        XCTAssertEqual(delegate.disconnectSnapshots[0].source, .local)
        XCTAssertEqual(delegate.disconnectSnapshots[0].reasonCode, .disconnectWithWillMessage)
        XCTAssertNil(delegate.disconnectSnapshots[0].error)
    }

    func testManualDisconnectWithSocketErrorDoesNotReportLocalReason() {
        let socket = SocketSpy()
        let delegate = DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "manual-disconnect-error-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate

        mqtt5.disconnect()
        mqtt5.socketDidDisconnect(socket, withError: CocoaMQTTError.writeTimeout)

        XCTAssertEqual(delegate.disconnectSnapshots.count, 1)
        XCTAssertNil(delegate.disconnectSnapshots[0].source)
        XCTAssertNil(delegate.disconnectSnapshots[0].reasonCode)
        XCTAssertNotNil(delegate.disconnectSnapshots[0].error)
        XCTAssertNil(mqtt5.lastDisconnectReason)
    }

    func testRemoteDisconnectReasonIsReadableInDisconnectCallback() {
        let socket = SocketSpy()
        let delegate = DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "remote-disconnect-reason-\(UUID().uuidString)", socket: socket)
        let reader = CocoaMQTTReader(socket: socket, delegate: nil)
        let frame = FrameDisconnect(
            packetFixedHeaderType: FrameType.disconnect.rawValue,
            bytes: [CocoaMQTTDISCONNECTReasonCode.serverBusy.rawValue]
        )
        mqtt5.delegate = delegate

        XCTAssertNotNil(frame)

        mqtt5.didReceive(reader, disconnect: frame!)
        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(delegate.receivedDisconnectReasonCodes, [.serverBusy])
        XCTAssertEqual(delegate.disconnectSnapshots.count, 1)
        XCTAssertEqual(delegate.disconnectSnapshots[0].source, .remote)
        XCTAssertEqual(delegate.disconnectSnapshots[0].reasonCode, .serverBusy)
        XCTAssertNil(delegate.disconnectSnapshots[0].error)
        XCTAssertEqual(mqtt5.lastDisconnectReason?.source, .remote)
        XCTAssertEqual(mqtt5.lastDisconnectReason?.reasonCode, .serverBusy)
    }

    func testRemoteDisconnectWithSocketErrorDoesNotReportFinalReason() {
        let socket = SocketSpy()
        let delegate = DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "remote-disconnect-error-\(UUID().uuidString)", socket: socket)
        let reader = CocoaMQTTReader(socket: socket, delegate: nil)
        let frame = FrameDisconnect(
            packetFixedHeaderType: FrameType.disconnect.rawValue,
            bytes: [CocoaMQTTDISCONNECTReasonCode.serverBusy.rawValue]
        )
        mqtt5.delegate = delegate

        XCTAssertNotNil(frame)

        mqtt5.didReceive(reader, disconnect: frame!)
        mqtt5.socketDidDisconnect(socket, withError: CocoaMQTTError.readTimeout)

        XCTAssertEqual(delegate.receivedDisconnectReasonCodes, [.serverBusy])
        XCTAssertEqual(delegate.disconnectSnapshots.count, 1)
        XCTAssertNil(delegate.disconnectSnapshots[0].source)
        XCTAssertNil(delegate.disconnectSnapshots[0].reasonCode)
        XCTAssertNotNil(delegate.disconnectSnapshots[0].error)
        XCTAssertNil(mqtt5.lastDisconnectReason)
    }

    func testCleanSocketCloseWithoutMQTTReasonClearsDisconnectReason() {
        let socket = SocketSpy()
        let delegate = DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "clean-close-no-reason-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(delegate.disconnectSnapshots.count, 1)
        XCTAssertNil(delegate.disconnectSnapshots[0].source)
        XCTAssertNil(delegate.disconnectSnapshots[0].reasonCode)
        XCTAssertNil(delegate.disconnectSnapshots[0].error)
        XCTAssertNil(mqtt5.lastDisconnectReason)
    }
}
