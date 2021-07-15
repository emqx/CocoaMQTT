//
//  FramePubRel.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBREL packet
/// A PUBREL packet is the response to a PUBREC packet. It is the third packet of the QoS 2 protocol exchange.
struct FramePubRel: Frame {
    
    var packetFixedHeaderType: UInt8 = FrameType.pubrel.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    // --- Attributes End


    //3.6.2.1 PUBREL Reason Code
    public var reasonCode: CocoaMQTTPUBRELReasonCode?

    //3.6.2.2 PUBREL Properties
    //3.6.2.2.2 Reason String
    public var reasonString: String?
    //3.6.2.2.3 User Property
    public var userProperties: [String: String]?

    init(msgid: UInt16) {
        self.msgid = msgid
        
        qos = .qos1
    }
}

extension FramePubRel {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.pubrel.rawValue]
        header += [UInt8(variableHeader().count + payload().count)]

        return header
    }
    
    func variableHeader() -> [UInt8] {
        //3.6.2 MSB+LSB
        var head = msgid.hlBytes
        //3.6.2.1 PUBACK Reason Code
        head += [reasonCode!.rawValue]

        //MQTT 5.0
        head.append(UInt8(self.properties().count))
        head += self.properties()

        return head
    }
    
    func payload() -> [UInt8] { return [] }
    
    func properties() -> [UInt8] {
        var properties = [UInt8]()

        //3.6.2.2.2 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }

        //3.6.2.2.3 User Property
        if let userProperty = self.userProperties {
            //propertiesData += MQTTProperty<[String : String]>(.userProperty, value: userProperty).mqttData
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

extension FramePubRel: InitialWithBytes {
    
    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        guard packetFixedHeaderType == 0x62 else {
            return nil
        }
        guard bytes.count == 2 else {
            return nil
        }
        
        self.packetFixedHeaderType = packetFixedHeaderType
        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }
}

extension FramePubRel: CustomStringConvertible {
    var description: String {
        return "PUBREL(id: \(msgid))"
    }
}
