//
//  MqttDecodePublish.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/27.
//

import Foundation

public class MqttDecodePublish: NSObject {

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
    public var userProperties = [CocoaMQTTUserProperty]()
    // 3.3.2.3.8 Subscription Identifier
    public var subscriptionIdentifier: Int = 0
    public var subscriptionIdentifiers = [Int]()
    // 3.3.2.3.9 Content Type
    public var contentType: String?

    // public var applicationMessage: [UInt8]?

    // 3.3.2.1 Topic Name
    public var topic: String = ""
    // 3.3.2.2 Packet Identifier
    public var packetIdentifier: UInt16?
    public var mqtt5DataIndex = 0

    @discardableResult
    public func decodePublish(fixedHeader: UInt8,
                              publishData: [UInt8],
                              protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        propertyLength = nil
        payloadFormatIndicator = nil
        messageExpiryInterval = nil
        topicAlias = nil
        responseTopic = nil
        correlationData = nil
        userProperty = nil
        userProperties = []
        subscriptionIdentifier = 0
        subscriptionIdentifiers = []
        contentType = nil
        packetIdentifier = nil

        guard fixedHeader & 0xf0 == FrameType.publish.rawValue,
              fixedHeader & 0x06 != 0x06,
              fixedHeader & 0x06 != 0 || fixedHeader & 0x08 == 0,
              var reader = MQTTByteReader(publishData),
              let decodedTopic = reader.readUTF8String(),
              !decodedTopic.contains("+"), !decodedTopic.contains("#"),
              let receivedQoS = CocoaMQTTQoS(rawValue: (fixedHeader & 0b0000_0110) >> 1),
              receivedQoS != .FAILURE else { return false }

        topic = decodedTopic
        if receivedQoS > .qos0 {
            guard let identifier = reader.readUInt16(), identifier != 0 else { return false }
            packetIdentifier = identifier
        }

        guard protocolVersion == .v5 else {
            mqtt5DataIndex = reader.index
            return true
        }

        guard let decodedPropertyLength = reader.readVariableByteInteger(),
              var properties = reader.readSection(length: decodedPropertyLength) else { return false }
        propertyLength = decodedPropertyLength
        mqtt5DataIndex = reader.index - decodedPropertyLength

        var singleUseProperties = Set<CocoaMQTTPropertyName>()
        while !properties.isAtEnd {
            guard let identifier = properties.readVariableByteInteger(),
                  let propertyName = UInt8(exactly: identifier).flatMap(CocoaMQTTPropertyName.init(rawValue:)) else {
                return false
            }

            if propertyName != .userProperty && propertyName != .subscriptionIdentifier {
                guard singleUseProperties.insert(propertyName).inserted else { return false }
            }

            switch propertyName {
            case .payloadFormatIndicator:
                guard let value = properties.readByte(), value <= 1 else { return false }
                payloadFormatIndicator = value == 1 ? .utf8 : .unspecified
            case .willExpiryInterval:
                guard let value = properties.readUInt32() else { return false }
                messageExpiryInterval = value
            case .topicAlias:
                guard let value = properties.readUInt16(), value != 0 else { return false }
                topicAlias = value
            case .responseTopic:
                guard let value = properties.readUTF8String(), !value.isEmpty,
                      !value.contains("+"), !value.contains("#") else { return false }
                responseTopic = value
            case .correlationData:
                guard let value = properties.readBinaryData() else { return false }
                correlationData = value
            case .userProperty:
                guard let key = properties.readUTF8String(),
                      let value = properties.readUTF8String() else { return false }
                if userProperty == nil { userProperty = [:] }
                userProperty?[key] = value
                userProperties.append(CocoaMQTTUserProperty(key: key, value: value))
            case .subscriptionIdentifier:
                guard let value = properties.readVariableByteInteger(), value > 0 else { return false }
                subscriptionIdentifier = value
                subscriptionIdentifiers.append(value)
            case .contentType:
                guard let value = properties.readUTF8String() else { return false }
                contentType = value
            default:
                return false
            }
        }

        return !topic.isEmpty || topicAlias != nil
    }

}
