//
//  FrameConnack.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


struct FrameConnAck: Frame {
    
    var fixedHeader: UInt8 = FrameType.connack.rawValue
    
    // --- Attributes
    
    var returnCode: CocoaMQTTConnAck
    
    var sessPresent: Bool = false
    
    // --- Attributes End

    init(code: CocoaMQTTConnAck) {
        returnCode = code
    }
}

extension FrameConnAck {
    
    func variableHeader() -> [UInt8] {
        return [sessPresent.bit, returnCode.rawValue]
    }
    
    func payload() -> [UInt8] { return [] }
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

extension FrameConnAck: CustomStringConvertible {
    var description: String {
        return "CONNACK(code: \(returnCode), sp: \(sessPresent))"
    }
}
