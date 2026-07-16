import Foundation
import XCTest
@testable import CocoaMQTT

final class SendingMessageLifecycleTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL = false
        var writes = [Data]()
        var writeTags = [Int]()
        var onWrite: ((Int) -> Void)?

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
            writes.append(data)
            writeTags.append(tag)
            onWrite?(tag)
        }
    }

    func testMQTT311ReleasesQoS0MessageAfterSending() {
        let queue = DispatchQueue(label: "tests.sending-messages.qos0", attributes: .concurrent)
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "sending-qos0", socket: socket)
        mqtt.delegateQueue = queue
        let published = expectation(description: "QoS 0 message sent")
        mqtt.didPublishMessage = { _, _, _ in published.fulfill() }

        XCTAssertEqual(mqtt.publish(CocoaMQTTMessage(topic: "t/0", payload: [0], qos: .qos0)), 0)
        wait(for: [published], timeout: 1)
        queue.sync {}

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT311KeepsBackToBackQoS0CallbacksAssociatedWithOriginalMessages() {
        let queue = DispatchQueue(label: "tests.sending-messages.qos0-order")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }

        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "sending-qos0-order", socket: socket)
        socket.onWrite = { [weak mqtt, weak socket] tag in
            guard let mqtt, let socket else { return }
            mqtt.socket(socket, didWriteDataWithTag: tag)
        }
        mqtt.delegateQueue = queue
        let published = expectation(description: "Both QoS 0 messages sent")
        published.expectedFulfillmentCount = 2
        var received = [CocoaMQTTMessage]()
        mqtt.didPublishMessage = { _, message, _ in
            received.append(message)
            published.fulfill()
        }

        let first = CocoaMQTTMessage(topic: "t/first", payload: [1], qos: .qos0, retained: true)
        let second = CocoaMQTTMessage(topic: "t/second", payload: [2], qos: .qos0)
        XCTAssertEqual(mqtt.publish(first), 0)
        XCTAssertEqual(mqtt.publish(second), 0)

        gate.signal()
        wait(for: [published], timeout: 1)
        queue.sync {}

        XCTAssertEqual(received.map(\.topic), ["t/first", "t/second"])
        XCTAssertEqual(received.map(\.qos), [.qos0, .qos0])
        XCTAssertEqual(received.map(\.retained), [true, false])
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT5ReleasesQoS0MessageWithoutSocketWriteCompletion() throws {
        let queue = DispatchQueue(label: "tests.sending-messages.qos0-write-completion")
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: "sending-qos0-write-completion", socket: socket)
        mqtt.delegateQueue = queue
        let published = expectation(description: "QoS 0 message handed to socket")
        mqtt.didPublishMessage = { _, _, _ in published.fulfill() }

        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t/0", payload: [0], qos: .qos0),
                properties: MqttPublishProperties()
            ),
            0
        )
        wait(for: [published], timeout: 1)
        queue.sync {}

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
        let writeTag = try XCTUnwrap(socket.writeTags.first)
        mqtt.socket(socket, didWriteDataWithTag: writeTag)
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT311ReleasesQoS1MessageAfterPubAck() {
        let queue = DispatchQueue(label: "tests.sending-messages.qos1")
        let mqtt = CocoaMQTT(clientID: "sending-qos1", socket: SocketSpy())
        mqtt.delegateQueue = queue
        let msgid = mqtt.publish(CocoaMQTTMessage(topic: "t/1", payload: [1], qos: .qos1))
        queue.sync {}

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)

        mqtt.didReceive(
            CocoaMQTTReader(socket: SocketSpy(), delegate: nil),
            puback: FramePubAck(msgid: UInt16(msgid))
        )

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT5KeepsQoS2MessageUntilPubComp() {
        let queue = DispatchQueue(label: "tests.sending-messages.qos2")
        let mqtt = CocoaMQTT5(clientID: "sending-qos2", socket: SocketSpy())
        mqtt.delegateQueue = queue
        let msgid = mqtt.publish(
            CocoaMQTT5Message(topic: "t/2", payload: [2], qos: .qos2),
            properties: MqttPublishProperties()
        )
        queue.sync {}
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil, protocolVersion: .v5)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)

        mqtt.didReceive(reader, pubrec: FramePubRec(msgid: UInt16(msgid), reasonCode: .success))
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)

        mqtt.didReceive(reader, pubcomp: FramePubComp(msgid: UInt16(msgid), reasonCode: .success))
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT5ReleasesQoS2MessageAfterFailedPubRec() {
        let queue = DispatchQueue(label: "tests.sending-messages.failed-pubrec")
        let mqtt = CocoaMQTT5(clientID: "sending-failed-pubrec", socket: SocketSpy())
        mqtt.delegateQueue = queue
        let msgid = mqtt.publish(
            CocoaMQTT5Message(topic: "t/failure", payload: [3], qos: .qos2),
            properties: MqttPublishProperties()
        )
        queue.sync {}

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)

        mqtt.didReceive(
            CocoaMQTTReader(socket: SocketSpy(), delegate: nil, protocolVersion: .v5),
            pubrec: FramePubRec(msgid: UInt16(msgid), reasonCode: .notAuthorized)
        )

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testCleanSessionTerminalDisconnectReleasesMessages() {
        let clientID311 = "terminal-clean-311-\(UUID().uuidString)"
        let clientID5 = "terminal-clean-5-\(UUID().uuidString)"
        defer {
            clearStorage(clientID311)
            clearStorage(clientID5)
        }
        let storage311 = CocoaMQTTStorage(by: clientID311, protocolVersion: .v311)
        let storage5 = CocoaMQTTStorage(by: clientID5, protocolVersion: .v5)
        XCTAssertTrue(storage311?.write(FramePublish(topic: "stored/311", payload: [1], qos: .qos1, msgid: 1)) == true)
        XCTAssertTrue(storage5?.write(FramePublish(topic: "stored/5", payload: [2], qos: .qos1, msgid: 1)) == true)

        let mqtt311 = CocoaMQTT(clientID: clientID311, socket: SocketSpy())
        mqtt311.cleanSession = true
        _ = mqtt311.publish(CocoaMQTTMessage(topic: "t/311", payload: [1], qos: .qos1))
        XCTAssertEqual(mqtt311.t_sendingMessagesCount(), 1)

        mqtt311.socketDidDisconnect(SocketSpy(), withError: nil)
        XCTAssertEqual(mqtt311.t_sendingMessagesCount(), 0)
        XCTAssertTrue(storage311?.readAll().isEmpty == true)

        let mqtt5 = CocoaMQTT5(clientID: clientID5, socket: SocketSpy())
        mqtt5.cleanSession = true
        _ = mqtt5.publish(
            CocoaMQTT5Message(topic: "t/5", payload: [2], qos: .qos1),
            properties: MqttPublishProperties()
        )
        XCTAssertEqual(mqtt5.t_sendingMessagesCount(), 1)

        mqtt5.socketDidDisconnect(SocketSpy(), withError: nil)
        XCTAssertEqual(mqtt5.t_sendingMessagesCount(), 0)
        XCTAssertTrue(storage5?.readAll().isEmpty == true)
    }

    func testPersistentSessionTerminalDisconnectKeepsMessagesForResume() {
        let mqtt = CocoaMQTT(clientID: "terminal-persistent", socket: SocketSpy())
        mqtt.cleanSession = false
        _ = mqtt.publish(CocoaMQTTMessage(topic: "t/persistent", payload: [1], qos: .qos1))

        mqtt.socketDidDisconnect(SocketSpy(), withError: nil)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)
    }

    private func clearStorage(_ clientID: String) {
        guard let defaults = UserDefaults(suiteName: "cocomqtt-\(clientID)") else {
            return
        }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }
}
