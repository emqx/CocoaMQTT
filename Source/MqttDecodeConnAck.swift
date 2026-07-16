//
//  MqttDecodeConnAck.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/26.
//

import Foundation

public class MqttDecodeConnAck: NSObject {

    //    var connackData: [UInt8]
    //
    //    init(connackData: [UInt8]) {
    //        connackData = connackData
    //    }

    // 3.2.2.3 CONNACK Properties
    // 3.2.2.3.1 Property Length
    public var propertyLength: Int?
    // 3.2.2.3.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?
    // 3.2.2.3.3 Receive Maximum
    public var receiveMaximum: UInt16?
    // 3.2.2.3.4 Maximum QoS
    public var maximumQoS: CocoaMQTTQoS?
    // 3.2.2.3.5 Retain Available
    public var retainAvailable: Bool?
    // 3.2.2.3.6 Maximum Packet Size
    public var maximumPacketSize: UInt32?
    // 3.2.2.3.7 Assigned Client Identifier
    public var assignedClientIdentifier: String?
    // 3.2.2.3.8 Topic Alias Maximum
    public var topicAliasMaximum: UInt16?
    // 3.2.2.3.9 Reason String
    public var reasonString: String?
    // 3.2.2.3.10 User Property
    public var userProperty: [String: String]?
    // 3.2.2.3.11 Wildcard Subscription Available
    public var wildcardSubscriptionAvailable: Bool?
    // 3.2.2.3.12 Subscription Identifiers Available
    public var subscriptionIdentifiersAvailable: Bool?
    // 3.2.2.3.13 Shared Subscription Available
    public var sharedSubscriptionAvailable: Bool?
    // 3.2.2.3.14 Server Keep Alive
    public var serverKeepAlive: UInt16?
    // 3.2.2.3.15 Response Information
    public var responseInformation: String?
    // 3.2.2.3.16 Server Reference
    public var serverReference: String?
    // 3.2.2.3.17 Authentication Method
    public var authenticationMethod: String?
    // 3.2.2.3.18 Authentication Data
    public var authenticationData = [UInt8]()

    @discardableResult
    public func properties(connackData: [UInt8],
                           protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        propertyLength = nil
        sessionExpiryInterval = nil
        receiveMaximum = nil
        maximumQoS = nil
        retainAvailable = nil
        maximumPacketSize = nil
        assignedClientIdentifier = nil
        topicAliasMaximum = nil
        reasonString = nil
        userProperty = nil
        wildcardSubscriptionAvailable = nil
        subscriptionIdentifiersAvailable = nil
        sharedSubscriptionAvailable = nil
        serverKeepAlive = nil
        responseInformation = nil
        serverReference = nil
        authenticationMethod = nil
        authenticationData = []

        guard protocolVersion == .v5,
              var reader = MQTTByteReader(connackData),
              reader.readByte() != nil,
              reader.readByte() != nil,
              let decodedPropertyLength = reader.readVariableByteInteger(),
              var properties = reader.readSection(length: decodedPropertyLength),
              reader.isAtEnd else { return false }

        propertyLength = decodedPropertyLength
        var singleUseProperties = Set<CocoaMQTTPropertyName>()

        while !properties.isAtEnd {
            guard let identifier = properties.readVariableByteInteger(),
                  let propertyName = UInt8(exactly: identifier).flatMap(CocoaMQTTPropertyName.init(rawValue:)) else {
                return false
            }
            if propertyName != .userProperty {
                guard singleUseProperties.insert(propertyName).inserted else { return false }
            }

            switch propertyName {
            case .sessionExpiryInterval:
                guard let value = properties.readUInt32() else { return false }
                sessionExpiryInterval = value
            case .receiveMaximum:
                guard let value = properties.readUInt16(), value != 0 else { return false }
                receiveMaximum = value
            case .maximumQoS:
                guard let value = properties.readByte(), value <= 1,
                      let qos = CocoaMQTTQoS(rawValue: value) else { return false }
                maximumQoS = qos
            case .retainAvailable:
                guard let value = properties.readByte(), value <= 1 else { return false }
                retainAvailable = value == 1
            case .maximumPacketSize:
                guard let value = properties.readUInt32(), value != 0 else { return false }
                maximumPacketSize = value
            case .assignedClientIdentifier:
                guard let value = properties.readUTF8String() else { return false }
                assignedClientIdentifier = value
            case .topicAliasMaximum:
                guard let value = properties.readUInt16() else { return false }
                topicAliasMaximum = value
            case .reasonString:
                guard let value = properties.readUTF8String() else { return false }
                reasonString = value
            case .userProperty:
                guard let key = properties.readUTF8String(),
                      let value = properties.readUTF8String() else { return false }
                if userProperty == nil { userProperty = [:] }
                userProperty?[key] = value
            case .wildcardSubscriptionAvailable:
                guard let value = properties.readByte(), value <= 1 else { return false }
                wildcardSubscriptionAvailable = value == 1
            case .subscriptionIdentifiersAvailable:
                guard let value = properties.readByte(), value <= 1 else { return false }
                subscriptionIdentifiersAvailable = value == 1
            case .sharedSubscriptionAvailable:
                guard let value = properties.readByte(), value <= 1 else { return false }
                sharedSubscriptionAvailable = value == 1
            case .serverKeepAlive:
                guard let value = properties.readUInt16() else { return false }
                serverKeepAlive = value
            case .responseInformation:
                guard let value = properties.readUTF8String() else { return false }
                responseInformation = value
            case .serverReference:
                guard let value = properties.readUTF8String() else { return false }
                serverReference = value
            case .authenticationMethod:
                guard let value = properties.readUTF8String() else { return false }
                authenticationMethod = value
            case .authenticationData:
                guard let value = properties.readBinaryData() else { return false }
                authenticationData = value
            default:
                return false
            }
        }

        return !singleUseProperties.contains(.authenticationData) || authenticationMethod != nil
    }

}
