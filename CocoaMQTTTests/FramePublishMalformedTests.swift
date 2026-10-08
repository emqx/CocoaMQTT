//
//  FramePublishMalformedTests.swift
//  CocoaMQTTTests
//
//  Verifies that the MQTT 3.1.1 PUBLISH parser rejects malformed frames by
//  returning nil (never crashing / force-unwrapping), while still parsing
//  well-formed frames correctly. The reader-level guarantee that a nil parse
//  only discards the single frame (instead of disconnecting the socket) is
//  covered by CocoaMQTTReaderProtocolErrorTests.
//

import Foundation
import XCTest
@testable import CocoaMQTT

final class FramePublishMalformedTests: XCTestCase {

    // QoS0 PUBLISH fixed-header type (0x30), QoS1 PUBLISH (0x32).
    private let qos0Header = FrameType.publish.rawValue          // 0x30
    private let qos1Header = FrameType.publish.rawValue | 0x02   // 0x32

    private func topicPrefixed(_ topicBytes: [UInt8]) -> [UInt8] {
        return UInt16(topicBytes.count).hlBytes + topicBytes
    }

    // T1: Valid QoS0 PUBLISH -> non-nil; topic + payload correct, msgid == 0.
    func testValidQoS0PublishParses() throws {
        let topic = Array("a/b".utf8)
        let payload: [UInt8] = [0x68, 0x69] // "hi"
        let bytes = topicPrefixed(topic) + payload

        let frame = try XCTUnwrap(
            FramePublish(packetFixedHeaderType: qos0Header, bytes: bytes, protocolVersion: .v311)
        )
        XCTAssertEqual(frame.topic, "a/b")
        XCTAssertEqual(frame.payload(), payload)
        XCTAssertEqual(frame.msgid, 0)
    }

    // T2: Valid QoS1 PUBLISH -> non-nil; topic, msgid (non-zero), payload parse.
    func testValidQoS1PublishParses() throws {
        let topic = Array("a/b".utf8)
        let msgid: [UInt8] = [0x12, 0x34] // 0x1234
        let payload: [UInt8] = [0x70, 0x71] // "pq"
        let bytes = topicPrefixed(topic) + msgid + payload

        let frame = try XCTUnwrap(
            FramePublish(packetFixedHeaderType: qos1Header, bytes: bytes, protocolVersion: .v311)
        )
        XCTAssertEqual(frame.topic, "a/b")
        XCTAssertEqual(frame.msgid, 0x1234)
        XCTAssertEqual(frame.payload(), payload)
    }

    // T3: Invalid-UTF-8 topic bytes -> returns nil, no crash.
    func testInvalidUTF8TopicReturnsNil() {
        // Topic length 2 with invalid UTF-8 bytes [0xFF, 0xFE].
        let bytes = topicPrefixed([0xFF, 0xFE]) + [0x41]
        let frame = FramePublish(packetFixedHeaderType: qos0Header, bytes: bytes, protocolVersion: .v311)
        XCTAssertNil(frame)
    }

    // T4: Truncated topic (declared length longer than available bytes) -> nil.
    func testTruncatedTopicReturnsNil() {
        // Declared topic length = 10, but only 3 topic bytes present.
        let bytes: [UInt8] = [0x00, 0x0A, 0x61, 0x62, 0x63]
        let frame = FramePublish(packetFixedHeaderType: qos0Header, bytes: bytes, protocolVersion: .v311)
        XCTAssertNil(frame)
    }

    // T5: Truncated message id for QoS1 (topic present, <2 bytes for packet id) -> nil.
    func testTruncatedMessageIdForQoS1ReturnsNil() {
        let topic = Array("a/b".utf8)
        // Only one byte remaining where a 2-byte packet identifier is required.
        let bytes = topicPrefixed(topic) + [0x00]
        let frame = FramePublish(packetFixedHeaderType: qos1Header, bytes: bytes, protocolVersion: .v311)
        XCTAssertNil(frame)
    }

    // T6: Binary (non-UTF-8) payload with a valid UTF-8 topic, QoS0 ->
    //     non-nil; payload preserved byte-for-byte (payload is NOT UTF-8 validated).
    func testBinaryPayloadPreservedForValidTopic() throws {
        let topic = Array("a/b".utf8)
        let payload: [UInt8] = [0xFF, 0x00, 0xFE, 0x80] // not valid UTF-8
        let bytes = topicPrefixed(topic) + payload

        let frame = try XCTUnwrap(
            FramePublish(packetFixedHeaderType: qos0Header, bytes: bytes, protocolVersion: .v311)
        )
        XCTAssertEqual(frame.topic, "a/b")
        XCTAssertEqual(frame.msgid, 0)
        XCTAssertEqual(frame.payload(), payload)
    }
}
