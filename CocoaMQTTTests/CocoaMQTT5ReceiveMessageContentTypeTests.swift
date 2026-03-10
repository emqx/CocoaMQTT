import Foundation
import XCTest
@testable import CocoaMQTT

final class CocoaMQTT5ReceiveMessageContentTypeTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
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
        let packet = outboundPublish.bytes(version: "5.0")
        let remainingLength = decodeVariableByteInteger(data: packet, offset: 1)
        let body = [UInt8](packet[remainingLength.newOffset..<packet.count])
        guard let publish = FramePublish(packetFixedHeaderType: packet[0], bytes: body) else {
            XCTFail("Failed to decode MQTT5 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(callbackPublishDataContentType, "application/json")
        XCTAssertEqual(callbackMessageContentType, "application/json")
    }

    func testDidReceiveMessageMapsOtherPublishProperties() {
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
            payloadFormatIndicator: .utf8,
            messageExpiryInterval: 60,
            responseTopic: "t/response",
            correlation: "corr-id",
            userProperty: ["k": "v"],
            contentType: "application/json"
        )
        var outboundPublish = FramePublish(topic: "t/properties", payload: [0x7B, 0x7D], qos: .qos0)
        outboundPublish.publishProperties = publishProperties
        let packet = outboundPublish.bytes(version: "5.0")
        let remainingLength = decodeVariableByteInteger(data: packet, offset: 1)
        let body = [UInt8](packet[remainingLength.newOffset..<packet.count])
        guard let publish = FramePublish(packetFixedHeaderType: packet[0], bytes: body) else {
            XCTFail("Failed to decode MQTT5 publish frame")
            return
        }

        mqtt5.didReceive(reader, publish: publish)

        XCTAssertEqual(callbackPublishData?.payloadFormatIndicator, .utf8)
        XCTAssertEqual(callbackPublishData?.messageExpiryInterval, 60)
        XCTAssertEqual(callbackPublishData?.responseTopic, "t/response")
        XCTAssertEqual(callbackPublishData?.correlationData, [UInt8]("corr-id".utf8))
        XCTAssertEqual(callbackPublishData?.userProperty?["k"], "v")

        XCTAssertEqual(callbackMessage?.isUTF8EncodedData, true)
        XCTAssertEqual(callbackMessage?.willExpiryInterval, 60)
        XCTAssertEqual(callbackMessage?.willResponseTopic, "t/response")
        XCTAssertEqual(callbackMessage?.willCorrelationData, [UInt8]("corr-id".utf8))
        XCTAssertEqual(callbackMessage?.willUserProperty?["k"], "v")
    }
}
