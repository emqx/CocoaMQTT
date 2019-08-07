//
//  FrameConnack.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation


struct FrameConnAck: Frame {
    
    // -- Inherit
    
    var fixedHeader: UInt8 = FrameType.connack.rawValue
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // -- Inherit end
    
    var returnCode: CocoaMQTTConnAck
    
    var sessPresent: Bool = false
    
    func bytes() -> [UInt8] {
        return [fixedHeader, 0x02, sessPresent.bit, returnCode.rawValue]
    }
    
    init(code: CocoaMQTTConnAck) {
        returnCode = code
    }
}

extension FrameConnAck: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == FrameType.connack.rawValue else {
            return nil
        }
        
        guard bytes.count == 2 else {
            return nil
        }
        
        sessPresent = Bool(bit: bytes[0] & 0x01)
        
        guard let ack = CocoaMQTTConnAck(rawValue: bytes[1]) else {
            return nil
        }
        returnCode = ack
    }
}
