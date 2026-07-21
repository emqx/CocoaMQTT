//
//  FrameConnack.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

struct FrameConnAck: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.connack.rawValue

    // --- Attributes

    /// MQTT 3.1.1
    var returnCode: CocoaMQTTConnAck?

    /// MQTT 5.0
    var reasonCode: CocoaMQTTCONNACKReasonCode?

    // 3.2.2.1.1 Session Present
    var sessPresent: Bool = false

    // --- Attributes End

    // 3.2.2.3 CONNACK Properties
    var connackProperties: MqttDecodeConnAck?
    var propertiesBytes: [UInt8]?
    // 3.2.3 CONNACK Payload
    // The CONNACK packet has no Payload.

    /// MQTT 3.1.1
    init(returnCode: CocoaMQTTConnAck) {
        self.returnCode = returnCode
    }

    /// MQTT 5.0
    init(code: CocoaMQTTCONNACKReasonCode) {
        reasonCode = code
    }

}

extension FrameConnAck {

    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.connack.rawValue]

        return header
    }

    func variableHeader5() -> [UInt8] {
        return [sessPresent.bit, reasonCode!.rawValue]
    }

    func payload5() -> [UInt8] { return [] }

    func properties() -> [UInt8] { return propertiesBytes ?? [] }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader5()
        allData += properties()
        allData += payload5()

        return allData
    }

    func variableHeader() -> [UInt8] {
        return [sessPresent.bit, returnCode!.rawValue]
    }

    func payload() -> [UInt8] { return [] }
}

extension FrameConnAck: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {
        guard packetFixedHeaderType == FrameType.connack.rawValue else {
            return nil
        }

        guard bytes.count >= 2, bytes[0] & 0xfe == 0 else {
            return nil
        }

        sessPresent = Bool(bit: bytes[0] & 0x01)

        if protocolVersion == .v5 {
            guard let ack = CocoaMQTTCONNACKReasonCode(rawValue: bytes[1]) else { return nil }
            reasonCode = ack
            propertiesBytes = bytes
            let decodedProperties = MqttDecodeConnAck()
            guard decodedProperties.properties(connackData: bytes,
                                               protocolVersion: protocolVersion) else { return nil }
            connackProperties = decodedProperties
        } else {
            guard bytes.count == 2, bytes[1] < CocoaMQTTConnAck.reserved.rawValue else { return nil }
            returnCode = CocoaMQTTConnAck(byte: bytes[1])
        }

        guard bytes[1] == 0 || !sessPresent else { return nil }
    }
}

extension FrameConnAck: CustomStringConvertible {
    var description: String {
        return "CONNACK(code: \(String(describing: reasonCode)), sp: \(sessPresent))"
    }
}
