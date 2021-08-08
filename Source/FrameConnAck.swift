//
//  FrameConnack.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


struct FrameConnAck: Frame {

    init(code: CocoaMQTTCONNACKReasonCode) {
        reasonCode = code
    }

    var packetFixedHeaderType: UInt8 = FrameType.connack.rawValue
    
    // --- Attributes
    
    var reasonCode: CocoaMQTTCONNACKReasonCode

    //3.2.2.1.1 Session Present
    var sessPresent: Bool = false
    
    // --- Attributes End

    //3.2.2.3 CONNACK Properties
    var connackProperties: MqttDecodeConnAck?
    var propertiesBytes: [UInt8]?
    //3.2.3 CONNACK Payload
    //The CONNACK packet has no Payload.


}

extension FrameConnAck {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.connack.rawValue]
        header += [UInt8(variableHeader().count)]
        
        return header
    }

    func variableHeader() -> [UInt8] {
        return [sessPresent.bit, reasonCode.rawValue]
    }
    
    func payload() -> [UInt8] { return [] }

    func properties() -> [UInt8] { return propertiesBytes ?? [] }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader()
        allData += properties()
        allData += payload()

        return allData
    }
}

extension FrameConnAck: InitialWithBytes {
    
    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        guard packetFixedHeaderType == FrameType.connack.rawValue else {
            return nil
        }
        
        guard bytes.count >= 2 else {
            return nil
        }

        sessPresent = Bool(bit: bytes[0] & 0x01)
        
        guard let ack = CocoaMQTTCONNACKReasonCode(rawValue: bytes[1]) else {
            return nil
        }
        reasonCode = ack

        propertiesBytes = bytes
        self.connackProperties = MqttDecodeConnAck.shared
        self.connackProperties!.properties(connackData: bytes)
    }
}

extension FrameConnAck: CustomStringConvertible {
    var description: String {
        return "CONNACK(code: \(reasonCode), sp: \(sessPresent))"
    }
}
