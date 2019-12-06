//
//  FramePubRel.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBREL packet
struct FramePubRel: Frame {
    
    var fixedHeader: UInt8 = FrameType.pubrel.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    // --- Attributes End
    
    init(msgid: UInt16) {
        self.msgid = msgid
        
        qos = .qos1
    }
}

extension FramePubRel {
    
    func variableHeader() -> [UInt8] { return msgid.hlBytes }
    
    func payload() -> [UInt8] { return [] }
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

extension FramePubRel: CustomStringConvertible {
    var description: String {
        return "PUBREL(id: \(msgid))"
    }
}
