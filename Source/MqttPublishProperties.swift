//
//  MqttPublishProperties.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/27.
//

import Foundation

public class MqttPublishProperties: NSObject {

    // 3.3.2.3 PUBLISH Properties
    // 3.3.2.3.1 Property Length
    public var propertyLength: Int?
    // 3.3.2.3.2 Payload Format Indicator
    public var payloadFormatIndicator: PayloadFormatIndicator?
    // 3.3.2.3.3 Message Expiry Interval
    public var messageExpiryInterval: UInt32?
    // 3.3.2.3.4 Topic Alias
    public var topicAlias: UInt16?
    // 3.3.2.3.5 Response Topic
    public var responseTopic: String?
    // 3.3.2.3.6 Correlation Data
    public var correlationData: [UInt8]?
    // 3.3.2.3.7 Property
    public var userProperty: [String: String]?
    /// Ordered User Properties. When non-empty, these are encoded instead of `userProperty`.
    public var userProperties = [CocoaMQTTUserProperty]()
    // 3.3.2.3.8 Subscription Identifier
    public var subscriptionIdentifier: UInt32?
    // 3.3.2.3.9 Content Type
    public var contentType: String?

    public init(
        propertyLength: Int? = nil,
        payloadFormatIndicator: PayloadFormatIndicator? = nil,
        messageExpiryInterval: UInt32? = nil,
        topicAlias: UInt16? = nil,
        responseTopic: String? = nil,
        correlation: String? = nil,
        userProperty: [String: String]? = nil,
        subscriptionIdentifier: UInt32? = nil,
        contentType: String? = nil
    ) {
        self.propertyLength = propertyLength
        self.payloadFormatIndicator = payloadFormatIndicator
        self.messageExpiryInterval = messageExpiryInterval
        self.topicAlias = topicAlias
        self.responseTopic = responseTopic
        self.correlationData = correlation.map { Array($0.utf8) }
        self.userProperty = userProperty
        self.subscriptionIdentifier = subscriptionIdentifier
        self.contentType = contentType
    }

    /// Rebuild the properties of an outbound PUBLISH restored from session storage.
    convenience init(recovering decoded: MqttDecodePublish) {
        self.init()
        payloadFormatIndicator = decoded.payloadFormatIndicator
        messageExpiryInterval = decoded.messageExpiryInterval
        responseTopic = decoded.responseTopic
        correlationData = decoded.correlationData
        userProperty = decoded.userProperty
        userProperties = decoded.userProperties
        contentType = decoded.contentType

        // A Topic Alias mapping ends with its network connection. Subscription
        // Identifiers are server-originated and invalid on an outbound PUBLISH.
    }

    public var properties: [UInt8] {
        var properties = [UInt8]()

        // 3.3.2.3.2  Payload Format Indicator
        if let payloadFormatIndicator = self.payloadFormatIndicator {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.payloadFormatIndicator.rawValue, value: [payloadFormatIndicator.rawValue])
        }
        // 3.3.2.3.3  Message Expiry Interval
        if let messageExpiryInterval = self.messageExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.willExpiryInterval.rawValue, value: messageExpiryInterval.byteArrayLittleEndian)
        }
        // 3.3.2.3.4 Topic Alias
        if let topicAlias = self.topicAlias {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.topicAlias.rawValue, value: topicAlias.hlBytes)
        }
        // 3.3.2.3.5 Response Topic
        if let responseTopic = self.responseTopic {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.responseTopic.rawValue, value: responseTopic.bytesWithLength)
        }
        // 3.3.2.3.6 Correlation Data
        if let correlationData = self.correlationData,
           correlationData.count <= Int(UInt16.max) {
            properties += getMQTTPropertyData(
                type: CocoaMQTTPropertyName.correlationData.rawValue,
                value: UInt16(correlationData.count).hlBytes + correlationData
            )
        } else if correlationData != nil {
            printError("Correlation Data exceeds the MQTT binary data limit.")
        }
        // 3.3.2.3.7 Property Length User Property
        if !userProperties.isEmpty {
            properties += userProperties.userPropertyBytes
        } else if let userProperty = self.userProperty {
            properties += userProperty.userPropertyBytes
        }
        // 3.3.2.3.8 Subscription Identifier
        if let subscriptionIdentifier = self.subscriptionIdentifier,
           let subscriptionIdentifier = beVariableByteInteger(subscriptionIdentifier) {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.subscriptionIdentifier.rawValue, value: subscriptionIdentifier)
        }
        // 3.3.2.3.9 Content Type
        if let contentType = self.contentType {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.contentType.rawValue, value: contentType.bytesWithLength)
        }

        return properties
    }

    func isValid(forTopic topic: String, payload: [UInt8]) -> Bool {
        let hasTopic = hasValidMQTTUTF8Length(topic)
        let hasAlias = topic.isEmpty && topicAlias != nil && topicAlias != 0
        let hasValidTopic = hasTopic || hasAlias
        guard hasValidTopic, !topic.contains("+"), !topic.contains("#"),
              topicAlias.map({ $0 != 0 }) ?? true,
              subscriptionIdentifier == nil,
              (correlationData?.count ?? 0) <= Int(UInt16.max),
              hasValidMQTTUserProperties(userProperty),
              hasValidMQTTUserProperties(userProperties) else { return false }

        if let responseTopic = responseTopic {
            guard hasValidMQTTUTF8Length(responseTopic),
                  !responseTopic.contains("+"), !responseTopic.contains("#") else { return false }
        }
        if let contentType = contentType {
            guard hasValidMQTTUTF8Length(contentType, allowEmpty: true) else { return false }
        }
        if payloadFormatIndicator == .utf8 {
            guard String(bytes: payload, encoding: .utf8) != nil else { return false }
        }
        return true
    }
}
