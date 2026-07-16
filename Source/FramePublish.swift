//
//  FramePublish.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

// MQTT PUBLISH Frame
struct FramePublish: Frame {

    // 3.3.1.4 Remaining Length
    public var remainingLength: UInt32?

    // 3.3.2.1 Topic Name
    public var topicName: String?
    // 3.3.2.2 Packet Identifier
    public var packetIdentifier: UInt16?

    // 3.3.2.3 PUBLISH Properties
    public var publishProperties: MqttPublishProperties?
    public var publishRecProperties: MqttDecodePublish?

    var packetFixedHeaderType: UInt8 = FrameType.publish.rawValue

    // --- Attributes

    var msgid: UInt16

    var topic: String = ""

    var _payload: [UInt8] = []

    var mqtt5Topic: String = ""

    /// Local-only identifier used to associate a queued publish with its original message.
    /// QoS 0 packets have no MQTT Packet Identifier, so this value must not be encoded.
    var deliveryToken: UInt64?

    /// Full topic used only when persisting an alias-only MQTT 5 PUBLISH. Topic Alias
    /// mappings do not survive a network reconnect, so stored packets must be standalone.
    var persistenceTopic: String?

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

        return header
    }

    func variableHeader5() -> [UInt8] {

        // 3.3.2.1 Topic Name
        var header = self.topic.bytesWithLength
        // 3.3.2.2 Packet Identifier qos1 or qos2
        if qos > .qos0 {
            header += msgid.hlBytes
            //            header.append(UInt8(0))
            //            header.append(QoS.rawValue)
        }

        // MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)

        return header
    }

    func payload5() -> [UInt8] { return _payload }

    func properties() -> [UInt8] {

        // Properties
        return publishProperties?.properties ?? []
    }

    func allData() -> [UInt8] {

        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader5()
        allData += properties()
        allData += payload5()

        return allData
    }

    func variableHeader() -> [UInt8] {

        var header = topic.bytesWithLength

        if qos > .qos0 {
            header += msgid.hlBytes
        }

        return header
    }

    func payload() -> [UInt8] { return _payload }
}

extension FramePublish: InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        self.init(packetFixedHeaderType: packetFixedHeaderType, bytes: bytes, protocolVersion: .v311)
    }

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8], protocolVersion: CocoaMQTTProtocolVersion) {

        guard packetFixedHeaderType & 0xF0 == FrameType.publish.rawValue else {
            return nil
        }
        guard let recQos = CocoaMQTTQoS(rawValue: (packetFixedHeaderType & 0b0000_0110) >> 1) else {
            return nil
        }
        guard recQos != .FAILURE else { return nil }
        guard recQos != .qos0 || packetFixedHeaderType & 0x08 == 0 else { return nil }
        self.packetFixedHeaderType = packetFixedHeaderType

        // Packet Identifier
        // The Packet Identifier field is only present in PUBLISH packets where the QoS level is 1 or 2.

        let pos: Int
        if protocolVersion == .v5 {
            let data = MqttDecodePublish()
            guard data.decodePublish(fixedHeader: packetFixedHeaderType,
                                     publishData: bytes,
                                     protocolVersion: protocolVersion) else { return nil }
            pos = data.mqtt5DataIndex + (data.propertyLength ?? 0)

            // MQTT 5.0: Topic Name may be empty only when Topic Alias is present.
            if data.topic.isEmpty && data.topicAlias == nil {
                return nil
            }

            // MQTT 5.0
            self.mqtt5Topic = data.topic
            self.topic = data.topic
            self.packetIdentifier = data.packetIdentifier
            self.msgid = data.packetIdentifier ?? 0
            self.publishRecProperties = data

        } else {
            // MQTT 3.1.1
            guard var reader = MQTTByteReader(bytes),
                  let recTopic = reader.readUTF8String(), !recTopic.isEmpty,
                  !recTopic.contains("+"), !recTopic.contains("#") else { return nil }
            topic = recTopic
            if recQos == .qos0 {
                msgid = 0
            } else {
                guard let identifier = reader.readUInt16(), identifier != 0 else { return nil }
                msgid = identifier
            }
            pos = reader.index
        }

        // payload
        if pos == bytes.count {
            _payload = []
        } else if pos < bytes.count {
            _payload = [UInt8](bytes[pos..<bytes.count])
        } else {
            return nil
        }

        if protocolVersion == .v5,
           publishRecProperties?.payloadFormatIndicator == .utf8,
           String(bytes: _payload, encoding: .utf8) == nil {
            return nil
        }

    }
}

extension FramePublish: CustomStringConvertible {
    var description: String {
        return "PUBLISH(id: \(msgid), topic: \(topic), payload: \(_payload.summary))"
    }
}
