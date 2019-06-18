//
//  CocoaMQTTMessage.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation


/**
 * MQTT Message
 */
public class CocoaMQTTMessage: NSObject {
    public var qos = CocoaMQTTQOS.qos1
    public var dup = false

    public var topic: String
    public var payload: [UInt8]
    public var retained = false
    
    // utf8 bytes array to string
    public var string: String? {
        get {
            return NSString(bytes: payload, length: payload.count, encoding: String.Encoding.utf8.rawValue) as String?
        }
    }
    
    public init(topic: String, string: String, qos: CocoaMQTTQOS = .qos1, retained: Bool = false, dup: Bool = false) {
        self.topic = topic
        self.payload = [UInt8](string.utf8)
        self.qos = qos
        self.retained = retained
        self.dup = dup
    }

    public init(topic: String, payload: [UInt8], qos: CocoaMQTTQOS = .qos1, retained: Bool = false, dup: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retained = retained
        self.dup = dup
    }
    
    func convertToFrame() -> CocoaMQTTFramePublish {
        var frame = CocoaMQTTFramePublish(msgid: 0, topic: topic, payload: payload)
        frame.qos = qos.rawValue
        frame.retained = retained
        
        return frame
    }
}

/**
 * MQTT Will Message
 */
public class CocoaMQTTWill: CocoaMQTTMessage {
    public init(topic: String, message: String) {
        super.init(topic: topic, payload: message.bytesWithLength)
    }
    
    public init(topic: String, payload: [UInt8]) {
        let endian = UInt16(payload.count).hlBytes
        let payloadCoded = endian + payload as [UInt8]
        super.init(topic: topic, payload: payloadCoded)
    }
}
