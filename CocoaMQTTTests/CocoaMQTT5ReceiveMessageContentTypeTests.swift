import Foundation
import XCTest
@testable import CocoaMQTT

final class CocoaMQTT5ReceiveMessageContentTypeTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false
        var writes: [Data] = []

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
            writes.append(data)
        }
    }

    private func decodePublishFromOutboundFrame(_ publish: FramePublish) -> FramePublish? {
        let packet = publish.bytes(version: "5.0")
        let remainingLength = decodeVariableByteInteger(data: packet, offset: 1)
        let body = [UInt8](packet[remainingLength.newOffset..<packet.count])
        return FramePublish(packetFixedHeaderType: packet[0], bytes: body)
    }

    private func frameType(from data: Data) -> UInt8? {
        guard let firstByte = data.first else {
            return nil
        }
        return firstByte & 0xF0
    }

    func testDidReceiveMessageMapsContentType() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let mqtt5 = CocoaMQTT5(clientID: "mq5-recv-content-type-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil)

        var callbackMessageContentType: String?
        var callbackPublishDataContentType: String?

        mqtt5.didReceiveMessage = { _, message, _, publishData in
            callbackMessageContentType = message.contentType
            callbackPublishDataContentType = publishData?.contentType
        }

        let publishProperties = MqttPublishProperties(contentType: "application/json")
        var outboundPublish = FramePublish(topic: "t/content-type", payload: [0x7B, 0x7D], qos: .qos0)
        outboundPublish.publishProperties = publishProperties
        guard let publish = decodePublishFromOutboundFrame(outboundPublish) else {
            XCTFail("Failed to decode MQTT5 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(callbackPublishDataContentType, "application/json")
        XCTAssertEqual(callbackMessageContentType, "application/json")
    }

    func testDidReceiveMessageKeepsWillPropertiesUnsetForPublishProperties() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let mqtt5 = CocoaMQTT5(clientID: "mq5-recv-properties-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil)

        var callbackMessage: CocoaMQTT5Message?
        var callbackPublishData: MqttDecodePublish?
        mqtt5.didReceiveMessage = { _, message, _, publishData in
            callbackMessage = message
            callbackPublishData = publishData
        }

        let publishProperties = MqttPublishProperties(
            payloadFormatIndicator: .unspecified,
            messageExpiryInterval: 60,
            responseTopic: "t/response",
            correlation: "corr-id",
            userProperty: ["k": "v"]
        )
        var outboundPublish = FramePublish(topic: "t/properties", payload: [0x7B, 0x7D], qos: .qos0)
        outboundPublish.publishProperties = publishProperties
        guard let publish = decodePublishFromOutboundFrame(outboundPublish) else {
            XCTFail("Failed to decode MQTT5 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(callbackPublishData?.payloadFormatIndicator, .unspecified)
        XCTAssertEqual(callbackPublishData?.messageExpiryInterval, 60)
        XCTAssertEqual(callbackPublishData?.responseTopic, "t/response")
        XCTAssertEqual(callbackPublishData?.correlationData, [UInt8]("corr-id".utf8))
        XCTAssertEqual(callbackPublishData?.userProperty?["k"], "v")

        XCTAssertEqual(callbackMessage?.isUTF8EncodedData, true)
        XCTAssertEqual(callbackMessage?.willExpiryInterval, UInt32.max)
        XCTAssertNil(callbackMessage?.willResponseTopic)
        XCTAssertNil(callbackMessage?.willCorrelationData)
        XCTAssertNil(callbackMessage?.willUserProperty)
        XCTAssertNil(callbackMessage?.contentType)
    }

    func testDidReceiveQoS1PublishSendsPuback() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let socket = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: "mq5-recv-qos1-\(UUID().uuidString)", socket: socket)
        let reader = CocoaMQTTReader(socket: socket, delegate: nil)

        var outboundPublish = FramePublish(topic: "t/qos1", payload: [0x31], qos: .qos1, msgid: 42)
        outboundPublish.publishProperties = MqttPublishProperties(contentType: "text/plain")
        guard let publish = decodePublishFromOutboundFrame(outboundPublish) else {
            XCTFail("Failed to decode MQTT5 QoS1 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(socket.writes.count, 1)
        XCTAssertEqual(frameType(from: socket.writes[0]), FrameType.puback.rawValue)
    }

    func testDidReceiveQoS2PublishSendsPubrec() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let socket = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: "mq5-recv-qos2-\(UUID().uuidString)", socket: socket)
        let reader = CocoaMQTTReader(socket: socket, delegate: nil)

        var outboundPublish = FramePublish(topic: "t/qos2", payload: [0x32], qos: .qos2, msgid: 77)
        outboundPublish.publishProperties = MqttPublishProperties(contentType: "text/plain")
        guard let publish = decodePublishFromOutboundFrame(outboundPublish) else {
            XCTFail("Failed to decode MQTT5 QoS2 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(socket.writes.count, 1)
        XCTAssertEqual(frameType(from: socket.writes[0]), FrameType.pubrec.rawValue)
    }

    func testDidReceiveMessageWithContentTypeAndUnspecifiedPayloadFormatKeepsWillPropertiesUnset() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let mqtt5 = CocoaMQTT5(clientID: "mq5-recv-content-type-unspecified-\(UUID().uuidString)")
        let reader = CocoaMQTTReader(socket: SocketSpy(), delegate: nil)

        var callbackMessage: CocoaMQTT5Message?
        var callbackPublishData: MqttDecodePublish?
        mqtt5.didReceiveMessage = { _, message, _, publishData in
            callbackMessage = message
            callbackPublishData = publishData
        }

        let publishProperties = MqttPublishProperties(
            payloadFormatIndicator: .unspecified,
            messageExpiryInterval: 45,
            responseTopic: "t/response",
            correlation: "cid",
            userProperty: ["k2": "v2"],
            contentType: "text/plain"
        )
        var outboundPublish = FramePublish(topic: "t/no-properties", payload: [0x7B, 0x7D], qos: .qos0)
        outboundPublish.publishProperties = publishProperties
        let packet = outboundPublish.bytes(version: "5.0")
        let remainingLength = decodeVariableByteInteger(data: packet, offset: 1)
        let body = [UInt8](packet[remainingLength.newOffset..<packet.count])
        guard let publish = FramePublish(packetFixedHeaderType: packet[0], bytes: body) else {
            XCTFail("Failed to decode MQTT5 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(callbackPublishData?.payloadFormatIndicator, .unspecified)
        XCTAssertEqual(callbackPublishData?.messageExpiryInterval, 45)
        XCTAssertEqual(callbackPublishData?.responseTopic, "t/response")
        XCTAssertEqual(callbackPublishData?.correlationData, [UInt8]("cid".utf8))
        XCTAssertEqual(callbackPublishData?.userProperty?["k2"], "v2")
        XCTAssertEqual(callbackPublishData?.contentType, "text/plain")

        // isUTF8EncodedData is a will-message field (MQTT5 §3.1.3.2.3) that defaults to true;
        // the receive path does not update it from publishRecProperties.payloadFormatIndicator.
        XCTAssertEqual(callbackMessage?.isUTF8EncodedData, true)
        XCTAssertEqual(callbackMessage?.contentType, "text/plain")
        // Will-specific fields must remain at their defaults and not be polluted by received publish properties.
        XCTAssertEqual(callbackMessage?.willExpiryInterval, UInt32.max)
        XCTAssertNil(callbackMessage?.willResponseTopic)
        XCTAssertNil(callbackMessage?.willCorrelationData)
        XCTAssertNil(callbackMessage?.willUserProperty)
    }
}
