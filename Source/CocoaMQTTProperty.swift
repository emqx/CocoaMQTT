//
//  CocoaMQTTPropertyType.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/6.
//

import Foundation

/// One MQTT 5 User Property entry. MQTT permits duplicate keys and preserves order.
public struct CocoaMQTTUserProperty: Equatable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum CocoaMQTTPropertyName: UInt8 {
    case payloadFormatIndicator = 0x01
    case willExpiryInterval = 0x02
    case contentType = 0x03
    case responseTopic = 0x08
    case correlationData = 0x09
    case subscriptionIdentifier = 0x0B
    case sessionExpiryInterval = 0x11
    case assignedClientIdentifier = 0x12
    case serverKeepAlive = 0x13
    case authenticationMethod = 0x15
    case authenticationData = 0x16
    case requestProblemInformation = 0x17
    case willDelayInterval = 0x18
    case requestResponseInformation = 0x19
    case responseInformation = 0x1A
    case serverReference = 0x1C
    case reasonString = 0x1F
    case receiveMaximum = 0x21
    case topicAliasMaximum = 0x22
    case topicAlias = 0x23
    case maximumQoS = 0x24
    case retainAvailable = 0x25
    case userProperty = 0x26
    case maximumPacketSize = 0x27
    case wildcardSubscriptionAvailable = 0x28
    case subscriptionIdentifiersAvailable = 0x29
    case sharedSubscriptionAvailable = 0x2A
}

func getMQTTPropertyData(type: UInt8, value: [UInt8]) -> [UInt8] {
    var properties = [UInt8]()
    properties.append(UInt8(type))
    properties += value
    return properties
}

func beVariableByteInteger(length: Int) -> [UInt8] {
    var res = [UInt8]()
    var tmpLen: Int = length
    repeat {
        var d: UInt8 = UInt8(tmpLen % 128)
        tmpLen /= 128
        if tmpLen > 0 {
            d |= 0x80
        }
        res.append(d)
    } while(tmpLen > 0)

    return res
}

func beVariableByteInteger(_ data: UInt32) -> [UInt8]? {
    if data > 0x0fffffff {
        return nil
    }
    return beVariableByteInteger(length: Int(data))
}

/// Bounds-checked reader used for data received from the network.
struct MQTTByteReader {
    private let data: [UInt8]
    private let endIndex: Int
    private(set) var index: Int

    init?(_ data: [UInt8], offset: Int = 0, length: Int? = nil) {
        let end = length.map { offset + $0 } ?? data.count
        guard offset >= 0, end >= offset, end <= data.count else { return nil }
        self.data = data
        self.index = offset
        self.endIndex = end
    }

    var isAtEnd: Bool { index == endIndex }
    var remainingCount: Int { endIndex - index }

    mutating func readByte() -> UInt8? {
        guard index < endIndex else { return nil }
        defer { index += 1 }
        return data[index]
    }

    mutating func readUInt16() -> UInt16? {
        guard let high = readByte(), let low = readByte() else { return nil }
        return UInt16(high) << 8 | UInt16(low)
    }

    mutating func readUInt32() -> UInt32? {
        guard let first = readByte(), let second = readByte(),
              let third = readByte(), let fourth = readByte() else { return nil }
        return UInt32(first) << 24 | UInt32(second) << 16 | UInt32(third) << 8 | UInt32(fourth)
    }

    mutating func readVariableByteInteger() -> Int? {
        var value = 0
        var multiplier = 1

        for byteCount in 1...4 {
            guard let byte = readByte() else { return nil }
            value += Int(byte & 0x7f) * multiplier

            if byte & 0x80 == 0 {
                // MQTT requires the shortest possible representation.
                if byteCount > 1 && value < multiplier {
                    return nil
                }
                return value
            }

            guard byteCount < 4 else { return nil }
            multiplier *= 128
        }
        return nil
    }

    mutating func readBytes(count: Int) -> [UInt8]? {
        guard count >= 0, count <= remainingCount else { return nil }
        let end = index + count
        defer { index = end }
        return Array(data[index..<end])
    }

    mutating func readUTF8String() -> String? {
        guard let length = readUInt16(), let bytes = readBytes(count: Int(length)) else { return nil }
        guard let value = String(bytes: bytes, encoding: .utf8),
              hasValidMQTTUTF8Length(value, allowEmpty: true) else { return nil }
        return value
    }

    mutating func readBinaryData() -> [UInt8]? {
        guard let length = readUInt16() else { return nil }
        return readBytes(count: Int(length))
    }

    mutating func readSection(length: Int) -> MQTTByteReader? {
        guard length >= 0, length <= remainingCount,
              let section = MQTTByteReader(data, offset: index, length: length) else { return nil }
        index += length
        return section
    }
}

struct MQTTAcknowledgementData {
    let msgid: UInt16
    let reasonCode: UInt8
    let propertyLength: Int
    let reasonString: String?
    let userProperty: [String: String]?
    let userProperties: [CocoaMQTTUserProperty]
}

private struct MQTTReasonStringAndUserProperties {
    let reasonString: String?
    let userProperty: [String: String]?
    let userProperties: [CocoaMQTTUserProperty]
}

private func decodeReasonStringAndUserProperties(
    _ properties: inout MQTTByteReader
) -> MQTTReasonStringAndUserProperties? {
    var reasonString: String?
    var userProperty: [String: String]?
    var userProperties = [CocoaMQTTUserProperty]()
    while !properties.isAtEnd {
        guard let propertyIdentifier = properties.readVariableByteInteger(),
              let propertyName = UInt8(exactly: propertyIdentifier).flatMap(CocoaMQTTPropertyName.init(rawValue:)) else {
            return nil
        }
        switch propertyName {
        case .reasonString:
            guard reasonString == nil, let value = properties.readUTF8String() else { return nil }
            reasonString = value
        case .userProperty:
            guard let key = properties.readUTF8String(),
                  let value = properties.readUTF8String() else { return nil }
            if userProperty == nil { userProperty = [:] }
            userProperty?[key] = value
            userProperties.append(CocoaMQTTUserProperty(key: key, value: value))
        default:
            return nil
        }
    }
    return MQTTReasonStringAndUserProperties(
        reasonString: reasonString,
        userProperty: userProperty,
        userProperties: userProperties
    )
}

func decodeAcknowledgement(_ bytes: [UInt8],
                           protocolVersion: CocoaMQTTProtocolVersion) -> MQTTAcknowledgementData? {
    guard var reader = MQTTByteReader(bytes),
          let msgid = reader.readUInt16(), msgid != 0 else { return nil }

    guard protocolVersion == .v5 else {
        guard reader.isAtEnd else { return nil }
        return MQTTAcknowledgementData(msgid: msgid,
                                       reasonCode: 0,
                                       propertyLength: 0,
                                       reasonString: nil,
                                       userProperty: nil,
                                       userProperties: [])
    }

    guard let reasonCode = reader.isAtEnd ? UInt8(0) : reader.readByte() else { return nil }
    if reader.isAtEnd {
        return MQTTAcknowledgementData(msgid: msgid,
                                       reasonCode: reasonCode,
                                       propertyLength: 0,
                                       reasonString: nil,
                                       userProperty: nil,
                                       userProperties: [])
    }

    guard let propertyLength = reader.readVariableByteInteger(),
          var properties = reader.readSection(length: propertyLength),
          reader.isAtEnd else { return nil }

    guard let decodedProperties = decodeReasonStringAndUserProperties(&properties) else { return nil }

    return MQTTAcknowledgementData(msgid: msgid,
                                   reasonCode: reasonCode,
                                   propertyLength: propertyLength,
                                   reasonString: decodedProperties.reasonString,
                                   userProperty: decodedProperties.userProperty,
                                   userProperties: decodedProperties.userProperties)
}

struct MQTTReasonCodeListData {
    let msgid: UInt16
    let propertyLength: Int
    let reasonString: String?
    let userProperty: [String: String]?
    let userProperties: [CocoaMQTTUserProperty]
    let reasonCodes: [UInt8]
}

func decodeReasonCodeList(_ bytes: [UInt8],
                          protocolVersion: CocoaMQTTProtocolVersion) -> MQTTReasonCodeListData? {
    guard var reader = MQTTByteReader(bytes),
          let msgid = reader.readUInt16(), msgid != 0 else { return nil }

    if protocolVersion == .v311 {
        guard let reasonCodes = reader.readBytes(count: reader.remainingCount) else { return nil }
        return MQTTReasonCodeListData(msgid: msgid,
                                      propertyLength: 0,
                                      reasonString: nil,
                                      userProperty: nil,
                                      userProperties: [],
                                      reasonCodes: reasonCodes)
    }

    guard let propertyLength = reader.readVariableByteInteger(),
          var properties = reader.readSection(length: propertyLength),
          let decodedProperties = decodeReasonStringAndUserProperties(&properties),
          let reasonCodes = reader.readBytes(count: reader.remainingCount) else { return nil }
    return MQTTReasonCodeListData(msgid: msgid,
                                  propertyLength: propertyLength,
                                  reasonString: decodedProperties.reasonString,
                                  userProperty: decodedProperties.userProperty,
                                  userProperties: decodedProperties.userProperties,
                                  reasonCodes: reasonCodes)
}
