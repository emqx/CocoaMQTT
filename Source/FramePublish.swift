//
//  FramePublish.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT PUBLISH Frame
struct FramePublish: Frame {

    //3.3.1.1 DUP
    public var DUP: Bool = false
    //3.3.1.2 QoS
    public var QoS: CocoaMQTTCONNACKMaximumQoS = .qos2
    //3.3.1.3 RETAIN
    public var retain: Bool = false
    //3.3.1.4 Remaining Length
    public var remainingLength: UInt32?

    //3.3.2.1 Topic Name
    public var topicName: String?
    //3.3.2.2 Packet Identifier
    public var packetIdentifier: UInt16?
    //3.3.2.3.1 Property Length
    public var propertyLength: UInt16?
    //3.3.2.3.2 Payload Format Indicator
    public var payloadFormatIndicator: PayloadFormatIndicator?
    //3.3.2.3.3 Message Expiry Interval
    public var messageExpiryInterval: UInt32?
    //3.3.2.3.4 Topic Alias
    public var topicAlias: UInt16?
    //3.3.2.3.5 Response Topic
    public var responseTopic: String?
    //3.3.2.3.6 Correlation Data
    public var correlationData: [UInt8]?
    //3.3.2.3.7 Property
    public var userProperty: [String: String]?
    //3.3.2.3.8 Subscription Identifier
    public var subscriptionIdentifier: UInt32?
    //3.3.2.3.9 Content Type
    public var contentType: String?


    var packetFixedHeaderType: UInt8 = FrameType.publish.rawValue
    
    // --- Attributes
    
    var msgid: UInt16
    
    var topic: String
    
    var _payload: [UInt8] = []

    var applicationMessage: [UInt8]?

    // --- Attributes End
    
    init(topic: String, payload: [UInt8], qos: CocoaMQTTQoS = .qos0, msgid: UInt16 = 0) {
        self.topic = topic
        self._payload = payload
        self.msgid = msgid
        
        self.qos = qos
    }
}

extension FramePublish {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.publish.rawValue]
        header += [UInt8(variableHeader().count + payload().count)]

        return header
    }
    
    func variableHeader() -> [UInt8] {

        //3.3.2.1 Topic Name
        var header = topic.bytesWithLength
        //3.3.2.2 Packet Identifier qos1 or qos2
        if qos > .qos0 {
            header += msgid.hlBytes
        }

        //MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)
        header += self.properties()

        return header
    }
    
    func payload() -> [UInt8] { return _payload }

    func properties() -> [UInt8] {
        var properties = [UInt8]()

        //3.3.2.3.2  Payload Format Indicator
        if let payloadFormatIndicator = self.payloadFormatIndicator {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.payloadFormatIndicator.rawValue, value: [payloadFormatIndicator.rawValue])
        }
        //3.3.2.3.3  Message Expiry Interval
        if let messageExpiryInterval = self.messageExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.willExpiryInterval.rawValue, value: messageExpiryInterval.byteArrayLittleEndian)
        }
        //3.3.2.3.4 Topic Alias
        if let topicAlias = self.topicAlias {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.topicAlias.rawValue, value: topicAlias.hlBytes)
        }
        //3.3.2.3.5 Response Topic
        if let responseTopic = self.responseTopic {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.responseTopic.rawValue, value: responseTopic.bytesWithLength)
        }
        //3.3.2.3.6 Correlation Data
        if let correlationData = self.correlationData {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.correlationData.rawValue, value: correlationData)
        }
        //3.3.2.3.7 Property Length User Property
        if let userProperty = self.userProperty {
            let dictValues = [String](userProperty.values)
            for (value) in dictValues {
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: value.bytesWithLength)
            }
        }
        //3.3.2.3.8 Subscription Identifier
        if let subscriptionIdentifier = self.subscriptionIdentifier {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.subscriptionIdentifier.rawValue, value: subscriptionIdentifier.byteArrayLittleEndian)
        }
        //3.3.2.3.9 Content Type
        if let contentType = self.contentType {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.contentType.rawValue, value: contentType.bytesWithLength)
        }



        return properties
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

extension FramePublish: InitialWithBytes {
    
    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        
        guard packetFixedHeaderType & 0xF0 == FrameType.publish.rawValue else {
            return nil
        }


        // Reserved
        var flags: UInt8 = 0

        if retain {
            flags = flags | 0b0000_0001
        } else {
            flags = flags | 0b0000_0000
        }

        if DUP {
            flags = flags | 0b0011_1000
        } else {
            flags = flags | 0b0011_0000
        }
        
        switch QoS {
        case .qos0:
            flags = flags | 0b0011_0000
        case .qos1:
            flags = flags | 0b0011_0010
        case .qos2:
            flags = flags | 0b0011_0100
        }
        self.packetFixedHeaderType = flags


        // parse topic
        if bytes.count < 2 {
            return nil
        }
        
        let len = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
        
        var pos = 2 + Int(len)
        
        if bytes.count < pos {
            return nil
        }
        
        topic = NSString(bytes: [UInt8](bytes[2...(pos-1)]), length: Int(len), encoding: String.Encoding.utf8.rawValue)! as String
        
        // msgid
        if (packetFixedHeaderType & 0x06) >> 1 == CocoaMQTTQoS.qos0.rawValue {
            msgid = 0
        } else {
            if bytes.count < pos + 2 {
                return nil
            }
            msgid = UInt16(bytes[pos]) << 8 + UInt16(bytes[pos+1])
            pos += 2
        }
        
        // payload
        if (pos == bytes.count) {
            _payload = []
        } else if (pos < bytes.count) {
            _payload = [UInt8](bytes[pos..<bytes.count])
        } else {
            return nil
        }

    }
}

extension FramePublish: CustomStringConvertible {
    var description: String {
        return "PUBLISH(id: \(msgid), topic: \(topic), payload: \(_payload.summary))"
    }
}
