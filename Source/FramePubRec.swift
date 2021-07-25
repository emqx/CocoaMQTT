//
//  FramePubRec.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBREC packet
struct FramePubRec: Frame {
    
    var packetFixedHeaderType: UInt8 = FrameType.pubrec.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    // --- Attributes End

    //3.5.2.1 PUBREC Reason Code
    public var reasonCode: CocoaMQTTPUBRECReasonCode?

    //3.5.2.2 PUBREC Properties
    //3.5.2.2.2 Reason String
    public var reasonString: String?
    //3.5.2.2.3 User Property
    public var userProperties: [String: String]?
    //3.8.3.1 Subscription Options
    public var topicFilters: [CocoaMMQTTopicFilter]?
    
    
    init(msgid: UInt16, reasonCode: CocoaMQTTPUBRECReasonCode) {
        self.msgid = msgid
        self.reasonCode = reasonCode
    }
}

extension FramePubRec {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.pubrec.rawValue]
        header += [UInt8(variableHeader().count)]

        return header
    }
    
    func variableHeader() -> [UInt8] {
        //3.5.2 MSB+LSB
        var header = msgid.hlBytes
        //3.5.2.1 PUBACK Reason Code
        header += [reasonCode!.rawValue]

        //MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)
        header += self.properties()

        return header
    }
    
    func payload() -> [UInt8] { return [] }

    func properties() -> [UInt8] {
        var properties = [UInt8]()

        //3.5.2.2.2 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }

        //3.5.2.2.3 User Property
        if let userProperty = self.userProperties {
            let dictValues = [String](userProperty.values)
            for (value) in dictValues {
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: value.bytesWithLength)
            }
        }

        return properties;
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


extension FramePubRec: InitialWithBytes {
    
    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        guard packetFixedHeaderType == FrameType.pubrec.rawValue else {
            return nil
        }
        guard bytes.count == 2 else {
            return nil
        }
        
        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }
}

extension FramePubRec: CustomStringConvertible {
    var description: String {
        return "PUBREC(id: \(msgid))"
    }
}
