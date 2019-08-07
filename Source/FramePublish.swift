//
//  FramePublish.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation

/// MQTT PUBLISH Frame
struct FramePublish: Frame {
    
    //  --- Inherit
    
    var fixedHeader: UInt8 = FrameType.publish.rawValue
    
    var variableHeader: [UInt8] = []
    
    // --- Inherit end
    
    var msgid: UInt16
    
    var topic: String
    
    var payload: [UInt8] = []
    
    init(msgid: UInt16, topic: String, payload: [UInt8]) {
        self.msgid = msgid
        self.topic = topic
        self.payload = payload
    }
    
    func bytes() -> [UInt8] {
        
        var variableHeader = topic.bytesWithLength
        if qos.rawValue > CocoaMQTTQoS.qos0.rawValue {
            variableHeader += msgid.hlBytes
        }
        
        let length = UInt32(variableHeader.count + payload.count)
        return [fixedHeader] + remainingLen(len: length) + variableHeader + payload
    }
}

extension FramePublish: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        
        guard fixedHeader & 0xF0 == FrameType.publish.rawValue else {
            return nil
        }
        
        self.fixedHeader = fixedHeader
        
        // parse topic
        if bytes.count < 2 {
            return nil
        }
        
        let len = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
        
        var pos = 2 + Int(len)
        
        if bytes.count < pos {
            return nil
        }
        
        topic = NSString(bytes: [UInt8](bytes[2...(pos-1)]), length: Int(len), encoding: String.Encoding.utf8.rawValue)! as String
        
        // msgid
        if (fixedHeader & 0x06) >> 1 == CocoaMQTTQoS.qos0.rawValue {
            msgid = 0
        } else {
            if bytes.count < pos + 2 {
                return nil
            }
            msgid = UInt16(bytes[pos]) << 8 + UInt16(bytes[pos+1])
            pos += 2
        }
        
        // payload
        let end = bytes.count - 1
        
        if (end - pos >= 0) {
            payload = [UInt8](bytes[pos...end])
            // receives an empty message
        } else {
            return nil
        }
    }
}

extension FramePublish: CustomStringConvertible {
    var description: String {
        return "PUBLISH(msgid: \(msgid), topic: \(topic), payload: \(payload))"
    }
}
