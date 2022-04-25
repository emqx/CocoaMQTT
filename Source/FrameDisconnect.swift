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

    //3.14.2 DISCONNECT Variable Header
    public var sendReasonCode: CocoaMQTTDISCONNECTReasonCode?
    public var receiveReasonCode: CocoaMQTTDISCONNECTReasonCode?

    //3.14.2.2.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?
    
    //3.14.2.2.3 Reason String
    public var reasonString: String?
    //3.14.2.2.4 User Property
    public var userProperties: [String: String]?
    //3.14.2.2.5 Server Reference
    public var serverReference: String?

    ///MQTT 3.1.1
    init() { /* Nothing to do */ }

    ///MQTT 5.0
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

        //MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)
   

        return header
    }
    
    func payload5() -> [UInt8] { return [] }

    func properties() -> [UInt8] {
        
        var properties = [UInt8]()

        //3.14.2.2.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }
        //3.14.2.2.3 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        //3.14.2.2.4 User Property
        if let userProperty = self.userProperties {
            let dictValues = [String](userProperty.values)
            for (value) in dictValues {
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: value.bytesWithLength)
            }
        }
        //3.14.2.2.5 Server Reference
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

        var protocolVersion = "";
        if let storage = CocoaMQTTStorage() {
            protocolVersion = storage.queryMQTTVersion()
        }

        if (protocolVersion == "5.0"){
            if bytes.count > 0 {
                receiveReasonCode = CocoaMQTTDISCONNECTReasonCode(rawValue: bytes[0])
            }
        }
    }
    
}

extension FrameDisconnect: CustomStringConvertible {
    var description: String {
        return "DISCONNECT"
    }
}
