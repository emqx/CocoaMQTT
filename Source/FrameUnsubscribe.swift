//
//  FrameUnsubscribe.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation


/// MQTT UNSUBSCRIBE packet
struct FrameUnsubscribe: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.unsubscribe.rawValue
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // --- Inherit end
    
    var msgid: UInt16
    var topics: [String]
    
    init(msgid: UInt16, topics: [String]) {
        self.msgid = msgid
        self.topics = topics
        
        qos = CocoaMQTTQoS.qos1
    }
    
    func bytes() -> [UInt8] {
        let variableHeader = msgid.hlBytes
        
        var payload = [UInt8]()
        for t in topics {
            payload += t.bytesWithLength
        }
        
        let length = UInt32(variableHeader.count + payload.count)
        return [fixedHeader] + remainingLen(len: length) + variableHeader + payload
    }
    
    mutating func pack() { /* won't use */ }
}
