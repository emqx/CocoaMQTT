//
//  FrameDisconnect.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


/// MQTT Disconnect packet
struct FrameDisconnect: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.disconnect.rawValue

    //3.14.2 DISCONNECT Variable Header
    public var disconnectReasonCode: CocoaMQTTDISCONNECTReasonCode?


    //3.14.2.2.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?
    
    //3.14.2.2.3 Reason String
    public var reasonString: String?
    //3.14.2.2.4 User Property
    public var userProperties: [String: String]?
    //3.14.2.2.5 Server Reference
    public var serverReference: String?


    init(disconnectReasonCode: CocoaMQTTDISCONNECTReasonCode) {
        self.disconnectReasonCode = disconnectReasonCode
    }
}

extension FrameDisconnect {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.disconnect.rawValue]
        header += [UInt8(variableHeader().count)]

        return header
    }
    
    func variableHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [disconnectReasonCode!.rawValue]

        //MQTT 5.0
        header.append(UInt8(self.properties().count))
        header += self.properties()

        return header
    }
    
    func payload() -> [UInt8] { return [] }

    func properties() -> [UInt8] {
        var properties = [UInt8]()

        //3.14.2.2.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }
        //3.14.2.2.3 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        //3.14.2.2.4 User Property
        if let userProperty = self.userProperties {
            let dictValues = [String](userProperty.values)
            for (value) in dictValues {
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: value.bytesWithLength)
            }
        }
        //3.14.2.2.5 Server Reference
        if let serverReference = self.serverReference {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.serverReference.rawValue, value: serverReference.bytesWithLength)
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

extension FrameDisconnect: CustomStringConvertible {
    var description: String {
        return "DISCONNECT"
    }
}
