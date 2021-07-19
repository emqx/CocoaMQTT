//
//  ConnectFrame.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT CONNECT Frame
struct FrameConnect: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.connect.rawValue
//    private let PROTOCOL_LEVEL = UInt8(4)
//    private let PROTOCOL_VERSION: String  = "MQTT/5.0"
//    private let PROTOCOL_MAGIC: String = "MQTT"

    // --- Attributes

    //3.1.2.1

    let protocolName: String = "MQTT"
    //3.1.2.2 Protocol Version
    let protocolVersion = UInt8(5)

    //3.1.2.5 Will Flag
    var willMsg: CocoaMQTTMessage?
    //3.1.2.6 Will QoS
    var willQoS: UInt8?
    //3.1.2.7 Will Retain
    var willRetain: Bool = true
    //3.1.2.8 User Name Flag
    var username: String?
    //3.1.2.9 Password Flag
    var password: String?
    //3.1.2.10 Keep Alive
    var keepAlive: UInt16 = 10
    var cleansess: Bool = true

    //3.1.2.11.1 Property Length
    var propertyLength: UInt8?
    //3.1.2.11.2 Session Expiry Interval
    var sessionExpiryInterval: UInt32?
    //3.1.2.11.3 Receive Maximum
    var receiveMaximum: UInt16?
    //3.1.2.11.4 Maximum Packet Size
    var maximumPacketSize: UInt32?
    //3.1.2.11.5 Topic Alias Maximum
    var topicAliasMaximum: UInt16?
    //3.1.2.11.6 Request Response Information
    var requestResponseInformation: UInt8?
    //3.1.2.11.7 Request Problem Information
    var requestProblemInfomation: UInt8?
    //3.1.2.11.8 User Property
    var userProperties: [String: String]?
    //3.1.2.11.9 Authentication Method
    var authenticationMethod: String?
    //3.1.2.11.10 Authentication Data
    var authenticationData: Data?


    //3.1.3.1 Client Identifier (ClientID)
    var clientID: String
    //3.1.3.2 Will Properties
    var willProperties: Data?
    //3.1.3.2.2 Will Delay Interval
    var willDelayInterval: Int?
    //3.1.3.2.3 Payload Format Indicator
    var payloadFormatIndicator: UInt8?
    //3.1.3.2.4 Message Expiry Interval
    var messageExpiryInterval: UInt32?

    //3.1.3.2.5 Content Type
    var contentType: String?
    //3.1.3.2.6 Response Topic
    var responseTopic: String?
    //3.1.3.2.7 Correlation Data
    var correlationData: Data?
    //3.1.3.2.8 User Property
    var willUserProperties: [String: String]?
    //3.1.3.3 Will Topic
    var willTopic: String?
    //3.1.3.4 Will Payload
    var willPayload: Data?


    // --- Attributes End

    init(clientID: String) {
        self.clientID = clientID
    }
}

extension FrameConnect {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.connect.rawValue]
        header += [UInt8(variableHeader().count + payload().count)]

        return header
    }

    func variableHeader() -> [UInt8] {
        var header = [UInt8]()
        var flags = ConnFlags()

        //-----------------------
        //3.1.2.1 Protocol Name
        header += protocolName.bytesWithLength

        //3.1.2.2 Protocol Version
        header.append(protocolVersion)

        //3.1.2.3 Connect Flags
        if let will = willMsg {
            flags.flagWill = true
            flags.flagWillQoS = will.qos.rawValue
            flags.flagWillRetain = will.retained
        }

        if let _ = username {
            flags.flagUsername = true

            // Append password attribute if username presented
            if let _ = password {
                flags.flagPassword = true
            }
        }

        flags.flagCleanSession = cleansess

        header.append(flags.rawValue)
        header += keepAlive.hlBytes

        //MQTT 5.0
        header.append(UInt8(self.properties().count))
        header += self.properties()

        return header
    }

    func properties() -> [UInt8] {
        var properties = [UInt8]()

        //3.1.2.11.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }

        // 3.1.2.11.3 Receive Maximum
        if let receiveMaximum = self.receiveMaximum {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.receiveMaximum.rawValue, value: receiveMaximum.hlBytes)
        }

        // 3.1.2.11.4 Maximum Packet Size
        if let maximumPacketSize = self.maximumPacketSize {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.maximumPacketSize.rawValue, value: maximumPacketSize.byteArrayLittleEndian)
        }

        // 3.1.2.11.5 Topic Alias Maximum
        if let topicAliasMaximum = self.topicAliasMaximum {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.topicAliasMaximum.rawValue, value: topicAliasMaximum.hlBytes)
        }

        // 3.1.2.11.6 Request Response Information
        if let requestResponseInformation = self.requestResponseInformation {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.requestResponseInformation.rawValue, value: [requestResponseInformation])
        }
        // 3.1.2.11.7 Request Problem Information
        if let requestProblemInfomation = self.requestProblemInfomation {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.requestProblemInfomation.rawValue, value: [requestProblemInfomation])
        }
        // 3.1.2.11.8 User Property
        if let userProperty = self.userProperties {
            let dictValues = [String](userProperty.values)
            for (value) in dictValues {
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: value.bytesWithLength)
            }
        }
        // 3.1.2.11.9 Authentication Method
        if let authenticationMethod = self.authenticationMethod {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.authenticationMethod.rawValue, value: authenticationMethod.bytesWithLength)
        }
        // 3.1.2.11.10 Authentication Data
        if let authenticationData = self.authenticationData {
            properties += authenticationData
        }

        return properties
    }

    func payload() -> [UInt8] {
        var payload = [UInt8]()

        payload += clientID.bytesWithLength

        if let will = willMsg {
            payload += will.topic.bytesWithLength
            payload += UInt16(will.payload.count).hlBytes
            payload += will.payload
        }
        if let username = username {
            payload += username.bytesWithLength

            // Append password attribute if username presented
            if let password = password {
                payload += password.bytesWithLength
            }
        }


        return payload
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

extension FrameConnect: CustomStringConvertible {

    var description: String {
        return "CONNECT(id: \(clientID), username: \(username ?? "nil"), " +
               "password: \(password ?? "nil"), keepAlive : \(keepAlive), " +
               "cleansess: \(cleansess))"
    }
}


/// Connect Flags
private struct ConnFlags {

    /// These Flags consist of following flags:
    ///
    ///    +----------+----------+------------+--------------------+--------------+----------+
    ///    |     7    |    6     |      5     |  4   3  |     2    |       1      |     0    |
    ///    +----------+----------+------------+---------+----------+--------------+----------+
    ///    | username | password | willretain | willqos | willflag | cleansession | reserved |
    ///    +----------+----------+------------+---------+----------+--------------+----------+
    ///
    var rawValue: UInt8 = 0

    var flagUsername: Bool {
        get {
            return Bool(bit: (rawValue >> 7) & 0x01)
        }

        set {
            rawValue = (rawValue & 0x7F) | (newValue.bit << 7)
        }
    }

    var flagPassword: Bool {
        get {
            return Bool(bit:(rawValue >> 6) & 0x01)
        }

        set {
            rawValue = (rawValue & 0xBF) | (newValue.bit << 6)
        }
    }

    var flagWillRetain: Bool {
        get {
            return Bool(bit: (rawValue >> 5) & 0x01)
        }

        set {
            rawValue = (rawValue & 0xDF) | (newValue.bit << 5)
        }
    }

    var flagWillQoS: UInt8 {
        get {
            return (rawValue >> 3) & 0x03
        }

        set {
            rawValue = (rawValue & 0xE7) | (newValue << 3)
        }
    }

    var flagWill: Bool {
        get {
            return Bool(bit:(rawValue >> 2) & 0x01)
        }

        set {
            rawValue = (rawValue & 0xFB) | (newValue.bit << 2)
        }
    }

    var flagCleanSession: Bool {
        get {
            return Bool(bit: (rawValue >> 1) & 0x01)
        }

        set {
            rawValue = (rawValue & 0xFD) | (newValue.bit << 1)

        }
    }
}

