import Foundation
import XCTest
@testable import CocoaMQTT

final class SendingMessageLifecycleTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL = false

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    func testMQTT311ReleasesQoS0MessageAfterSending() {
        let queue = DispatchQueue(label: "tests.sending-messages.qos0", attributes: .concurrent)
        let mqtt = CocoaMQTT(clientID: "sending-qos0", socket: SocketSpy())
        mqtt.delegateQueue = queue
        let published = expectation(description: "QoS 0 message sent")
        mqtt.didPublishMessage = { _, _, _ in published.fulfill() }

        XCTAssertEqual(mqtt.publish(CocoaMQTTMessage(topic: "t/0", payload: [0], qos: .qos0)), 0)
        wait(for: [published], timeout: 1)
        queue.sync {}

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
}
