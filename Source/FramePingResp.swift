//
//  FramePingResp.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation


/// MQTT PINGRESP packet
struct FramePingResp: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.pingresp.rawValue
    
    let variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // --- Inherit end
    
    init() { /* Nothing to do */ }
    
    func bytes() -> [UInt8] {
        return [fixedHeader, 0x00]
    }
}

extension FramePingResp: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == FrameType.pingresp.rawValue else {
            return nil
        }
        
        guard bytes.count == 0 else {
            return nil
        }
    }
}
