import Foundation
import XCTest
@testable import CocoaMQTT

final class AutoReconnectStateTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false
        private(set) weak var delegate: CocoaMQTTSocketDelegate?
        private(set) var connectCount = 0
        private(set) var disconnectCount = 0
        private(set) var writes: [Data] = []

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
            delegate = theDelegate
        }

        func connect(toHost host: String, onPort port: UInt16) throws {
            connectCount += 1
        }

        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {
            connectCount += 1
        }

        func disconnect() {
            disconnectCount += 1
        }

        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
            writes.append(data)
        }
    }

    private struct ReconnectSchedule: Equatable {
        let attemptCount: UInt
        let interval: UInt16
    }

    private final class MQTTDelegateSpy: NSObject, CocoaMQTTDelegate {
        private(set) var reconnectSchedules: [ReconnectSchedule] = []
        private(set) var connectAcks: [CocoaMQTTConnAck] = []
        var onConnectAck: ((CocoaMQTT, CocoaMQTTConnAck) -> Void)?

        func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
            connectAcks.append(ack)
            onConnectAck?(mqtt, ack)
        }
        func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
        func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
        func mqttDidPing(_ mqtt: CocoaMQTT) {}
        func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
        func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {}

        func mqtt(_ mqtt: CocoaMQTT, didScheduleReconnect attemptCount: UInt, after interval: UInt16) {
            reconnectSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }
    }

    private final class MQTT5DelegateSpy: NSObject, CocoaMQTT5Delegate {
        private(set) var reconnectSchedules: [ReconnectSchedule] = []
        private(set) var connectAcks: [CocoaMQTTCONNACKReasonCode] = []
        var onConnectAck: ((CocoaMQTT5, CocoaMQTTCONNACKReasonCode) -> Void)?

        func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
            connectAcks.append(ack)
            onConnectAck?(mqtt5, ack)
        }
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
        func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
        func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}
        func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {}

        func mqtt5(_ mqtt5: CocoaMQTT5, didScheduleReconnect attemptCount: UInt, after interval: UInt16) {
            reconnectSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            usleep(10_000)
        }
        return condition()
    }

    private func containsDisconnectFrame(_ writes: [Data]) -> Bool {
        writes.contains { data in
            data.first == FrameType.disconnect.rawValue
        }
    }

    private func connectFrameBytes(clientID: String, username: String, password: String, version: String) -> Data {
        var frame = FrameConnect(clientID: clientID)
        frame.keepAlive = 60
        frame.username = username
        frame.password = password
        frame.cleansess = true

        return Data(frame.bytes(version: version))
    }

    func testCocoaMQTTExposesReconnectIntervalAndAttemptCount() {
        let socket = SocketSpy()
        let delegate = MQTTDelegateSpy()
        let mqtt = CocoaMQTT(clientID: "reconnect-state-\(UUID().uuidString)", socket: socket)
        mqtt.delegate = delegate
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1
        mqtt.maxAutoReconnectTimeInterval = 3

        var closureSchedules: [ReconnectSchedule] = []
        mqtt.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.reconnectTimeInterval, 1)
        XCTAssertEqual(mqtt.reconnectAttemptCount, 1)
        XCTAssertEqual(delegate.reconnectSchedules, [ReconnectSchedule(attemptCount: 1, interval: 1)])
        XCTAssertEqual(closureSchedules, [ReconnectSchedule(attemptCount: 1, interval: 1)])

        XCTAssertTrue(waitUntil { socket.connectCount == 1 })
        XCTAssertEqual(mqtt.reconnectTimeInterval, 2)

        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.reconnectTimeInterval, 2)
        XCTAssertEqual(mqtt.reconnectAttemptCount, 2)
        XCTAssertEqual(delegate.reconnectSchedules, [
            ReconnectSchedule(attemptCount: 1, interval: 1),
            ReconnectSchedule(attemptCount: 2, interval: 2)
        ])
        XCTAssertEqual(closureSchedules, delegate.reconnectSchedules)

        XCTAssertTrue(waitUntil(timeout: 3) { socket.connectCount == 2 })
        XCTAssertEqual(mqtt.reconnectTimeInterval, 3)

        mqtt.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: FrameConnAck(returnCode: .accept))

        XCTAssertEqual(mqtt.reconnectTimeInterval, 0)
        XCTAssertEqual(mqtt.reconnectAttemptCount, 0)
    }

    func testCocoaMQTTDoesNotScheduleReconnectWhenDisabledInDisconnectCallback() {
        let socket = SocketSpy()
        let delegate = MQTTDelegateSpy()
        let mqtt = CocoaMQTT(clientID: "reconnect-disable-\(UUID().uuidString)", socket: socket)
        mqtt.delegate = delegate
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1

        var closureSchedules: [ReconnectSchedule] = []
        mqtt.didDisconnect = { mqtt, _ in
            mqtt.autoReconnect = false
        }
        mqtt.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.reconnectTimeInterval, 0)
        XCTAssertEqual(mqtt.reconnectAttemptCount, 0)
        XCTAssertTrue(delegate.reconnectSchedules.isEmpty)
        XCTAssertTrue(closureSchedules.isEmpty)
        XCTAssertEqual(socket.connectCount, 0)
    }

    func testCocoaMQTTConnackFailureKeepsAutoReconnectEnabled() {
        let socket = SocketSpy()
        let delegate = MQTTDelegateSpy()
        let mqtt = CocoaMQTT(clientID: "connack-failure-reconnect-\(UUID().uuidString)", socket: socket)
        mqtt.delegate = delegate
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1

        var closureAcks: [CocoaMQTTConnAck] = []
        var closureSchedules: [ReconnectSchedule] = []
        mqtt.didConnectAck = { _, ack in
            closureAcks.append(ack)
        }
        mqtt.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: FrameConnAck(returnCode: .serverUnavailable))

        XCTAssertEqual(delegate.connectAcks, [.serverUnavailable])
        XCTAssertEqual(closureAcks, [.serverUnavailable])
        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertFalse(containsDisconnectFrame(socket.writes))

        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.reconnectTimeInterval, 1)
        XCTAssertEqual(mqtt.reconnectAttemptCount, 1)
        XCTAssertEqual(delegate.reconnectSchedules, [ReconnectSchedule(attemptCount: 1, interval: 1)])
        XCTAssertEqual(closureSchedules, delegate.reconnectSchedules)
        XCTAssertTrue(waitUntil { socket.connectCount == 1 })
    }

    func testCocoaMQTTAuthFailureCanRefreshCredentialsBeforeAutoReconnectAttempt() {
        let socket = SocketSpy()
        let delegate = MQTTDelegateSpy()
        let clientID = "auth-refresh-reconnect-\(UUID().uuidString)"
        let mqtt = CocoaMQTT(clientID: clientID, socket: socket)
        mqtt.delegate = delegate
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1
        mqtt.username = "expired-user"
        mqtt.password = "expired-password"

        delegate.onConnectAck = { mqtt, ack in
            guard ack == .badUsernameOrPassword else { return }
            mqtt.username = "fresh-user"
            mqtt.password = "fresh-password"
        }

        mqtt.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: FrameConnAck(returnCode: .badUsernameOrPassword))

        XCTAssertEqual(delegate.connectAcks, [.badUsernameOrPassword])
        XCTAssertEqual(mqtt.username, "fresh-user")
        XCTAssertEqual(mqtt.password, "fresh-password")
        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertFalse(containsDisconnectFrame(socket.writes))

        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.reconnectTimeInterval, 1)
        XCTAssertEqual(mqtt.reconnectAttemptCount, 1)
        XCTAssertTrue(waitUntil { socket.connectCount == 1 })

        mqtt.socketConnected(socket)

        XCTAssertEqual(socket.writes.last, connectFrameBytes(
            clientID: clientID,
            username: "fresh-user",
            password: "fresh-password",
            version: "3.1.1"
        ))
    }

    func testCocoaMQTT5ExposesReconnectIntervalAndAttemptCount() {
        let socket = SocketSpy()
        let delegate = MQTT5DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "reconnect-state-5-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate
        mqtt5.autoReconnect = true
        mqtt5.autoReconnectTimeInterval = 1
        mqtt5.maxAutoReconnectTimeInterval = 3

        var closureSchedules: [ReconnectSchedule] = []
        mqtt5.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt5.reconnectTimeInterval, 1)
        XCTAssertEqual(mqtt5.reconnectAttemptCount, 1)
        XCTAssertEqual(delegate.reconnectSchedules, [ReconnectSchedule(attemptCount: 1, interval: 1)])
        XCTAssertEqual(closureSchedules, [ReconnectSchedule(attemptCount: 1, interval: 1)])

        XCTAssertTrue(waitUntil { socket.connectCount == 1 })
        XCTAssertEqual(mqtt5.reconnectTimeInterval, 2)

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt5.reconnectTimeInterval, 2)
        XCTAssertEqual(mqtt5.reconnectAttemptCount, 2)
        XCTAssertEqual(delegate.reconnectSchedules, [
            ReconnectSchedule(attemptCount: 1, interval: 1),
            ReconnectSchedule(attemptCount: 2, interval: 2)
        ])
        XCTAssertEqual(closureSchedules, delegate.reconnectSchedules)

        XCTAssertTrue(waitUntil(timeout: 3) { socket.connectCount == 2 })
        XCTAssertEqual(mqtt5.reconnectTimeInterval, 3)

        mqtt5.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: FrameConnAck(code: .success))

        XCTAssertEqual(mqtt5.reconnectTimeInterval, 0)
        XCTAssertEqual(mqtt5.reconnectAttemptCount, 0)
    }

    func testCocoaMQTT5DoesNotScheduleReconnectWhenDisabledInDisconnectCallback() {
        let socket = SocketSpy()
        let delegate = MQTT5DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "reconnect-disable-5-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate
        mqtt5.autoReconnect = true
        mqtt5.autoReconnectTimeInterval = 1

        var closureSchedules: [ReconnectSchedule] = []
        mqtt5.didDisconnect = { mqtt5, _ in
            mqtt5.autoReconnect = false
        }
        mqtt5.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt5.reconnectTimeInterval, 0)
        XCTAssertEqual(mqtt5.reconnectAttemptCount, 0)
        XCTAssertTrue(delegate.reconnectSchedules.isEmpty)
        XCTAssertTrue(closureSchedules.isEmpty)
        XCTAssertEqual(socket.connectCount, 0)
    }

    func testCocoaMQTT5ConnackFailureKeepsAutoReconnectEnabled() {
        let socket = SocketSpy()
        let delegate = MQTT5DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "connack-failure-reconnect-5-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate
        mqtt5.autoReconnect = true
        mqtt5.autoReconnectTimeInterval = 1

        var closureAcks: [CocoaMQTTCONNACKReasonCode] = []
        var closureSchedules: [ReconnectSchedule] = []
        mqtt5.didConnectAck = { _, ack, _ in
            closureAcks.append(ack)
        }
        mqtt5.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt5.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: FrameConnAck(code: .serverBusy))

        XCTAssertEqual(delegate.connectAcks, [.serverBusy])
        XCTAssertEqual(closureAcks, [.serverBusy])
        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertFalse(containsDisconnectFrame(socket.writes))

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt5.reconnectTimeInterval, 1)
        XCTAssertEqual(mqtt5.reconnectAttemptCount, 1)
        XCTAssertEqual(delegate.reconnectSchedules, [ReconnectSchedule(attemptCount: 1, interval: 1)])
        XCTAssertEqual(closureSchedules, delegate.reconnectSchedules)
        XCTAssertTrue(waitUntil { socket.connectCount == 1 })
    }

    func testCocoaMQTT5AuthFailureCanRefreshCredentialsBeforeAutoReconnectAttempt() {
        let socket = SocketSpy()
        let delegate = MQTT5DelegateSpy()
        let clientID = "auth-refresh-reconnect-5-\(UUID().uuidString)"
        let mqtt5 = CocoaMQTT5(clientID: clientID, socket: socket)
        mqtt5.delegate = delegate
        mqtt5.autoReconnect = true
        mqtt5.autoReconnectTimeInterval = 1
        mqtt5.username = "expired-user"
        mqtt5.password = "expired-password"

        delegate.onConnectAck = { mqtt5, ack in
            guard ack == .notAuthorized else { return }
            mqtt5.username = "fresh-user"
            mqtt5.password = "fresh-password"
        }

        mqtt5.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: FrameConnAck(code: .notAuthorized))

        XCTAssertEqual(delegate.connectAcks, [.notAuthorized])
        XCTAssertEqual(mqtt5.username, "fresh-user")
        XCTAssertEqual(mqtt5.password, "fresh-password")
        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertFalse(containsDisconnectFrame(socket.writes))

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt5.reconnectTimeInterval, 1)
        XCTAssertEqual(mqtt5.reconnectAttemptCount, 1)
        XCTAssertTrue(waitUntil { socket.connectCount == 1 })

        mqtt5.socketConnected(socket)

        XCTAssertEqual(socket.writes.last, connectFrameBytes(
            clientID: clientID,
            username: "fresh-user",
            password: "fresh-password",
            version: "5.0"
        ))
    }
}
