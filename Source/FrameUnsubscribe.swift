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
    
    var topics: [String]
    
    // --- Attribetes end

    //3.10.2.1.2 User Property
    public var userProperty: [String: String]?
    //3.10.3 UNSUBSCRIBE Payload
    public var topicFilters: [CocoaMMQTTopicFilter]

    init(msgid: UInt16, topics: [String], topicFilters: [CocoaMMQTTopicFilter]) {
        self.msgid = msgid
        self.topics = topics
        self.topicFilters = topicFilters

        qos = CocoaMQTTQoS.qos1
    }

//    init(msgid: UInt16, topicFilters: [CocoaMMQTTopicFilter]) {
//        //qos = CocoaMQTTQoS.qos1
//
//        self.msgid = msgid
//        self.topicFilters = topicFilters
//
//    }
}

extension FrameUnsubscribe {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.unsubscribe.rawValue]
        header += [UInt8(variableHeader().count + payload().count)]

        return header
    }
    
    func variableHeader() -> [UInt8] { return msgid.hlBytes }
    
    func payload() -> [UInt8] {
        
        var payload = [UInt8]()
        
        for t in topics {
            payload += t.bytesWithLength
        }
        
        return payload
    }


    func properties() -> [UInt8] { return [] }

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
        return "UNSUBSCRIBE(id: \(msgid), topics: \(topics))"
    }
}
