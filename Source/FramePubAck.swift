//
//  FramePuback.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBACK packet
struct FramePubAck: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.puback.rawValue

    // --- Attributes

    var msgid: UInt16

    // --- Attributes End

    // 3.4.2.1 PUBACK Reason Code
    public var reasonCode: CocoaMQTTPUBACKReasonCode?

    // 3.4.2.2 PUBACK Properties
    public var pubAckProperties: MqttDecodePubAck?
    // 3.4.2.2.2 Reason String
    public var reasonString: String?
    // 3.4.2.2.3 User Property
    public var userProperties: [String: String]?

    /// MQTT 3.1.1
    init(msgid: UInt16) {
        self.msgid = msgid
    }

    /// MQTT 5.0
    init(msgid: UInt16, reasonCode: CocoaMQTTPUBACKReasonCode) {
        self.msgid = msgid
        self.reasonCode = reasonCode
    }
}

extension FramePubAck {

    func fixedHeader() -> [UInt8] {

        var header = [UInt8]()
        header += [FrameType.puback.rawValue]

        return header
    }

    func variableHeader5() -> [UInt8] {

        // 3.4.2 MSB+LSB
        var header = msgid.hlBytes
        // 3.4.2.1 PUBACK Reason Code
        header += [reasonCode!.rawValue]

        // MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)

        return header
    }

    func payload5() -> [UInt8] { return [] }

    func properties() -> [UInt8] {

        var properties = [UInt8]()

        // 3.4.2.2.2 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }

        // 3.4.2.2.3 User Property
        if let userProperty = self.userProperties {
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

extension FramePubAck: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {
        guard packetFixedHeaderType == FrameType.puback.rawValue else {
            return nil
        }

        // MQTT 5.0 bytes.count == 4
        guard bytes.count >= 2 else {
            return nil
        }

        if protocolVersion == .v5 {
            let decodedProperties = MqttDecodePubAck()
            guard decodedProperties.decodePubAck(fixedHeader: packetFixedHeaderType,
                                                 pubAckData: bytes,
                                                 protocolVersion: protocolVersion) else { return nil }
            pubAckProperties = decodedProperties
            reasonCode = decodedProperties.reasonCode
        } else {
            guard bytes.count == 2 else { return nil }
        }

        msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
        guard msgid != 0 else { return nil }
    }
}

extension FramePubAck: CustomStringConvertible {
    var description: String {
        return "PUBACK(id: \(msgid))"
    }
}
