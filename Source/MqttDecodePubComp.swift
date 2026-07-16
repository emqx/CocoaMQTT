//
//  MqttDecodePubComp.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/8/9.
//

import Foundation

public class MqttDecodePubComp: NSObject {

    var totalCount = 0
    var dataIndex = 0
    var propertyLength: Int = 0

    public var reasonCode: CocoaMQTTPUBCOMPReasonCode?
    public var msgid: UInt16 = 0
    public var reasonString: String?
    public var userProperty: [String: String]?

    @discardableResult
    public func decodePubComp(fixedHeader: UInt8,
                              pubAckData: [UInt8],
                              protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        guard fixedHeader == FrameType.pubcomp.rawValue,
              let decoded = decodeAcknowledgement(pubAckData, protocolVersion: protocolVersion),
              let decodedReasonCode = CocoaMQTTPUBCOMPReasonCode(rawValue: decoded.reasonCode) else { return false }
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
