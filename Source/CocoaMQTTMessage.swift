//
//  CocoaMQTTMessage.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqx.io. All rights reserved.
//

import Foundation


/// MQTT Message
public class CocoaMQTTMessage: NSObject {
    
    @objc public var qos = CocoaMQTTQoS.qos1
    
    @objc public var topic: String
    
    @objc public var payload: [UInt8]
    
    @objc public var retained = false
    
    /// The `duplicated` property show that this message maybe has be received before
    ///
    /// - note: Readonly property
    @objc public var duplicated = false
    
    /// Return the payload as a utf8 string if possible
    ///
    /// It will return nil if the payload is not a valid utf8 string
    @objc public var string: String? {
        get {
            return NSString(bytes: payload, length: payload.count, encoding: String.Encoding.utf8.rawValue) as String?
        }
    }
    
    @objc public init(topic: String, string: String, qos: CocoaMQTTQoS = .qos1, retained: Bool = false) {
        self.topic = topic
        self.payload = [UInt8](string.utf8)
        self.qos = qos
        self.retained = retained
    }

    @objc public init(topic: String, payload: [UInt8], qos: CocoaMQTTQoS = .qos1, retained: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retained = retained
    }
}

extension CocoaMQTTMessage {
    
    public override var description: String {
        return "CocoaMQTTMessage(topic: \(topic), qos: \(qos), payload: \(payload.summary))"
    }
}

// For test
extension CocoaMQTTMessage {
    
    var t_pub_frame: FramePublish {
        var frame = FramePublish(topic: topic, payload: payload, qos: qos, msgid: 0)
        frame.retained = retained
        frame.dup = duplicated
        return frame
    }
    
}
