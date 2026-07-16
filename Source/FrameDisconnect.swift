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

    // 3.14.2 DISCONNECT Variable Header
    public var sendReasonCode: CocoaMQTTDISCONNECTReasonCode?
    public var receiveReasonCode: CocoaMQTTDISCONNECTReasonCode?

    // 3.14.2.2.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?

    // 3.14.2.2.3 Reason String
    public var reasonString: String?
    // 3.14.2.2.4 User Property
    public var userProperties: [String: String]?
    // 3.14.2.2.5 Server Reference
    public var serverReference: String?

    /// MQTT 3.1.1
    init() { /* Nothing to do */ }

    /// MQTT 5.0
    init(disconnectReasonCode: CocoaMQTTDISCONNECTReasonCode) {
        self.sendReasonCode = disconnectReasonCode
    }
}

extension FrameDisconnect {

    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.disconnect.rawValue]

        return header
    }

    func variableHeader5() -> [UInt8] {

        var header = [UInt8]()
        header += [sendReasonCode!.rawValue]

        // MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)

        return header
    }

    func payload5() -> [UInt8] { return [] }

    func properties() -> [UInt8] {

        var properties = [UInt8]()

        // 3.14.2.2.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }
        // 3.14.2.2.3 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        // 3.14.2.2.4 User Property
        if let userProperty = self.userProperties {
            properties += userProperty.userPropertyBytes
        }
        // 3.14.2.2.5 Server Reference
        if let serverReference = self.serverReference {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.serverReference.rawValue, value: serverReference.bytesWithLength)
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

    func variableHeader() -> [UInt8] { return [] }

    func payload() -> [UInt8] { return [] }
}

extension FrameDisconnect: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {
        guard protocolVersion == .v5, packetFixedHeaderType == FrameType.disconnect.rawValue else { return nil }
        if bytes.isEmpty {
            receiveReasonCode = .normalDisconnection
            return
        }

        guard var reader = MQTTByteReader(bytes),
              let reasonByte = reader.readByte(),
              let reasonCode = CocoaMQTTDISCONNECTReasonCode(rawValue: reasonByte) else { return nil }
        receiveReasonCode = reasonCode
        guard !reader.isAtEnd else { return }
        guard let propertyLength = reader.readVariableByteInteger(),
              var properties = reader.readSection(length: propertyLength),
              reader.isAtEnd else { return nil }

        var singleUseProperties = Set<CocoaMQTTPropertyName>()
        while !properties.isAtEnd {
            guard let identifier = properties.readVariableByteInteger(),
                  let propertyName = UInt8(exactly: identifier).flatMap(CocoaMQTTPropertyName.init(rawValue:)) else {
                return nil
            }
            if propertyName != .userProperty {
                guard singleUseProperties.insert(propertyName).inserted else { return nil }
            }
            switch propertyName {
            case .reasonString:
                guard let value = properties.readUTF8String() else { return nil }
                reasonString = value
            case .userProperty:
                guard let key = properties.readUTF8String(),
                      let value = properties.readUTF8String() else { return nil }
                if userProperties == nil { userProperties = [:] }
                userProperties?[key] = value
            case .serverReference:
                guard let value = properties.readUTF8String() else { return nil }
                serverReference = value
            default:
                // A Server MUST NOT send Session Expiry Interval in DISCONNECT.
                return nil
            }
        }
    }

}

extension FrameDisconnect: CustomStringConvertible {
    var description: String {
        return "DISCONNECT"
    }
}
