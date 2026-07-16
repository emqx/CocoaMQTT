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

    var packetFixedHeaderType: UInt8 = FrameType.unsuback.rawValue

    // --- Attributes

    var msgid: UInt16

    // --- Attributes End

    // 3.10.2.1 UNSUBSCRIBE Properties
    public var unSubAckProperties: MqttDecodeUnsubAck?
    // 3.11.2 Property
    public var userProperty: [String: String]?
    // 3.11.2.1.2 Reason String
    public var reasonString: String?

    var _payload: [UInt8] = []

    init(msgid: UInt16, payload: [UInt8]) {
        self.msgid = msgid
        self._payload = payload
    }
}

extension FrameUnsubAck {

    func fixedHeader() -> [UInt8] {

        var header = [UInt8]()
        header += [FrameType.unsuback.rawValue]

        return header
    }

    func variableHeader5() -> [UInt8] {

        // 3.11.2 MSB+LSB
        var header = msgid.hlBytes

        // MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)

        return header
    }

    func payload5() -> [UInt8] { return _payload }

    func properties() -> [UInt8] {

        var properties = [UInt8]()

        // 3.11.2.1.2 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }

        // 3.11.2.1.3 User Property
        if let userProperty = self.userProperty {
            properties += userProperty.userPropertyBytes
        }

        return properties
    }

    func allData() -> [UInt8] {

        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader5()
        allData += properties()
        allData += payload5()

        return allData
    }

    func variableHeader() -> [UInt8] { return msgid.hlBytes }

    func payload() -> [UInt8] { return [] }
}

extension FrameUnsubAck: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {
        guard packetFixedHeaderType == FrameType.unsuback.rawValue else {
            return nil
        }

        guard bytes.count >= 2 else {
            return nil
        }

        let decoded = MqttDecodeUnsubAck()
        guard decoded.decodeUnSubAck(fixedHeader: packetFixedHeaderType,
                                     pubAckData: bytes,
                                     protocolVersion: protocolVersion) else { return nil }
        msgid = decoded.msgid
        if protocolVersion == .v5 { unSubAckProperties = decoded }

    }
}

extension FrameUnsubAck: CustomStringConvertible {
    var description: String {
        return "UNSUBSACK(id: \(msgid))"
    }
}
