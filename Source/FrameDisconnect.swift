//
//  FrameDisconnect.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


/// MQTT Disconnect packet
struct FrameDisconnect: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.disconnect.rawValue
    
    init() { /* Nothing to do */ }
}

extension FrameDisconnect {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.disconnect.rawValue]
        header += [UInt8(variableHeader().count)]

        return header
    }
    
    func variableHeader() -> [UInt8] { return [] }
    
    func payload() -> [UInt8] { return [] }

    func properties() -> [UInt8] { return [] }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader()
        allData += properties()
        allData += payload()

        return allData
    }

}

extension FrameDisconnect: CustomStringConvertible {
    var description: String {
        return "DISCONNECT"
    }
}
