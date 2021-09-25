//
//  FrameUnsubAck.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


/// MQTT UNSUBACK packet
struct FrameUnsubAck: Frame {

    var fixedHeader: UInt8 = FrameType.unsuback.rawValue

    // --- Attributes
    
    var msgid: UInt16
    
    // --- Attributes End
    
    init(msgid: UInt16) {
        self.msgid = msgid
    }
}

extension FrameUnsubAck {
    
    func variableHeader() -> [UInt8] { return msgid.hlBytes }
    
    func payload() -> [UInt8] { return [] }
}


extension FrameUnsubAck: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == FrameType.unsuback.rawValue else {
            return nil
        }
        
        guard bytes.count == 2 else {
            return nil
        }
        
        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }
}

extension FrameUnsubAck: CustomStringConvertible {
    var description: String {
        return "UNSUBSACK(id: \(msgid))"
    }
}
