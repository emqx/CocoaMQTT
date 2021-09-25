//
//  FrameSubscribe.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


/// MQTT SUBSCRIBE Frame
struct FrameSubscribe: Frame {
    
    var fixedHeader: UInt8 = FrameType.subscribe.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    var topics: [(String, CocoaMQTTQoS)]
    
    // --- Attributes End
    
    init(msgid: UInt16, topic: String, reqos: CocoaMQTTQoS) {
        self.init(msgid: msgid, topics: [(topic, reqos)])
    }
    
    init(msgid: UInt16, topics: [(String, CocoaMQTTQoS)]) {
        fixedHeader = FrameType.subscribe.rawValue
        self.msgid = msgid
        self.topics = topics
        
        qos = CocoaMQTTQoS.qos1
    }
}

extension FrameSubscribe {
    
    func variableHeader() -> [UInt8] { return msgid.hlBytes }
    
    func payload() -> [UInt8] {
        
        var payload = [UInt8]()
        
        for (topic, qos) in topics {
            payload += topic.bytesWithLength
            payload.append(qos.rawValue)
        }
        
        return payload
    }
}

extension FrameSubscribe: CustomStringConvertible {
    var description: String {
        return "SUBSCRIBE(id: \(msgid), topics: \(topics))"
    }
}
