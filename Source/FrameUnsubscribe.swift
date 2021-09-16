//
//  FrameUnsubscribe.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


/// MQTT UNSUBSCRIBE packet
struct FrameUnsubscribe: Frame {
    
    var packetFixedHeaderType: UInt8 = UInt8(FrameType.unsubscribe.rawValue + 2)
    
    // --- Attributes
    
    var msgid: UInt16
    
    var topicFilters: [MqttSubscription]
    
    // --- Attribetes end

    //3.10.2.1.2 User Property
    public var userProperty: [String: String]?

    init(msgid: UInt16, topics: [MqttSubscription]) {
        self.msgid = msgid
        self.topicFilters = topics

        qos = CocoaMQTTQoS.qos1
    }


}

extension FrameUnsubscribe {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.unsubscribe.rawValue]

        return header
    }
    
    func variableHeader() -> [UInt8] {
        //MQTT 5.0
        var header = [UInt8]()
        header = msgid.hlBytes
        header += beVariableByteInteger(length: self.properties().count)
        return header
    }
    
    func payload() -> [UInt8] {
        
        var payload = [UInt8]()
        
        for subscription in self.topicFilters {
            subscription.subscriptionOptions = false
            payload += subscription.subscriptionData
        }

        return payload
    }


    func properties() -> [UInt8] {
        var properties = [UInt8]()

        // 3.10.2.1.2 User Property
        if let userProperty = self.userProperty {
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

extension FrameUnsubscribe: CustomStringConvertible {
    var description: String {
        var desc = ""
        for subscription in self.topicFilters {
            desc += "UNSUBSCRIBE(id: \(msgid), topics: \(subscription.topic))  "
        }
        return desc
    }
}
