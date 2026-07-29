//
//  MqttDecodePubRel.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/8/9.
//

import Foundation

public class MqttDecodePubRel: NSObject {

    var totalCount = 0
    var dataIndex = 0
    var propertyLength: Int = 0

    public var reasonCode: CocoaMQTTPUBRELReasonCode?
    public var msgid: UInt16 = 0
    public var reasonString: String?
    public var userProperty: [String: String]?
    public var userProperties = [CocoaMQTTUserProperty]()

    @available(*, deprecated, message: "Assumes MQTT 5 data; use the overload with protocolVersion")
    public func decodePubRel(fixedHeader: UInt8, pubAckData: [UInt8]) {
        _ = decodePubRel(fixedHeader: fixedHeader, pubAckData: pubAckData, protocolVersion: .v5)
    }

    @discardableResult
    public func decodePubRel(fixedHeader: UInt8,
                             pubAckData: [UInt8],
                             protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        guard fixedHeader == 0x62,
              let decoded = decodeAcknowledgement(pubAckData, protocolVersion: protocolVersion),
              let decodedReasonCode = CocoaMQTTPUBRELReasonCode(rawValue: decoded.reasonCode) else { return false }
        totalCount = pubAckData.count
        dataIndex = pubAckData.count
        propertyLength = decoded.propertyLength
        msgid = decoded.msgid
        reasonCode = decodedReasonCode
        reasonString = decoded.reasonString
        userProperty = decoded.userProperty
        userProperties = decoded.userProperties
        return true
    }

}
