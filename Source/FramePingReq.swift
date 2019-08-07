//
//  FramePingReq.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation

struct FramePingReq: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.pingreq.rawValue
    
    let variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // --- Inherit end
    
    init() { /* Nothing to do */ }
    
    func bytes() -> [UInt8] {
        return [fixedHeader, 0x00]
    }
}
