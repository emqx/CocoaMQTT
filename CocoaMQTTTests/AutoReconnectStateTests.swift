import Foundation
import XCTest
@testable import CocoaMQTT

final class AutoReconnectStateTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false
        private(set) weak var delegate: CocoaMQTTSocketDelegate?
        private(set) var connectCount = 0
        private(set) var disconnectCount = 0

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
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    private struct ReconnectSchedule: Equatable {
        let attemptCount: UInt
        let interval: UInt16
    }

    private final class MQTTDelegateSpy: NSObject, CocoaMQTTDelegate {
        private(set) var reconnectSchedules: [ReconnectSchedule] = []

        func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {}
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

        func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {}
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

    func testCocoaMQTTExposesReconnectIntervalAndAttemptCount() {
        let socket = SocketSpy()
        let delegate = MQTTDelegateSpy()
        let mqtt = CocoaMQTT(clientID: "reconnect-state-\(UUID().uuidString)", socket: socket)
        mqtt.delegate = delegate
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1
        mqtt.maxAutoReconnectTimeInterval = 3

        var observedInterval: UInt16?
        var observedAttemptCount: UInt?
        var closureSchedules: [ReconnectSchedule] = []
        mqtt.didDisconnect = { mqtt, _ in
            observedInterval = mqtt.reconnectTimeInterval
            observedAttemptCount = mqtt.reconnectAttemptCount
        }
        mqtt.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(observedInterval, 1)
        XCTAssertEqual(observedAttemptCount, 1)
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

    func testCocoaMQTT5ExposesReconnectIntervalAndAttemptCount() {
        let socket = SocketSpy()
        let delegate = MQTT5DelegateSpy()
        let mqtt5 = CocoaMQTT5(clientID: "reconnect-state-5-\(UUID().uuidString)", socket: socket)
        mqtt5.delegate = delegate
        mqtt5.autoReconnect = true
        mqtt5.autoReconnectTimeInterval = 1
        mqtt5.maxAutoReconnectTimeInterval = 3

        var observedInterval: UInt16?
        var observedAttemptCount: UInt?
        var closureSchedules: [ReconnectSchedule] = []
        mqtt5.didDisconnect = { mqtt5, _ in
            observedInterval = mqtt5.reconnectTimeInterval
            observedAttemptCount = mqtt5.reconnectAttemptCount
        }
        mqtt5.didScheduleReconnect = { _, attemptCount, interval in
            closureSchedules.append(ReconnectSchedule(attemptCount: attemptCount, interval: interval))
        }

        mqtt5.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(observedInterval, 1)
        XCTAssertEqual(observedAttemptCount, 1)
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
}
