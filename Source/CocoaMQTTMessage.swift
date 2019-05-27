//
//  CocoaMQTTMessage.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation


/// MQTT Message
public class CocoaMQTTMessage: NSObject {
    public var qos = CocoaMQTTQoS.qos1
    
    public var topic: String
    public var payload: [UInt8]
    public var retained = false
    
    /// Return the payload as a utf8 string if possiable
    public var string: String? {
        get {
            return NSString(bytes: payload, length: payload.count, encoding: String.Encoding.utf8.rawValue) as String?
        }
    }
    
    public init(topic: String, string: String, qos: CocoaMQTTQoS = .qos1, retained: Bool = false) {
        self.topic = topic
        self.payload = [UInt8](string.utf8)
        self.qos = qos
        self.retained = retained
    }

    public init(topic: String, payload: [UInt8], qos: CocoaMQTTQoS = .qos1, retained: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retained = retained
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
