//
//  FrameConnack.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


struct FrameConnAck: Frame {

    init(code: CocoaMQTTCONNACKReasonCode) {
        reasonCode = code
    }

    var fixedHeader: UInt8 = FrameType.connack.rawValue
    
    // --- Attributes
    
    var reasonCode: CocoaMQTTCONNACKReasonCode

    //3.2.2.1.1 Session Present
    var sessPresent: Bool = false
    
    // --- Attributes End

    //3.2.2.3 CONNACK Properties
    //3.2.2.3.1 Property Length
    var propertyLength: UInt32?
    //3.2.2.3.2 Session Expiry Interval
    var sessionExpiryInterval: UInt32?
    //3.2.2.3.3 Receive Maximum
    var receiveMaximum: UInt16?
    //3.2.2.3.4 Maximum QoS
    var maximumQoS: CocoaMQTTCONNACKMaximumQoS?
    //3.2.2.3.5 Retain Available
    var retainAvailable: Bool?
    //3.2.2.3.6 Maximum Packet Size
    var maximumPacketSize: UInt32?
    //3.2.2.3.7 Assigned Client Identifier
    var assignedClientIdentifier: String?
    //3.2.2.3.8 Topic Alias Maximum
    var topicAliasMaximum: UInt16?
    //3.2.2.3.9 Reason String
    var reasonString: String?
    //3.2.2.3.10 User Property
    var userProperties: [String: String]?
    //3.2.2.3.11 Wildcard Subscription Available
    var wildcardSubscriptionAvailable: Bool?
    //3.2.2.3.12 Subscription Identifiers Available
    var subscriptionIdentifiersAvailable: Bool?
    //3.2.2.3.13 Shared Subscription Available
    var sharedSubscriptionAvailable: Bool?
    //3.2.2.3.14 Server Keep Alive
    var serverKeepAlive: UInt16?
    //3.2.2.3.15 Response Information
    var responseInformation: String?
    //3.2.2.3.16 Server Reference
    var serverReference: String?
    //3.2.2.3.17 Authentication Method
    var authenticationMethod: String?
    //3.2.2.3.18 Authentication Data
    var authenticationData = [UInt8]()

    //3.2.3 CONNACK Payload
    //The CONNACK packet has no Payload.


}

extension FrameConnAck {
    
    func variableHeader() -> [UInt8] {
        return [sessPresent.bit, reasonCode.rawValue]
    }
    
    func payload() -> [UInt8] { return [] }

    func properties() -> [UInt8] { return [] }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData.append(fixedHeader)
        allData += variableHeader()
        allData += properties()
        allData += payload()

        return allData
    }
}

extension FrameConnAck: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        guard fixedHeader == FrameType.connack.rawValue else {
            return nil
        }
        
        guard bytes.count == 2 || bytes.count == 19 else {
            return nil
        }
        
        sessPresent = Bool(bit: bytes[0] & 0x01)
        
        guard let ack = CocoaMQTTCONNACKReasonCode(rawValue: bytes[1]) else {
            return nil
        }
        reasonCode = ack


        //3.2.2.3 CONNACK Properties
        var index = 2
        let propertyLengthVariableByteInteger = variableByteInteger(data: bytes, offset: index)
        propertyLength = UInt32(propertyLengthVariableByteInteger.res)
        index = propertyLengthVariableByteInteger.newOffset


        // properties

        while UInt32(index) - UInt32(propertyLengthVariableByteInteger.newOffset) < propertyLength! {
            let resVariableByteInteger = variableByteInteger(data: bytes, offset: index)
            index = resVariableByteInteger.newOffset
            let propertyNameByte = resVariableByteInteger.res
            guard let propertyName = CocoaMQTTPropertyName(rawValue: UInt8(propertyNameByte)) else {
                return nil
            }
            switch propertyName.rawValue {
            case CocoaMQTTPropertyName.sessionExpiryInterval.rawValue:
                sessionExpiryInterval = UInt32(integerCompute(data: bytes, formatType: formatInt.formatUint32.rawValue, offset: index)!)
                index += 4
            case CocoaMQTTPropertyName.receiveMaximum.rawValue:
                receiveMaximum = UInt16(integerCompute(data: bytes, formatType: formatInt.formatUint16.rawValue, offset: index)!)
                index += 2
            case CocoaMQTTPropertyName.maximumQoS.rawValue:
                if index > bytes.count {
                    return nil
                }
                if bytes[index] & 0x01 > 0 {
                    maximumQoS = .qos0
                } else {
                    maximumQoS = .qos1
                }

                index += 1
            case CocoaMQTTPropertyName.retainAvailable.rawValue:
                if index > bytes.count  {
                    return nil
                }
                if bytes[index] & 0x01 > 0 {
                    retainAvailable = true
                } else {
                    retainAvailable = false
                }
                index += 1
            case CocoaMQTTPropertyName.maximumPacketSize.rawValue:
                maximumPacketSize = UInt32(integerCompute(data: bytes, formatType: formatInt.formatUint32.rawValue, offset: index)!)
                index += 4
            case CocoaMQTTPropertyName.assignedClientIdentifier.rawValue:
                guard let result = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                assignedClientIdentifier = result.resStr
                index = result.newOffset
            case CocoaMQTTPropertyName.topicAliasMaximum.rawValue:
                topicAliasMaximum = UInt16(integerCompute(data: bytes, formatType: formatInt.formatUint16.rawValue, offset: index)!)
                index += 2
            case CocoaMQTTPropertyName.reasonString.rawValue:
                guard let result = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                reasonString = result.resStr
                index = result.newOffset
            case CocoaMQTTPropertyName.userProperty.rawValue:
                var key:String?
                var value:String?
                guard let keyRes = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                key = keyRes.resStr
                index = keyRes.newOffset

                guard let valRes = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                value = valRes.resStr
                index = valRes.newOffset

                userProperties![key!] = value
                
            case CocoaMQTTPropertyName.wildcardSubscriptionAvailable.rawValue:
                if index > bytes.count  {
                    return nil
                }
                if bytes[index] & 0x01 > 0 {
                    wildcardSubscriptionAvailable = true
                } else {
                    wildcardSubscriptionAvailable = false
                }
                index += 1
            case CocoaMQTTPropertyName.subscriptionIdentifiersAvailable.rawValue:
                if index > bytes.count  {
                    return nil
                }
                if bytes[index] & 0x01 > 0 {
                    subscriptionIdentifiersAvailable = true
                } else {
                    subscriptionIdentifiersAvailable = false
                }
                index += 1
            case CocoaMQTTPropertyName.sharedSubscriptionAvailable.rawValue:
                if index > bytes.count  {
                    return nil
                }
                if bytes[index] & 0x01 > 0 {
                    sharedSubscriptionAvailable = true
                } else {
                    sharedSubscriptionAvailable = false
                }
                index += 1
            case CocoaMQTTPropertyName.serverKeepAlive.rawValue:
                serverKeepAlive = UInt16(integerCompute(data: bytes, formatType: formatInt.formatUint16.rawValue, offset: index)!)
                    index += 2
            case CocoaMQTTPropertyName.responseInformation.rawValue:
                guard let valRes = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                responseInformation = valRes.resStr
                index = valRes.newOffset
            case CocoaMQTTPropertyName.serverReference.rawValue:
                guard let valRes = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                serverReference = valRes.resStr
                index = valRes.newOffset
            case CocoaMQTTPropertyName.authenticationMethod.rawValue:
                guard let valRes = unsignedByteToString(data: bytes, offset: index) else {
                    return nil
                }
                authenticationMethod = valRes.resStr
                index = valRes.newOffset
            case CocoaMQTTPropertyName.authenticationData.rawValue:
                guard let valRes = unsignedByteToBinary(data: bytes, offset: index) else {
                    return nil
                }
                authenticationData = valRes.resStr
                index = valRes.newOffset


            default:
                return nil
            }

           
        }



    }
}

extension FrameConnAck: CustomStringConvertible {
    var description: String {
        return "CONNACK(code: \(reasonCode), sp: \(sessPresent))"
    }
}
