//
//  FrameAuth.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/4.
//

import Foundation

struct FrameAuth: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.auth.rawValue

    // 3.15.2.1 Authenticate Reason Code
    var sendReasonCode: CocoaMQTTAUTHReasonCode?
    var receiveReasonCode: CocoaMQTTAUTHReasonCode?

    // 3.15.2.2 AUTH Properties
    var authProperties: MqttAuthProperties?

    init(reasonCode: CocoaMQTTAUTHReasonCode, authProperties: MqttAuthProperties) {
        self.sendReasonCode = reasonCode
        self.authProperties = authProperties
    }

}

extension FrameAuth {

    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.auth.rawValue]
        // header += [UInt8(variableHeader5().count)]

        return header
    }

    func variableHeader5() -> [UInt8] {
        var header = [UInt8]()
        header += [sendReasonCode!.rawValue]
        // MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)

        return header
    }

    func payload5() -> [UInt8] { return []}

    func properties() -> [UInt8] {
        return authProperties?.properties ?? []

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

extension FrameAuth: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {
        guard protocolVersion == .v5, packetFixedHeaderType == FrameType.auth.rawValue else { return nil }
        guard var reader = MQTTByteReader(bytes),
              let reasonByte = reader.readByte(),
              let reasonCode = CocoaMQTTAUTHReasonCode(rawValue: reasonByte) else { return nil }
        receiveReasonCode = reasonCode
        guard let propertyLength = reader.readVariableByteInteger(),
              var properties = reader.readSection(length: propertyLength),
              reader.isAtEnd else { return nil }

        let decodedProperties = MqttAuthProperties()
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
            case .authenticationMethod:
                guard let value = properties.readUTF8String() else { return nil }
                decodedProperties.authenticationMethod = value
            case .authenticationData:
                guard let value = properties.readBinaryData() else { return nil }
                decodedProperties.authenticationData = value
            case .reasonString:
                guard let value = properties.readUTF8String() else { return nil }
                decodedProperties.reasonString = value
            case .userProperty:
                guard let key = properties.readUTF8String(),
                      let value = properties.readUTF8String() else { return nil }
                if decodedProperties.userProperties == nil { decodedProperties.userProperties = [:] }
                decodedProperties.userProperties?[key] = value
            default:
                return nil
            }
        }
        guard decodedProperties.authenticationMethod != nil else { return nil }
        authProperties = decodedProperties
    }

}
