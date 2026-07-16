//
//  MqttDecodeSubAck.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/8/12.
//

import Foundation

public class MqttDecodeSubAck: NSObject {

    var totalCount = 0
    var dataIndex = 0
    var propertyLength: Int = 0

    public var reasonCodes: [CocoaMQTTSUBACKReasonCode] = []
    // public var reasonCode: CocoaMQTTSUBACKReasonCode?
    public var msgid: UInt16 = 0
    public var reasonString: String?
    public var userProperty: [String: String]?

    @discardableResult
    public func decodeSubAck(fixedHeader: UInt8,
                             pubAckData: [UInt8],
                             protocolVersion: CocoaMQTTProtocolVersion) -> Bool {
        guard fixedHeader == FrameType.suback.rawValue,
              let decoded = decodeReasonCodeList(pubAckData, protocolVersion: protocolVersion),
              !decoded.reasonCodes.isEmpty else { return false }
        if protocolVersion == .v311 {
            let validCodes: Set<UInt8> = [0x00, 0x01, 0x02, 0x80]
            guard decoded.reasonCodes.allSatisfy(validCodes.contains) else { return false }
        }
        let codes = decoded.reasonCodes.compactMap(CocoaMQTTSUBACKReasonCode.init(rawValue:))
        guard codes.count == decoded.reasonCodes.count else { return false }
        totalCount = pubAckData.count
        dataIndex = pubAckData.count
        propertyLength = decoded.propertyLength
        msgid = decoded.msgid
        reasonString = decoded.reasonString
        userProperty = decoded.userProperty
        reasonCodes = codes
        return true
    }

}
