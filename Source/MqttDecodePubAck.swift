//
//  MqttDecodePuback.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/8/3.
//

import Foundation

public class MqttDecodePubAck: NSObject {

    var totalCount = 0
    var dataIndex = 0
    var propertyLength: Int = 0

    public var reasonCode: CocoaMQTTPUBACKReasonCode?
    public var msgid: UInt16 = 0
    public var reasonString: String?
    public var userProperty: [String: String]?

    @discardableResult
    public func decodePubAck(fixedHeader: UInt8,
                             pubAckData: [UInt8],
                             protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        guard fixedHeader == FrameType.puback.rawValue,
              let decoded = decodeAcknowledgement(pubAckData, protocolVersion: protocolVersion),
              let decodedReasonCode = CocoaMQTTPUBACKReasonCode(rawValue: decoded.reasonCode) else { return false }
        totalCount = pubAckData.count
        dataIndex = pubAckData.count
        propertyLength = decoded.propertyLength
        msgid = decoded.msgid
        reasonCode = decodedReasonCode
        reasonString = decoded.reasonString
        userProperty = decoded.userProperty
        return true
    }
}
