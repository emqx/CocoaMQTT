//
//  MqttDecodePubRec.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/8/4.
//

import Foundation

public class MqttDecodePubRec: NSObject {

    var totalCount = 0
    var dataIndex = 0
    var propertyLength: Int = 0

    public var reasonCode: CocoaMQTTPUBACKReasonCode?
    /// PUBREC-specific reason code. `reasonCode` is retained for source compatibility.
    public var pubRecReasonCode: CocoaMQTTPUBRECReasonCode?
    public var msgid: UInt16 = 0
    public var reasonString: String?
    public var userProperty: [String: String]?
    public var userProperties = [CocoaMQTTUserProperty]()

    @discardableResult
    public func decodePubRec(fixedHeader: UInt8,
                             pubAckData: [UInt8],
                             protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        guard fixedHeader == FrameType.pubrec.rawValue,
              let decoded = decodeAcknowledgement(pubAckData, protocolVersion: protocolVersion),
              let decodedReasonCode = CocoaMQTTPUBRECReasonCode(rawValue: decoded.reasonCode) else { return false }
        totalCount = pubAckData.count
        dataIndex = pubAckData.count
        propertyLength = decoded.propertyLength
        msgid = decoded.msgid
        pubRecReasonCode = decodedReasonCode
        reasonCode = CocoaMQTTPUBACKReasonCode(rawValue: decoded.reasonCode)
        reasonString = decoded.reasonString
        userProperty = decoded.userProperty
        userProperties = decoded.userProperties
        return true
    }

}
