//
//  FramePingReq.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

struct FramePingReq: Frame {
    
    var fixedHeader: UInt8 = FrameType.pingreq.rawValue
    
    init() { /* Nothing to do */ }
}

extension FramePingReq {
    
    func variableHeader() -> [UInt8] { return [] }
    
    func payload() -> [UInt8] { return [] }

    func properties() -> [UInt8] { return [] }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData.append(fixedHeader)
        allData += variableHeader()
        allData += properties()
        allData += payload()

        return allData
    }
}

extension FramePingReq: CustomStringConvertible {
    var description: String {
        return "PING"
    }
}
