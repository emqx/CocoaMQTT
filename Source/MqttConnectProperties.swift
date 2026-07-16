//
//  MqttConnectProperties.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/25.
//

import Foundation

public class MqttConnectProperties: NSObject {

    // 3.1.2.11.1 Property Length
    // public var propertyLength: UInt8?
    // 3.1.2.11.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?
    // 3.1.2.11.3 Receive Maximum
    public var receiveMaximum: UInt16?
    // 3.1.2.11.4 Maximum Packet Size
    public var maximumPacketSize: UInt32?
    // 3.1.2.11.5 Topic Alias Maximum
    public var topicAliasMaximum: UInt16?
    // 3.1.2.11.6 Request Response Information
    public var requestResponseInformation: UInt8?
    // 3.1.2.11.7 Request Problem Information
    public var requestProblemInfomation: UInt8?
    // 3.1.2.11.8 User Property
    public var userProperties: [String: String]?
    // 3.1.2.11.9 Authentication Method
    public var authenticationMethod: String?
    // 3.1.2.11.10 Authentication Data
    public var authenticationData: [UInt8]?

    public var properties: [UInt8] {
        var properties = [UInt8]()

        // 3.1.2.11.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }

        // 3.1.2.11.3 Receive Maximum
        if let receiveMaximum = self.receiveMaximum {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.receiveMaximum.rawValue, value: receiveMaximum.hlBytes)
        }

        // 3.1.2.11.4 Maximum Packet Size
        if let maximumPacketSize = self.maximumPacketSize {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.maximumPacketSize.rawValue, value: maximumPacketSize.byteArrayLittleEndian)
        }

        // 3.1.2.11.5 Topic Alias Maximum
        if let topicAliasMaximum = self.topicAliasMaximum {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.topicAliasMaximum.rawValue, value: topicAliasMaximum.hlBytes)
        }

        // 3.1.2.11.6 Request Response Information
        if let requestResponseInformation = self.requestResponseInformation {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.requestResponseInformation.rawValue, value: [requestResponseInformation])
        }
        // 3.1.2.11.7 Request Problem Information
        if let requestProblemInfomation = self.requestProblemInfomation {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.requestProblemInformation.rawValue, value: [requestProblemInfomation])
        }
        // 3.1.2.11.8 User Property
        if let userProperty = self.userProperties {
            properties += userProperty.userPropertyBytes
        }
        // 3.1.2.11.9 Authentication Method
        if let authenticationMethod = self.authenticationMethod {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.authenticationMethod.rawValue, value: authenticationMethod.bytesWithLength)
        }
        // 3.1.2.11.10 Authentication Data
        if let authenticationData = self.authenticationData,
           authenticationData.count <= Int(UInt16.max) {
            properties += getMQTTPropertyData(
                type: CocoaMQTTPropertyName.authenticationData.rawValue,
                value: UInt16(authenticationData.count).hlBytes + authenticationData
            )
        } else if authenticationData != nil {
            printError("Authentication Data exceeds the MQTT binary data limit.")
        }

        return properties
    }

    func isValid() -> Bool {
        guard receiveMaximum.map({ $0 != 0 }) ?? true,
              maximumPacketSize.map({ $0 != 0 }) ?? true,
              requestResponseInformation.map({ $0 <= 1 }) ?? true,
              requestProblemInfomation.map({ $0 <= 1 }) ?? true,
              hasValidMQTTUserProperties(userProperties),
              (authenticationData?.count ?? 0) <= Int(UInt16.max) else { return false }
        if let authenticationMethod = authenticationMethod {
            guard hasValidMQTTUTF8Length(authenticationMethod, allowEmpty: true) else { return false }
        }
        return authenticationData == nil || authenticationMethod != nil
    }

}
