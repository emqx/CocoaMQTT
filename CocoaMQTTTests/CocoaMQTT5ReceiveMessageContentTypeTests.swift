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
}
