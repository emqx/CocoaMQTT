//
//  FramePubRec.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBREC packet
struct FramePubRec: Frame {
    
    var fixedHeader: UInt8 = 0x50
    
    // --- Attributes
    
    var msgid: UInt16
    
    // --- Attributes End
    
    init(msgid: UInt16) {
        self.msgid = msgid
    }
}

extension FramePubRec {
 
    func variableHeader() -> [UInt8] { return msgid.hlBytes }
    
    func payload() -> [UInt8] { return [] }
}


extension FramePubRec: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == FrameType.pubrec.rawValue else {
            return nil
        }
        guard bytes.count == 2 else {
            return nil
        }
        
        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }
}

extension FramePubRec: CustomStringConvertible {
    var description: String {
        return "PUBREC(id: \(msgid))"
    }
}
