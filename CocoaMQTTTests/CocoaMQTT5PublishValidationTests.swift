//
//  CocoaMQTT5PublishValidationTests.swift
//  CocoaMQTTTests
import XCTest
@testable import CocoaMQTT

final class CocoaMQTT5PublishValidationTests: XCTestCase {

    func testPublishKeepsQoSWhenDupIsFalse() {
        let mqtt5 = CocoaMQTT5(clientID: "mq5-qos-\(UUID().uuidString)")
        let properties = MqttPublishProperties()

        let qos1MsgId = mqtt5.publish("t/1", withString: "payload", qos: .qos1, DUP: false, retained: false, properties: properties)
        XCTAssertGreaterThan(qos1MsgId, 0)

        let qos0MsgId = mqtt5.publish("t/0", withString: "payload", qos: .qos0, DUP: false, retained: false, properties: properties)
        XCTAssertEqual(qos0MsgId, 0)
    }

    func testPublishKeepsQoSWhenDupIsTrueAndQoSIsOne() {
        let mqtt5 = CocoaMQTT5(clientID: "mq5-dup-qos1-\(UUID().uuidString)")
        let properties = MqttPublishProperties()

        let msgId = mqtt5.publish("t/1", withString: "payload", qos: .qos1, DUP: true, retained: false, properties: properties)
        XCTAssertGreaterThan(msgId, 0)
    }

    func testPublishRejectsClientSubscriptionIdentifier() {
        let mqtt5 = CocoaMQTT5(clientID: "mq5-subscription-identifier-\(UUID().uuidString)")
        let properties = MqttPublishProperties(subscriptionIdentifier: 1)

        XCTAssertEqual(
            mqtt5.publish("t/1", withString: "payload", properties: properties),
            -1
        )
    }
}
