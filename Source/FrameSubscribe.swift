//
//  FrameSubscribe.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation


/// MQTT SUBSCRIBE Frame
struct FrameSubscribe: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.subscribe.rawValue
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // --- Inherit end
    
    var msgid: UInt16
    
    var topics: [(String, CocoaMQTTQoS)]
    
    init(msgid: UInt16, topic: String, reqos: CocoaMQTTQoS) {
        self.init(msgid: msgid, topics: [(topic, reqos)])
    }
    
    /// TODO: Not work for objective-c
    init(msgid: UInt16, topics: [(String, CocoaMQTTQoS)]) {
        fixedHeader = FrameType.subscribe.rawValue
        self.msgid = msgid
        self.topics = topics
        
        qos = CocoaMQTTQoS.qos1
    }
    
    func bytes() -> [UInt8] {
        
        let variableHeader = msgid.hlBytes
        
        var payload = [UInt8]()
        for (topic, qos) in topics {
            payload += topic.bytesWithLength
            payload.append(qos.rawValue)
        }
        
        let length = UInt32(variableHeader.count + payload.count)
        
        return [fixedHeader] + remainingLen(len: length) + variableHeader + payload
    }
    
    mutating func pack() { /* won't use*/ }
}
