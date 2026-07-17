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

    func testUnexpectedPubAckDoesNotReleaseAnotherMessage() {
        let queue = DispatchQueue(label: "tests.sending-messages.unexpected-puback")
        let mqtt = CocoaMQTT(clientID: "sending-unexpected-puback", socket: SocketSpy())
        mqtt.delegateQueue = queue
        let msgid = mqtt.publish(CocoaMQTTMessage(topic: "t/1", payload: [1], qos: .qos1))
        queue.sync {}

        mqtt.didReceive(
            CocoaMQTTReader(socket: SocketSpy(), delegate: nil),
            puback: FramePubAck(msgid: UInt16(msgid + 1))
        )

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)
        XCTAssertEqual(mqtt.t_reservedPacketIdentifierCount(), 1)
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

        let socket5 = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: clientID5, socket: socket5)
        establishSession(mqtt5, socket: socket5, cleanStart: true, requestedExpiry: 0)
        _ = mqtt5.publish(
            CocoaMQTT5Message(topic: "t/5", payload: [2], qos: .qos1),
            properties: MqttPublishProperties()
        )
        XCTAssertEqual(mqtt5.t_sendingMessagesCount(), 1)

        mqtt5.socketDidDisconnect(socket5, withError: nil)
        XCTAssertEqual(mqtt5.t_sendingMessagesCount(), 0)
        XCTAssertTrue(storage5?.readAll().isEmpty == true)
    }

    func testMQTT5CleanStartWithNonzeroExpiryRetainsSessionAfterDisconnect() {
        let clientID = "clean-start-persistent-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt, socket: socket, cleanStart: true, requestedExpiry: 60)

        _ = mqtt.publish(
            CocoaMQTT5Message(topic: "t/persistent", payload: [1], qos: .qos1),
            properties: MqttPublishProperties()
        )
        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)
    }

    func testMQTT5NoCleanStartWithZeroExpiryDiscardsSessionAfterDisconnect() {
        let clientID = "no-clean-start-expiring-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt, socket: socket, cleanStart: false, requestedExpiry: 0)

        _ = mqtt.publish(
            CocoaMQTT5Message(topic: "t/ephemeral", payload: [1], qos: .qos1),
            properties: MqttPublishProperties()
        )
        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT5ConnAckSessionExpiryOverridesConnectValue() {
        let clientID = "server-expiry-override-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt,
                         socket: socket,
                         cleanStart: false,
                         requestedExpiry: 60,
                         serverExpiry: 0)

        _ = mqtt.publish(
            CocoaMQTT5Message(topic: "t/override", payload: [1], qos: .qos1),
            properties: MqttPublishProperties()
        )
        mqtt.socketDidDisconnect(socket, withError: nil)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT5FiniteSessionExpiryClearsRetainedState() {
        let clientID = "finite-expiry-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt, socket: socket, cleanStart: false, requestedExpiry: 1)

        _ = mqtt.publish(
            CocoaMQTT5Message(topic: "t/expiring", payload: [1], qos: .qos1),
            properties: MqttPublishProperties()
        )
        mqtt.socketDidDisconnect(socket, withError: nil)
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)

        let expired = expectation(description: "session expires")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { expired.fulfill() }
        wait(for: [expired], timeout: 2)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
        XCTAssertTrue(CocoaMQTTStorage(by: clientID, protocolVersion: .v5)?.readAll().isEmpty == true)
    }

    func testMQTT5TopicAliasesAreBoundedAndResolvedPerConnection() throws {
        let clientID = "topic-aliases-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt,
                         socket: socket,
                         cleanStart: true,
                         requestedExpiry: 0,
                         clientTopicAliasMaximum: 2,
                         serverTopicAliasMaximum: 2)

        let outboundProperties = MqttPublishProperties(topicAlias: 1)
        XCTAssertEqual(
            mqtt.publish(CocoaMQTT5Message(topic: "outbound/topic", payload: [1], qos: .qos0),
                         properties: outboundProperties),
            0
        )
        XCTAssertEqual(
            mqtt.publish(CocoaMQTT5Message(topic: "", payload: [2], qos: .qos0),
                         properties: MqttPublishProperties(topicAlias: 1)),
            0
        )
        XCTAssertEqual(
            mqtt.publish(CocoaMQTT5Message(topic: "too/high", payload: [3], qos: .qos0),
                         properties: MqttPublishProperties(topicAlias: 3)),
            -1
        )

        var receivedTopics = [String]()
        mqtt.didReceiveMessage = { _, message, _, _ in receivedTopics.append(message.topic) }
        let first = try XCTUnwrap(FramePublish(
            packetFixedHeaderType: FrameType.publish.rawValue,
            bytes: [0x00, 0x0d] + Array("inbound/topic".utf8) + [0x03, 0x23, 0x00, 0x01],
            protocolVersion: .v5
        ))
        let second = try XCTUnwrap(FramePublish(
            packetFixedHeaderType: FrameType.publish.rawValue,
            bytes: [0x00, 0x00, 0x03, 0x23, 0x00, 0x01],
            protocolVersion: .v5
        ))
        let reader = CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5)
        mqtt.didReceive(reader, publish: first)
        mqtt.didReceive(reader, publish: second)

        XCTAssertEqual(receivedTopics, ["inbound/topic", "inbound/topic"])
    }

    func testMQTT5ClearsTopicAliasesBeforeStartingAnotherConnection() {
        let clientID = "topic-alias-connection-boundary-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let queue = DispatchQueue(label: "tests.topic-alias-connection-boundary")
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        mqtt.delegateQueue = queue
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: 0,
            serverTopicAliasMaximum: 1
        )

        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "aliased/topic", payload: [1], qos: .qos0),
                properties: MqttPublishProperties(topicAlias: 1)
            ),
            0
        )
        mqtt.t_waitUntilDeliverIdle()
        queue.sync {}

        XCTAssertTrue(mqtt.connect())
        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "", payload: [2], qos: .qos0),
                properties: MqttPublishProperties(topicAlias: 1)
            ),
            -1
        )
    }

    func testMQTT5PersistsFullTopicForAliasOnlyPublish() throws {
        let clientID = "topic-alias-persistence-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt,
                         socket: socket,
                         cleanStart: true,
                         requestedExpiry: 60,
                         serverTopicAliasMaximum: 1)

        XCTAssertEqual(
            mqtt.publish(CocoaMQTT5Message(topic: "persisted/topic", payload: [1], qos: .qos0),
                         properties: MqttPublishProperties(topicAlias: 1)),
            0
        )
        let msgid = mqtt.publish(
            CocoaMQTT5Message(topic: "", payload: [2], qos: .qos1),
            properties: MqttPublishProperties(topicAlias: 1)
        )

        let stored = try XCTUnwrap(
            CocoaMQTTStorage(by: clientID, protocolVersion: .v5)?
                .readAll()
                .compactMap { $0 as? FramePublish }
                .first { $0.msgid == UInt16(msgid) }
        )
        XCTAssertEqual(stored.topic, "persisted/topic")
        XCTAssertEqual(stored.publishRecProperties?.topicAlias, 1)
    }

    func testMQTT5RestoresPersistedPublishPropertiesWithoutConnectionScopedAlias() throws {
        let clientID = "publish-property-recovery-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let queue = DispatchQueue(label: "tests.publish-property-recovery")
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        mqtt.delegateQueue = queue
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: false,
            requestedExpiry: UInt32.max,
            serverTopicAliasMaximum: 1
        )

        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "persisted/topic", payload: [1], qos: .qos0),
                properties: MqttPublishProperties(topicAlias: 1)
            ),
            0
        )

        let properties = MqttPublishProperties(
            payloadFormatIndicator: .utf8,
            messageExpiryInterval: 123,
            topicAlias: 1,
            responseTopic: "response/topic",
            contentType: "text/plain"
        )
        properties.correlationData = [0x00, 0xff]
        properties.userProperties = [
            CocoaMQTTUserProperty(key: "duplicate", value: "first"),
            CocoaMQTTUserProperty(key: "duplicate", value: "second")
        ]
        XCTAssertGreaterThan(
            mqtt.publish(
                CocoaMQTT5Message(
                    topic: "",
                    payload: Array("payload".utf8),
                    qos: .qos1
                ),
                properties: properties
            ),
            0
        )
        mqtt.t_waitUntilDeliverIdle()
        queue.sync {}

        mqtt.socketDidDisconnect(socket, withError: nil)
        socket.writes.removeAll()
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: false,
            requestedExpiry: UInt32.max,
            sessionPresent: true
        )
        queue.sync {}

        let publishData = try XCTUnwrap(
            socket.writes.first { $0.first.map { $0 & 0xf0 } == FrameType.publish.rawValue }
        )
        let recovered = try XCTUnwrap(mqtt5Publish(from: publishData))
        let recoveredProperties = try XCTUnwrap(recovered.publishRecProperties)
        XCTAssertTrue(recovered.dup)
        XCTAssertEqual(recovered.topic, "persisted/topic")
        XCTAssertEqual(recoveredProperties.payloadFormatIndicator, .utf8)
        XCTAssertEqual(recoveredProperties.messageExpiryInterval, 123)
        XCTAssertNil(recoveredProperties.topicAlias)
        XCTAssertEqual(recoveredProperties.responseTopic, "response/topic")
        XCTAssertEqual(recoveredProperties.correlationData, [0x00, 0xff])
        XCTAssertEqual(recoveredProperties.userProperties, properties.userProperties)
        XCTAssertEqual(recoveredProperties.contentType, "text/plain")
    }

    func testDisconnectReleasesPendingSubscriptionPacketIdentifiers() {
        let mqtt311 = CocoaMQTT(clientID: "pending-requests-311", socket: SocketSpy())
        mqtt311.cleanSession = false
        _ = mqtt311.publish(CocoaMQTTMessage(topic: "publish/311", payload: [1], qos: .qos1))
        mqtt311.subscribe("subscribe/311")
        mqtt311.unsubscribe("unsubscribe/311")
        XCTAssertEqual(mqtt311.t_reservedPacketIdentifierCount(), 3)

        mqtt311.socketDidDisconnect(SocketSpy(), withError: nil)
        XCTAssertEqual(mqtt311.t_reservedPacketIdentifierCount(), 1)

        let clientID = "pending-requests-5-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(mqtt5, socket: socket, cleanStart: false, requestedExpiry: 60)
        _ = mqtt5.publish(
            CocoaMQTT5Message(topic: "publish/5", payload: [1], qos: .qos1),
            properties: MqttPublishProperties()
        )
        mqtt5.subscribe("subscribe/5")
        mqtt5.unsubscribe("unsubscribe/5")
        XCTAssertEqual(mqtt5.t_reservedPacketIdentifierCount(), 3)

        mqtt5.socketDidDisconnect(socket, withError: nil)
        XCTAssertEqual(mqtt5.t_reservedPacketIdentifierCount(), 1)
    }

    func testMQTT5FailedUnsubscribeKeepsLocalSubscription() throws {
        let mqtt = CocoaMQTT5(clientID: "failed-unsubscribe", socket: SocketSpy())
        mqtt.subscriptions["keep/topic"] = .qos1
        mqtt.subscriptions["remove/topic"] = .qos1
        mqtt.unsubscribe([
            MqttSubscription(topic: "keep/topic", qos: .qos1),
            MqttSubscription(topic: "remove/topic", qos: .qos1)
        ])

        let unsuback = try XCTUnwrap(FrameUnsubAck(
            packetFixedHeaderType: FrameType.unsuback.rawValue,
            bytes: [0x00, 0x01, 0x00,
                    CocoaMQTTUNSUBACKReasonCode.notAuthorized.rawValue,
                    CocoaMQTTUNSUBACKReasonCode.success.rawValue],
            protocolVersion: .v5
        ))
        mqtt.didReceive(
            CocoaMQTTReader(socket: SocketSpy(), delegate: nil, protocolVersion: .v5),
            unsuback: unsuback
        )

        XCTAssertEqual(mqtt.subscriptions["keep/topic"], .qos1)
        XCTAssertNil(mqtt.subscriptions["remove/topic"])
    }

    func testPersistentSessionTerminalDisconnectKeepsMessagesForResume() {
        let mqtt = CocoaMQTT(clientID: "terminal-persistent", socket: SocketSpy())
        mqtt.cleanSession = false
        _ = mqtt.publish(CocoaMQTTMessage(topic: "t/persistent", payload: [1], qos: .qos1))

        mqtt.socketDidDisconnect(SocketSpy(), withError: nil)

        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 1)
    }

    func testIncomingQoS2PublishIsDeliveredExactlyOnceAndPersistsUntilPubrel() throws {
        let clientID = "incoming-qos2-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        var delivered = [CocoaMQTT5Message]()
        mqtt.didReceiveMessage = { _, message, _, _ in delivered.append(message) }
        let reader = CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5)
        let publish = try XCTUnwrap(FramePublish(
            packetFixedHeaderType: FrameType.publish.rawValue | 0x04,
            bytes: [0x00, 0x01, 0x74, 0x00, 0x2a, 0x00, 0x01],
            protocolVersion: .v5
        ))

        mqtt.didReceive(reader, publish: publish)
        mqtt.didReceive(reader, publish: publish)

        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(
            CocoaMQTTStorage(by: clientID, protocolVersion: .v5)?.receivedQoS2Identifiers(),
            [42]
        )
        XCTAssertEqual(socket.writes.filter { $0.first == FrameType.pubrec.rawValue }.count, 2)

        mqtt.didReceive(reader, pubrel: FramePubRel(msgid: 42))
        XCTAssertTrue(
            CocoaMQTTStorage(by: clientID, protocolVersion: .v5)?.receivedQoS2Identifiers().isEmpty == true
        )
        XCTAssertEqual(socket.writes.last?[4], CocoaMQTTPUBCOMPReasonCode.success.rawValue)

        mqtt.didReceive(reader, pubrel: FramePubRel(msgid: 42))
        XCTAssertEqual(socket.writes.last?[4], CocoaMQTTPUBCOMPReasonCode.packetIdentifierNotFound.rawValue)
    }

    func testMQTT5ReceiveMaximumDoesNotCountQoS2StateFromPreviousConnection() throws {
        let clientID = "incoming-qos2-connection-quota-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let storage = try XCTUnwrap(CocoaMQTTStorage(by: clientID, protocolVersion: .v5))
        XCTAssertTrue(storage.markReceivedQoS2(41))
        XCTAssertTrue(storage.markReceivedQoS2(42))

        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: false,
            requestedExpiry: UInt32.max,
            sessionPresent: true,
            clientReceiveMaximum: 1
        )
        socket.writes.removeAll()
        var deliveredIdentifiers = [UInt16]()
        mqtt.didReceiveMessage = { _, _, identifier, _ in
            deliveredIdentifiers.append(identifier)
        }

        mqtt.didReceive(
            CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5),
            publish: try mqtt5QoS2Publish(identifier: 43)
        )

        XCTAssertEqual(deliveredIdentifiers, [43])
        XCTAssertEqual(socket.writes.filter { $0.first == FrameType.pubrec.rawValue }.count, 1)
        XCTAssertFalse(socket.writes.contains { $0.first == FrameType.disconnect.rawValue })
    }

    func testMQTT5ReceiveMaximumCountsRecoveredQoS2PublishesOnCurrentConnection() throws {
        let clientID = "incoming-qos2-recovered-quota-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let storage = try XCTUnwrap(CocoaMQTTStorage(by: clientID, protocolVersion: .v5))
        XCTAssertTrue(storage.markReceivedQoS2(41))
        XCTAssertTrue(storage.markReceivedQoS2(42))

        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: false,
            requestedExpiry: UInt32.max,
            sessionPresent: true,
            clientReceiveMaximum: 1
        )
        socket.writes.removeAll()
        let reader = CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5)

        mqtt.didReceive(reader, publish: try mqtt5QoS2Publish(identifier: 41))
        mqtt.didReceive(reader, publish: try mqtt5QoS2Publish(identifier: 42))

        XCTAssertEqual(socket.writes.filter { $0.first == FrameType.pubrec.rawValue }.count, 1)
        XCTAssertEqual(socket.writes.last?.first, FrameType.disconnect.rawValue)
        XCTAssertEqual(socket.writes.last?[2], CocoaMQTTDISCONNECTReasonCode.receiveMaximumExceeded.rawValue)
    }

    func testMQTT5PubrelReplenishesCurrentConnectionReceiveMaximum() throws {
        let clientID = "incoming-qos2-replenish-quota-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: UInt32.max,
            clientReceiveMaximum: 1
        )
        socket.writes.removeAll()
        let reader = CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5)

        mqtt.didReceive(reader, publish: try mqtt5QoS2Publish(identifier: 41))
        mqtt.didReceive(reader, pubrel: FramePubRel(msgid: 41))
        mqtt.didReceive(reader, publish: try mqtt5QoS2Publish(identifier: 42))

        XCTAssertEqual(socket.writes.filter { $0.first == FrameType.pubrec.rawValue }.count, 2)
        XCTAssertEqual(socket.writes.filter { $0.first == FrameType.pubcomp.rawValue }.count, 1)
        XCTAssertFalse(socket.writes.contains { $0.first == FrameType.disconnect.rawValue })
    }

    func testMQTT311IncomingQoS2DuplicateIsDeliveredOnce() throws {
        let clientID = "incoming-qos2-311-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: clientID, socket: socket)
        var deliveryCount = 0
        mqtt.didReceiveMessage = { _, _, _ in deliveryCount += 1 }
        let publish = try XCTUnwrap(FramePublish(
            packetFixedHeaderType: FrameType.publish.rawValue | 0x04,
            bytes: [0x00, 0x01, 0x74, 0x00, 0x2a, 0x01],
            protocolVersion: .v311
        ))
        let reader = CocoaMQTTReader(socket: socket, delegate: nil)

        mqtt.didReceive(reader, publish: publish)
        mqtt.didReceive(reader, publish: publish)

        XCTAssertEqual(deliveryCount, 1)
        XCTAssertEqual(socket.writes.filter { $0.first == FrameType.pubrec.rawValue }.count, 2)
        mqtt.didReceive(reader, pubrel: FramePubRel(msgid: 42))
        XCTAssertTrue(
            CocoaMQTTStorage(by: clientID, protocolVersion: .v311)?.receivedQoS2Identifiers().isEmpty == true
        )
    }

    func testMQTT5AppliesAssignedClientIdentifier() throws {
        let assignedClientID = "assigned-\(UUID().uuidString)"
        defer { clearStorage(assignedClientID) }
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: "", socket: socket)
        mqtt.cleanSession = true
        XCTAssertTrue(mqtt.connect())
        mqtt.socketConnected(socket)

        let identifier = Array(assignedClientID.utf8)
        let properties = [CocoaMQTTPropertyName.assignedClientIdentifier.rawValue]
            + UInt16(identifier.count).hlBytes
            + identifier
        let connack = try XCTUnwrap(FrameConnAck(
            packetFixedHeaderType: FrameType.connack.rawValue,
            bytes: [0x00, CocoaMQTTCONNACKReasonCode.success.rawValue]
                + beVariableByteInteger(length: properties.count)
                + properties,
            protocolVersion: .v5
        ))

        mqtt.didReceive(
            CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5),
            connack: connack
        )

        XCTAssertEqual(mqtt.clientID, assignedClientID)
        XCTAssertEqual(mqtt.connState, .connected)
    }

    func testMQTT5EnforcesServerPublishingAndSubscriptionCapabilities() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: "server-capabilities-\(UUID().uuidString)", socket: socket)
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: 0,
            serverMaximumQoS: .qos0,
            serverRetainAvailable: false,
            serverMaximumPacketSize: 16,
            wildcardSubscriptionsAvailable: false,
            subscriptionIdentifiersAvailable: false,
            sharedSubscriptionsAvailable: false
        )
        socket.writes.removeAll()

        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t", payload: [1], qos: .qos1),
                properties: MqttPublishProperties()
            ),
            -1
        )
        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t", payload: [1], qos: .qos0, retained: true),
                properties: MqttPublishProperties()
            ),
            -1
        )
        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t", payload: Array(repeating: 1, count: 32), qos: .qos0),
                properties: MqttPublishProperties()
            ),
            -1
        )

        mqtt.subscribe("t/+")
        mqtt.subscribe([MqttSubscription(topic: "t")], subscriptionIdentifier: 1)
        mqtt.subscribe("$share/workers/t")
        XCTAssertTrue(socket.writes.isEmpty)

        // Maximum QoS limits outbound PUBLISH, not the requested QoS in SUBSCRIBE.
        mqtt.subscribe("t", qos: .qos2)
        XCTAssertEqual(
            socket.writes.filter { $0.first.map { $0 & 0xf0 } == FrameType.subscribe.rawValue }.count,
            1
        )
    }

    func testMQTT5ClearsServerPublishingCapabilitiesAfterDisconnect() {
        let queue = DispatchQueue(label: "tests.disconnected-server-capabilities")
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(
            clientID: "disconnected-server-capabilities-\(UUID().uuidString)",
            socket: socket
        )
        mqtt.delegateQueue = queue
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: 0,
            serverMaximumQoS: .qos0,
            serverRetainAvailable: false,
            serverMaximumPacketSize: 16
        )

        mqtt.socketDidDisconnect(socket, withError: nil)
        socket.writes.removeAll()
        XCTAssertGreaterThan(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t/qos", payload: [1], qos: .qos1),
                properties: MqttPublishProperties()
            ),
            0
        )
        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t/retained", payload: [1], qos: .qos0, retained: true),
                properties: MqttPublishProperties()
            ),
            0
        )
        XCTAssertEqual(
            mqtt.publish(
                CocoaMQTT5Message(
                    topic: "t/large",
                    payload: Array(repeating: 1, count: 32),
                    qos: .qos0
                ),
                properties: MqttPublishProperties()
            ),
            0
        )
        mqtt.t_waitUntilDeliverIdle()
        queue.sync {}
        XCTAssertTrue(
            socket.writes.filter { $0.first.map { $0 & 0xf0 } == FrameType.publish.rawValue }.isEmpty
        )

        establishSession(mqtt, socket: socket, cleanStart: true, requestedExpiry: 0)
        queue.sync {}
        XCTAssertEqual(
            socket.writes.filter { $0.first.map { $0 & 0xf0 } == FrameType.publish.rawValue }.count,
            3
        )
    }

    func testMQTT5ServerReceiveMaximumLimitsConcurrentPublishes() {
        let socket = SocketSpy()
        let queue = DispatchQueue(label: "tests.server-receive-maximum")
        let mqtt = CocoaMQTT5(clientID: "server-receive-maximum-\(UUID().uuidString)", socket: socket)
        mqtt.delegateQueue = queue
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: 0,
            serverReceiveMaximum: 1
        )
        socket.writes.removeAll()

        let first = mqtt.publish(
            CocoaMQTT5Message(topic: "t/1", payload: [1], qos: .qos1),
            properties: MqttPublishProperties()
        )
        _ = mqtt.publish(
            CocoaMQTT5Message(topic: "t/2", payload: [2], qos: .qos1),
            properties: MqttPublishProperties()
        )
        queue.sync {}
        XCTAssertEqual(socket.writes.filter { $0.first.map { $0 & 0xf0 } == FrameType.publish.rawValue }.count, 1)

        mqtt.didReceive(
            CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5),
            puback: FramePubAck(msgid: UInt16(first), reasonCode: .success)
        )
        queue.sync {}
        XCTAssertEqual(socket.writes.filter { $0.first.map { $0 & 0xf0 } == FrameType.publish.rawValue }.count, 2)
    }

    func testMQTT5AppliesServerCapabilitiesToPublishQueuedBeforeConnack() {
        let socket = SocketSpy()
        let queue = DispatchQueue(label: "tests.pre-connack-capabilities")
        let mqtt = CocoaMQTT5(clientID: "pre-connack-capabilities-\(UUID().uuidString)", socket: socket)
        mqtt.delegateQueue = queue
        var packetIdentifier = -1
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: 0,
            serverMaximumQoS: .qos0,
            preConnackAction: {
                socket.writes.removeAll()
                packetIdentifier = mqtt.publish(
                    CocoaMQTT5Message(topic: "t/queued", payload: [1], qos: .qos1),
                    properties: MqttPublishProperties()
                )
            }
        )
        queue.sync {}

        XCTAssertGreaterThan(packetIdentifier, 0)
        XCTAssertTrue(socket.writes.filter { $0.first.map { $0 & 0xf0 } == FrameType.publish.rawValue }.isEmpty)
        XCTAssertEqual(mqtt.t_reservedPacketIdentifierCount(), 0)
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
    }

    func testMQTT5PreConnackPublishAvoidsStoredIdentifierAndSendsAfterRecovery() {
        let socket = SocketSpy()
        let queue = DispatchQueue(label: "tests.pre-connack-recovery")
        let clientID = "pre-connack-recovery-\(UUID().uuidString)"
        defer { clearStorage(clientID) }
        let stored = FramePublish(topic: "t/stored", payload: [1], qos: .qos1, msgid: 1)
        XCTAssertTrue(CocoaMQTTStorage(by: clientID, protocolVersion: .v5)?.write(stored) == true)

        let mqtt = CocoaMQTT5(clientID: clientID, socket: socket)
        mqtt.delegateQueue = queue
        var newPacketIdentifier = -1
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: false,
            requestedExpiry: UInt32.max,
            sessionPresent: true,
            preConnackAction: {
                socket.writes.removeAll()
                socket.writeTags.removeAll()
                newPacketIdentifier = mqtt.publish(
                    CocoaMQTT5Message(topic: "t/new", payload: [2], qos: .qos1),
                    properties: MqttPublishProperties()
                )
            }
        )
        queue.sync {}

        XCTAssertEqual(newPacketIdentifier, 2)
        XCTAssertEqual(Set(socket.writeTags.filter { $0 > 0 }), Set([1, 2]))
        XCTAssertEqual(CocoaMQTTStorage(by: clientID, protocolVersion: .v5)?.readAll().count, 2)
        XCTAssertEqual(mqtt.t_reservedPacketIdentifierCount(), 2)
    }

    func testMQTT5UsesServerKeepAlive() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: "server-keepalive-\(UUID().uuidString)", socket: socket)
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: true,
            requestedExpiry: 0,
            serverKeepAlive: 7
        )
        XCTAssertEqual(mqtt.t_keepAliveInterval(), 7)
    }

    func testMQTT5ReusesSessionControllerWhenClientIdentifierCycles() {
        let socket = SocketSpy()
        let firstClientID = "client-a-\(UUID().uuidString)"
        let secondClientID = "client-b-\(UUID().uuidString)"
        let mqtt = CocoaMQTT5(clientID: firstClientID, socket: socket)

        XCTAssertTrue(mqtt.connect())
        mqtt.clientID = secondClientID
        XCTAssertTrue(mqtt.connect())
        mqtt.clientID = firstClientID
        XCTAssertTrue(mqtt.connect())

        XCTAssertEqual(mqtt.t_sessionExpiryControllerCount(), 2)
    }

    func testMQTT5ChangingClientIdentifierPreservesOldStoredSessionWithoutLeakingMemoryState() {
        let socket = SocketSpy()
        let firstClientID = "stored-client-a-\(UUID().uuidString)"
        let secondClientID = "stored-client-b-\(UUID().uuidString)"
        defer {
            clearStorage(firstClientID)
            clearStorage(secondClientID)
        }
        let mqtt = CocoaMQTT5(clientID: firstClientID, socket: socket)
        establishSession(
            mqtt,
            socket: socket,
            cleanStart: false,
            requestedExpiry: UInt32.max
        )
        XCTAssertGreaterThan(
            mqtt.publish(
                CocoaMQTT5Message(topic: "t/a", payload: [1], qos: .qos1),
                properties: MqttPublishProperties()
            ),
            0
        )
        XCTAssertEqual(CocoaMQTTStorage(by: firstClientID, protocolVersion: .v5)?.readAll().count, 1)

        mqtt.socketDidDisconnect(socket, withError: nil)
        mqtt.clientID = secondClientID
        XCTAssertTrue(mqtt.connect())

        XCTAssertEqual(mqtt.t_reservedPacketIdentifierCount(), 0)
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
        XCTAssertEqual(CocoaMQTTStorage(by: firstClientID, protocolVersion: .v5)?.readAll().count, 1)
        XCTAssertTrue(CocoaMQTTStorage(by: secondClientID, protocolVersion: .v5)?.readAll().isEmpty == true)
    }

    func testMQTT311ChangingClientIdentifierPreservesOldStoredSessionWithoutLeakingMemoryState() {
        let socket = SocketSpy()
        let firstClientID = "stored-311-client-a-\(UUID().uuidString)"
        let secondClientID = "stored-311-client-b-\(UUID().uuidString)"
        defer {
            clearStorage(firstClientID)
            clearStorage(secondClientID)
        }
        let mqtt = CocoaMQTT(clientID: firstClientID, socket: socket)
        mqtt.cleanSession = false
        XCTAssertTrue(mqtt.connect())
        mqtt.socketConnected(socket)
        let connack = FrameConnAck(
            packetFixedHeaderType: FrameType.connack.rawValue,
            bytes: [0, CocoaMQTTCONNACKReasonCode.success.rawValue],
            protocolVersion: .v311
        )
        XCTAssertNotNil(connack)
        if let connack = connack {
            mqtt.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: connack)
        }
        XCTAssertGreaterThan(mqtt.publish(CocoaMQTTMessage(topic: "t/a", payload: [1], qos: .qos1)), 0)
        XCTAssertEqual(CocoaMQTTStorage(by: firstClientID, protocolVersion: .v311)?.readAll().count, 1)

        mqtt.socketDidDisconnect(socket, withError: nil)
        mqtt.clientID = secondClientID
        XCTAssertTrue(mqtt.connect())

        XCTAssertEqual(mqtt.t_reservedPacketIdentifierCount(), 0)
        XCTAssertEqual(mqtt.t_sendingMessagesCount(), 0)
        XCTAssertEqual(CocoaMQTTStorage(by: firstClientID, protocolVersion: .v311)?.readAll().count, 1)
        XCTAssertTrue(CocoaMQTTStorage(by: secondClientID, protocolVersion: .v311)?.readAll().isEmpty == true)
    }

    func testMQTT311PublishQueuedBeforeConnackSendsAfterSessionSetup() {
        let socket = SocketSpy()
        let queue = DispatchQueue(label: "tests.pre-connack-311")
        let mqtt = CocoaMQTT(clientID: "pre-connack-311-\(UUID().uuidString)", socket: socket)
        mqtt.delegateQueue = queue
        mqtt.cleanSession = true
        XCTAssertTrue(mqtt.connect())
        mqtt.socketConnected(socket)
        socket.writes.removeAll()
        socket.writeTags.removeAll()

        let packetIdentifier = mqtt.publish(CocoaMQTTMessage(topic: "t/new", payload: [1], qos: .qos1))
        queue.sync {}
        XCTAssertTrue(socket.writes.isEmpty)

        let connack = FrameConnAck(
            packetFixedHeaderType: FrameType.connack.rawValue,
            bytes: [0, CocoaMQTTCONNACKReasonCode.success.rawValue],
            protocolVersion: .v311
        )
        XCTAssertNotNil(connack)
        if let connack = connack {
            mqtt.didReceive(CocoaMQTTReader(socket: socket, delegate: nil), connack: connack)
        }
        queue.sync {}

        XCTAssertGreaterThan(packetIdentifier, 0)
        XCTAssertTrue(socket.writeTags.contains(packetIdentifier))
        XCTAssertEqual(mqtt.t_reservedPacketIdentifierCount(), 1)
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

    private func establishSession(_ mqtt: CocoaMQTT5,
                                  socket: SocketSpy,
                                  cleanStart: Bool,
                                  requestedExpiry: UInt32,
                                  serverExpiry: UInt32? = nil,
                                  sessionPresent: Bool = false,
                                  clientReceiveMaximum: UInt16? = nil,
                                  clientTopicAliasMaximum: UInt16? = nil,
                                  serverTopicAliasMaximum: UInt16? = nil,
                                  serverReceiveMaximum: UInt16? = nil,
                                  serverMaximumQoS: CocoaMQTTQoS? = nil,
                                  serverRetainAvailable: Bool? = nil,
                                  serverMaximumPacketSize: UInt32? = nil,
                                  serverKeepAlive: UInt16? = nil,
                                  wildcardSubscriptionsAvailable: Bool? = nil,
                                  subscriptionIdentifiersAvailable: Bool? = nil,
                                  sharedSubscriptionsAvailable: Bool? = nil,
                                  preConnackAction: (() -> Void)? = nil) {
        let connectProperties = MqttConnectProperties()
        connectProperties.sessionExpiryInterval = requestedExpiry
        connectProperties.receiveMaximum = clientReceiveMaximum
        connectProperties.topicAliasMaximum = clientTopicAliasMaximum
        mqtt.cleanSession = cleanStart
        mqtt.connectProperties = connectProperties
        XCTAssertTrue(mqtt.connect())
        mqtt.socketConnected(socket)
        preConnackAction?()

        var properties = [UInt8]()
        if let serverExpiry = serverExpiry {
            properties.append(CocoaMQTTPropertyName.sessionExpiryInterval.rawValue)
            properties += serverExpiry.byteArrayLittleEndian
        }
        if let serverTopicAliasMaximum = serverTopicAliasMaximum {
            properties.append(CocoaMQTTPropertyName.topicAliasMaximum.rawValue)
            properties += serverTopicAliasMaximum.hlBytes
        }
        if let serverReceiveMaximum = serverReceiveMaximum {
            properties.append(CocoaMQTTPropertyName.receiveMaximum.rawValue)
            properties += serverReceiveMaximum.hlBytes
        }
        if let serverMaximumQoS = serverMaximumQoS {
            properties += [CocoaMQTTPropertyName.maximumQoS.rawValue, serverMaximumQoS.rawValue]
        }
        if let serverRetainAvailable = serverRetainAvailable {
            properties += [CocoaMQTTPropertyName.retainAvailable.rawValue, serverRetainAvailable ? 1 : 0]
        }
        if let serverMaximumPacketSize = serverMaximumPacketSize {
            properties.append(CocoaMQTTPropertyName.maximumPacketSize.rawValue)
            properties += serverMaximumPacketSize.byteArrayLittleEndian
        }
        if let serverKeepAlive = serverKeepAlive {
            properties.append(CocoaMQTTPropertyName.serverKeepAlive.rawValue)
            properties += serverKeepAlive.hlBytes
        }
        if let wildcardSubscriptionsAvailable = wildcardSubscriptionsAvailable {
            properties += [
                CocoaMQTTPropertyName.wildcardSubscriptionAvailable.rawValue,
                wildcardSubscriptionsAvailable ? 1 : 0
            ]
        }
        if let subscriptionIdentifiersAvailable = subscriptionIdentifiersAvailable {
            properties += [
                CocoaMQTTPropertyName.subscriptionIdentifiersAvailable.rawValue,
                subscriptionIdentifiersAvailable ? 1 : 0
            ]
        }
        if let sharedSubscriptionsAvailable = sharedSubscriptionsAvailable {
            properties += [
                CocoaMQTTPropertyName.sharedSubscriptionAvailable.rawValue,
                sharedSubscriptionsAvailable ? 1 : 0
            ]
        }
        let bytes = [sessionPresent ? UInt8(1) : UInt8(0),
                     CocoaMQTTCONNACKReasonCode.success.rawValue]
            + beVariableByteInteger(length: properties.count)
            + properties
        let connack = FrameConnAck(packetFixedHeaderType: FrameType.connack.rawValue,
                                   bytes: bytes,
                                   protocolVersion: .v5)
        XCTAssertNotNil(connack)
        if let connack = connack {
            mqtt.didReceive(CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5),
                            connack: connack)
        }
    }

    private func mqtt5QoS2Publish(identifier: UInt16) throws -> FramePublish {
        return try XCTUnwrap(FramePublish(
            packetFixedHeaderType: FrameType.publish.rawValue | 0x04,
            bytes: [0x00, 0x01, 0x74] + identifier.hlBytes + [0x00, 0x01],
            protocolVersion: .v5
        ))
    }

    private func mqtt5Publish(from data: Data) -> FramePublish? {
        let packet = [UInt8](data)
        guard let fixedHeader = packet.first,
              fixedHeader & 0xf0 == FrameType.publish.rawValue,
              var reader = MQTTByteReader(Array(packet.dropFirst())),
              let remainingLength = reader.readVariableByteInteger(),
              remainingLength == reader.remainingCount,
              let body = reader.readBytes(count: remainingLength) else {
            return nil
        }
        return FramePublish(
            packetFixedHeaderType: fixedHeader,
            bytes: body,
            protocolVersion: .v5
        )
    }
}
