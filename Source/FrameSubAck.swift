//
//  FrameSubAck.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation


/// MQTT SUBACK packet
struct FrameSubAck: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.suback.rawValue
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // --- Inherit end
    
    var msgid: UInt16
    
    var grantedQos: [CocoaMQTTQoS]
    
    init(msgid: UInt16, grantedQos: [CocoaMQTTQoS]) {
        self.msgid = msgid
        self.grantedQos = grantedQos
    }
    
    func bytes() -> [UInt8] {
        
        let variableHeader = msgid.hlBytes
        
        var payload = [UInt8]()
        for qos in grantedQos {
            payload.append(qos.rawValue)
        }
        
        let length = UInt32(variableHeader.count + payload.count)
        return [fixedHeader] + remainingLen(len: length) + variableHeader + payload
    }
}

extension FrameSubAck: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        self.fixedHeader = fixedHeader
        
        // the bytes length must bigger than 3
        guard bytes.count >= 3 else {
            return nil
        }
        
        self.msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
        self.grantedQos = []
        for i in 2 ..< bytes.count {
            guard let qos = CocoaMQTTQoS(rawValue: bytes[i]) else {
                return nil
            }
            self.grantedQos.append(qos)
        }
    }
}
