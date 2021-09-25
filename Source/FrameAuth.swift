//
//  FrameAuth.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/4.
//

import Foundation


struct FrameAuth: Frame {


    var packetFixedHeaderType: UInt8 = FrameType.auth.rawValue

    //3.15.2.1 Authenticate Reason Code
    var reasonCode: CocoaMQTTAUTHReasonCode
    //3.15.2.2.2 Authentication Method
    public var authenticationMethod: String?
    //3.15.2.2.3 Authentication Data
    public var authenticationData: [UInt8]?
    //3.15.2.2.4 Reason String
    public var reasonString: String?
    //3.15.2.2.5 User Property
    public var userProperties: [String: String]?

    init(reasonCode: CocoaMQTTAUTHReasonCode) {
        self.reasonCode = reasonCode
    }

}



extension FrameAuth {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.connect.rawValue]
        header += [UInt8(variableHeader().count)]

        return header
    }

    func variableHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [reasonCode.rawValue]
        //MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)
   
        return header
    }

    func payload() -> [UInt8] { return []}

    func properties() -> [UInt8] {
        var properties = [UInt8]()

        //3.15.2.2.2 Authentication Method
        if let authenticationMethod = self.authenticationMethod {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.authenticationMethod.rawValue, value: authenticationMethod.bytesWithLength)
        }
        //3.15.2.2.3 Authentication Data
        if let authenticationData = self.authenticationData {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.authenticationData.rawValue, value: authenticationData)
        }
        //3.15.2.2.4 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        //3.15.2.2.5 User Property
        if let userProperty = self.userProperties {
            let dictValues = [String](userProperty.values)
            for (value) in dictValues {
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: value.bytesWithLength)
            }
        }
        
        return properties
    }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader()
        allData += properties()
        allData += payload()

        return allData
    }
}


