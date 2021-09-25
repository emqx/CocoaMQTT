//
//  FramePubCom.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBCOMP packet
struct FramePubComp: Frame {
    
    var fixedHeader: UInt8 = FrameType.pubcomp.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    // --- Attributes End
    
    init(msgid: UInt16) {
        self.msgid = msgid
    }
}

extension FramePubComp {
    
    func variableHeader() -> [UInt8] { return msgid.hlBytes }
    
    func payload() -> [UInt8] { return [] }
}

extension FramePubComp: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == FrameType.pubcomp.rawValue else {
            return nil
        }
        
        guard bytes.count == 2 else {
            return nil
        }
        
        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }
}

extension FramePubComp: CustomStringConvertible {
    var description: String {
        return "PUBCOMP(id: \(msgid))"
    }
}
