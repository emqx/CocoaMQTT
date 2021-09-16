//
//  FrameAuth.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/4.
//

import Foundation


struct FrameAuth: Frame {


    var packetFixedHeaderType: UInt8 = FrameType.auth.rawValue

    //3.15.2.1 Authenticate Reason Code
    var reasonCode: CocoaMQTTAUTHReasonCode
    
    //3.15.2.2 AUTH Properties
    var authProperties: MqttAuthProperties?

    init(reasonCode: CocoaMQTTAUTHReasonCode,authProperties: MqttAuthProperties) {
        self.reasonCode = reasonCode
        self.authProperties = authProperties
    }

}



extension FrameAuth {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.connect.rawValue]
        header += [UInt8(variableHeader().count)]

        return header
    }

    func variableHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [reasonCode.rawValue]
        //MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)
   
        return header
    }

    func payload() -> [UInt8] { return []}

    func properties() -> [UInt8] {
        return authProperties!.properties
    }

    func allData() -> [UInt8] {
        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader()
        allData += properties()
        allData += payload()

        return allData
    }
}


