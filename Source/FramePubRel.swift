//
//  FramePubRel.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation

/// MQTT PUBREL packet
struct FramePubRel: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.pubrel.rawValue
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // -- Inherit end
    
    var msgid: UInt16
    
    init(msgid: UInt16) {
        self.msgid = msgid
        
        qos = .qos1
    }
    
    func bytes() -> [UInt8] {
        return [fixedHeader, 0x02] + msgid.hlBytes
    }
    
    func pack() { /* won't use */ }
}

extension FramePubRel: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == 0x62 else {
            return nil
        }
        guard bytes.count == 2 else {
            return nil
        }
        
        self.fixedHeader = fixedHeader
        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }
}
