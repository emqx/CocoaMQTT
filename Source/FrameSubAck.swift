//
//  FrameSubAck.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT SUBACK packet
struct FrameSubAck: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.suback.rawValue

    // --- Attributes

    var msgid: UInt16

    var grantedQos: [CocoaMQTTQoS]

    // --- Attributes End

    // 3.9.2.1.2 Reason String
    public var reasonString: String?
    // 3.9.2.1.3 User Property
    public var userProperties: [String: String]?
    // 3.9.3 The order of Reason Codes in the SUBACK packet MUST match the order of Topic Filters in the SUBSCRIBE packet [MQTT-3.9.3-1].
    public var reasonCodes: [CocoaMQTTSUBACKReasonCode]?

    // 3.9.2.1 SUBACK Properties
    public var subAckProperties: MqttDecodeSubAck?

    init(msgid: UInt16, grantedQos: [CocoaMQTTQoS]) {
        self.msgid = msgid
        self.grantedQos = grantedQos
    }
}

extension FrameSubAck {

    func fixedHeader() -> [UInt8] {

        var header = [UInt8]()
        header += [FrameType.suback.rawValue]

        return header
    }

    func variableHeader5() -> [UInt8] { return msgid.hlBytes }

    func payload5() -> [UInt8] {

        var payload = [UInt8]()

        for qos in grantedQos {
            payload.append(qos.rawValue)
        }

        return payload
    }

    func properties() -> [UInt8] { return [] }

    func allData() -> [UInt8] {

        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader5()
        allData += properties()
        allData += payload5()

        return allData
    }

    func variableHeader() -> [UInt8] { return msgid.hlBytes }

    func payload() -> [UInt8] {

        var payload = [UInt8]()

        for qos in grantedQos {
            payload.append(qos.rawValue)
        }

        return payload
    }
}

extension FrameSubAck: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {
        guard packetFixedHeaderType == FrameType.suback.rawValue else { return nil }
        self.packetFixedHeaderType = packetFixedHeaderType

        let decoded = MqttDecodeSubAck()
        guard decoded.decodeSubAck(fixedHeader: packetFixedHeaderType,
                                   pubAckData: bytes,
                                   protocolVersion: protocolVersion) else { return nil }

        msgid = decoded.msgid
        reasonCodes = decoded.reasonCodes
        grantedQos = decoded.reasonCodes.map { reasonCode in
            switch reasonCode {
            case .grantedQoS0: return .qos0
            case .grantedQoS1: return .qos1
            case .grantedQoS2: return .qos2
            default: return .FAILURE
            }
        }
        if protocolVersion == .v5 {
            subAckProperties = decoded
        }

    }
}

extension FrameSubAck: CustomStringConvertible {
    var description: String {
        return "SUBACK(id: \(msgid))"
    }
}
