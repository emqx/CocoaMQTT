//
//  FramePublish.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBLISH Frame
struct FramePublish: Frame {
    
    var fixedHeader: UInt8 = FrameType.publish.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    var topic: String
    
    var _payload: [UInt8] = []
    
    // --- Attributes End
    
    init(topic: String, payload: [UInt8], qos: CocoaMQTTQoS = .qos0, msgid: UInt16 = 0) {
        self.topic = topic
        self._payload = payload
        self.msgid = msgid
        
        self.qos = qos
    }
}

extension FramePublish {
    
    func variableHeader() -> [UInt8] {
        
        var header = topic.bytesWithLength
        
        if qos > .qos0 {
            header += msgid.hlBytes
        }
        
        return header
    }
    
    func payload() -> [UInt8] { return _payload }
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
        if (pos == bytes.count) {
            _payload = []
        } else if (pos < bytes.count) {
            _payload = [UInt8](bytes[pos..<bytes.count])
        } else {
            return nil
        }
    }
}

extension FramePublish: CustomStringConvertible {
    var description: String {
        return "PUBLISH(id: \(msgid), topic: \(topic), payload: \(_payload.summary))"
    }
}
