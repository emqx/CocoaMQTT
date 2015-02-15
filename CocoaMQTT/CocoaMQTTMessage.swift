//
//  CocoaMQTTMessage.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng.lee@nextalk.im> on 14/8/3.
//  Copyright (c) 2014年 slimpp.io. All rights reserved.
//

import Foundation

/**
* MQTT Messgae
*/
class CocoaMQTTMessage {
    
    var topic: String
    
    var payload: [Byte]
    
    //utf8 bytes array to string
    var string: String? {
    get {
        return NSString(bytes: payload, length: payload.count, encoding: NSUTF8StringEncoding)
//        return String.stringWithBytes(payload,
//            length: payload.count,
//            encoding: NSUTF8StringEncoding)
    }
    }
    
    var qos: CocoaMQTTQOS = .QOS1
    
    var retain: Bool = false
    
    var dup: Bool = false
    
    init(topic: String, string: String, qos: CocoaMQTTQOS = .QOS1) {
        self.topic = topic
        self.payload = [Byte](string.utf8)
        self.qos = qos
    }
    
    init(topic: String, payload: [Byte], qos: CocoaMQTTQOS = .QOS1, retain: Bool = false, dup: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retain = retain
        self.dup = dup
    }
    
}

/**
 * MQTT Will Message
**/
class CocoaMQTTWill: CocoaMQTTMessage {
    
    init(topic: String, message: String) {
        super.init(topic: topic, payload: message.bytesWithLength)
    }
    
}

