//
//  MqttAuthProperties.swift
//  CocoaMQTT
//
//  Created by liwei wang on 1/9/2021.
//

import Foundation

public class MqttAuthProperties: NSObject {

    // 3.15.2.2.2 Authentication Method
    public var authenticationMethod: String?
    // 3.15.2.2.3 Authentication Data
    public var authenticationData: [UInt8]?
    // 3.15.2.2.4 Reason String
    public var reasonString: String?
    // 3.15.2.2.5 User Property
    public var userProperties: [String: String]?
    /// Ordered User Properties. When non-empty, these are encoded instead of `userProperties`.
    public var userPropertyList = [CocoaMQTTUserProperty]()

    public var properties: [UInt8] {
        var properties = [UInt8]()

        // 3.15.2.2.2 Authentication Method
        if let authenticationMethod = self.authenticationMethod {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.authenticationMethod.rawValue, value: authenticationMethod.bytesWithLength)
        }
        // 3.15.2.2.3 Authentication Data
        if let authenticationData = self.authenticationData,
           authenticationData.count <= Int(UInt16.max) {
            properties += getMQTTPropertyData(
                type: CocoaMQTTPropertyName.authenticationData.rawValue,
                value: UInt16(authenticationData.count).hlBytes + authenticationData
            )
        } else if authenticationData != nil {
            printError("Authentication Data exceeds the MQTT binary data limit.")
        }
        // 3.15.2.2.4 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        // 3.15.2.2.5 User Property
        if !userPropertyList.isEmpty {
            properties += userPropertyList.userPropertyBytes
        } else if let userProperty = self.userProperties {
            properties += userProperty.userPropertyBytes
        }

        return properties
    }

    func isValid(expectedAuthenticationMethod: String) -> Bool {
        guard authenticationMethod == expectedAuthenticationMethod,
              hasValidMQTTUTF8Length(expectedAuthenticationMethod, allowEmpty: true),
              (authenticationData?.count ?? 0) <= Int(UInt16.max),
              hasValidMQTTUserProperties(userProperties),
              hasValidMQTTUserProperties(userPropertyList) else { return false }
        return reasonString.map { hasValidMQTTUTF8Length($0, allowEmpty: true) } ?? true
    }

}
