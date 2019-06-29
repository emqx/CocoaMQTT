//
//  CocoaMQTTFrame.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation

/**
 * MQTT Frame Type
 */
enum CocoaMQTTFrameType: UInt8 {
    case reserved = 0x00
    case connect = 0x10
    case connack = 0x20
    case publish = 0x30
    case puback = 0x40
    case pubrec = 0x50
    case pubrel = 0x60
    case pubcomp = 0x70
    case subscribe = 0x80
    case suback = 0x90
    case unsubscribe = 0xA0
    case unsuback = 0xB0
    case pingreq = 0xC0
    case pingresp = 0xD0
    case disconnect = 0xE0
}

/// The frame can be initialized with a bytes
protocol InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8])
}


/// MQTT Frame protocol
protocol CocoaMQTTFrame {
    /**
     * |--------------------------------------
     * | 7 6 5 4 |     3    |  2 1  | 0      |
     * |  Type   | DUP flag |  QoS  | RETAIN |
     * |--------------------------------------
     */
    var fixedHeader: UInt8 {get set}
    
    /// Some types of MQTT Control Packets contain a variable header component
    ///
    /// It is readonly property, the value decided by the attributes of frame
    var variableHeader: [UInt8] {get}
    
    /// Some MQTT Control Packets contain a payload as the final part of the packet
    var payload: [UInt8] {get set}
    
    /// Pack the attributes to variableHeader
    ///
    /// After excuting this method, the 'variableHeader' or 'payload' will be override
    mutating func pack()
}

extension CocoaMQTTFrame {

    /// The type of the Frame
    var type: CocoaMQTTFrameType {
        return  CocoaMQTTFrameType(rawValue: fixedHeader & 0xF0)!
    }
    
    /// Dup flag
    var dup: Bool {
        get {
            return ((fixedHeader & 0x08) >> 3) == 0 ? false : true
        }
        set {
            fixedHeader = (fixedHeader & 0xF7) | (newValue.bit  << 3)
        }
    }
    
    /// Qos level
    var qos: CocoaMQTTQoS {
        get {
            return CocoaMQTTQoS(rawValue: (fixedHeader & 0x06) >> 1)!
        }
        set {
            fixedHeader = (fixedHeader & 0xF9) | (newValue.rawValue << 1)
        }
    }
    
    /// Retained flag
    var retained: Bool {
        get {
            return (fixedHeader & 0x01) == 0 ? false : true
        }
        set {
            fixedHeader = (fixedHeader & 0xFE) | newValue.bit
        }
    }
    
    /// Construct a bytes array
    mutating func data() -> [UInt8] {
        self.pack()
        return [UInt8]([fixedHeader]) + remainingLength() + variableHeader + payload
    }
    
    /// Calculate the remaining length
    private func remainingLength() -> [UInt8] {
        var bytes: [UInt8] = []
        var digit: UInt8 = 0
        var len: UInt32 = UInt32(variableHeader.count + payload.count)
        
        repeat {
            digit = UInt8(len % 128)
            len = len / 128
            // if there are more digits to encode, set the top bit of this digit
            if len > 0 {
                digit = digit | 0x80
            }
            bytes.append(digit)
        } while len > 0
        
        return bytes
    }
}

/// MQTT CONNECT Frame
struct CocoaMQTTFrameConnect: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    let PROTOCOL_LEVEL = UInt8(4)
    let PROTOCOL_VERSION: String  = "MQTT/3.1.1"
    let PROTOCOL_MAGIC: String = "MQTT"

    /**
     *  The CONNECT flags
     *
     * |----------------------------------------------------------------------------------
     * |     7    |    6     |      5     |  4   3  |     2    |       1      |     0    |
     * | username | password | willretain | willqos | willflag | cleansession | reserved |
     * |----------------------------------------------------------------------------------
     */
    var connFlags: UInt8 = 0

    var flagUsername: Bool {
        get {
            return Bool(bit: (connFlags >> 7) & 0x01)
        }

        set {
            connFlags = (connFlags & 0x7F) | (newValue.bit << 7)
        }
    }

    var flagPassword: Bool {
        get {
            return Bool(bit:(connFlags >> 6) & 0x01)
        }

        set {
            connFlags = (connFlags & 0xBF) | (newValue.bit << 6)
        }
    }

    var flagWillRetain: Bool {
        get {
            return Bool(bit: (connFlags >> 5) & 0x01)
        }
        
        set {
            connFlags = (connFlags & 0xDF) | (newValue.bit << 5)
        }
    }

    var flagWillQoS: UInt8 {
        get {
            return (connFlags >> 3) & 0x03
        }
        
        set {
            connFlags = (connFlags & 0xE7) | (newValue << 3)
        }
    }

    var flagWill: Bool {
        get {
            return Bool(bit:(connFlags >> 2) & 0x01)
        }

        set {
            connFlags = (connFlags & 0xFB) | (newValue.bit << 2)
        }
    }

    var flagCleanSession: Bool {
        get {
            return Bool(bit: (connFlags >> 1) & 0x01)
        }

        set {
            connFlags = (connFlags & 0xFD) | (newValue.bit << 1)

        }
    }

    var client: CocoaMQTTClient

    // TODO: refactor?
    init(client: CocoaMQTT) {
        self.client = client
        self.fixedHeader = CocoaMQTTFrameType.connect.rawValue
    }

    mutating func pack() {
        variableHeader = []
        payload = []
        
        // variable header
        variableHeader += PROTOCOL_MAGIC.bytesWithLength
        variableHeader.append(PROTOCOL_LEVEL)

        // payload
        payload += client.clientID.bytesWithLength
        if let will = client.willMessage {
            flagWill = true
            flagWillQoS = will.qos.rawValue
            flagWillRetain = will.retained
            payload += will.topic.bytesWithLength
            payload += will.payload
        }
        if let username = client.username {
            flagUsername = true
            payload += username.bytesWithLength
        }
        if let password = client.password {
            flagPassword = true
            payload += password.bytesWithLength
        }

        // flags
        flagCleanSession = client.cleanSession
        variableHeader.append(connFlags)
        variableHeader += client.keepAlive.hlBytes
    }
}

// TODO: CONNACK Frame there

/// MQTT PUBLISH Frame
struct CocoaMQTTFramePublish: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    var topic: String

    init(msgid: UInt16, topic: String, payload: [UInt8]) {
        fixedHeader = CocoaMQTTFrameType.publish.rawValue
        self.msgid = msgid
        self.topic = topic
        self.payload = payload
    }
    
    mutating func pack() {
        variableHeader = []
        
        variableHeader += topic.bytesWithLength
        if qos.rawValue > CocoaMQTTQoS.qos0.rawValue {
            variableHeader += msgid.hlBytes
        }
    }
}

extension CocoaMQTTFramePublish: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        self.fixedHeader = fixedHeader
        
        // parse topic
        if bytes.count < 2 {
            return nil
        }
        var msb = bytes[0]
        var lsb = bytes[1]
        let len = UInt16(msb) << 8 + UInt16(lsb)
        var pos = 2 + Int(len)
        
        if bytes.count < pos {
            return nil
        }
        
        topic = NSString(bytes: [UInt8](bytes[2...(pos-1)]), length: Int(len), encoding: String.Encoding.utf8.rawValue)! as String
        
        // msgid
        if (fixedHeader & 0x06) >> 1 == CocoaMQTTQoS.qos0.rawValue {
            msgid = 0
        } else {
            if bytes.count < pos + 2 {
                return nil
            }
            msb = bytes[pos]
            lsb = bytes[pos+1]
            pos += 2
            msgid = UInt16(msb) << 8 + UInt16(lsb)
        }
        
        // payload
        let end = bytes.count - 1
        
        if (end - pos >= 0) {
            payload = [UInt8](bytes[pos...end])
            // receives an empty message
        } else {
            payload = []
        }
    }
}

extension CocoaMQTTFramePublish: CustomStringConvertible {
    var description: String {
        return "PUBLISH(msgid: \(msgid), topic: \(topic), payload: \(payload))"
    }
}

/// MQTT PUBACK
struct CocoaMQTTFramePubAck: CocoaMQTTFrame {
    
    var fixedHeader: UInt8

    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    init(msgid: UInt16) {
        fixedHeader = CocoaMQTTFrameType.puback.rawValue
        self.msgid = msgid
    }

    mutating func pack() {
        variableHeader = []
        
        variableHeader += msgid.hlBytes
    }
}

/// MQTT PUBREC Frame
struct CocoaMQTTFramePubRec: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    init(msgid: UInt16) {
        fixedHeader = CocoaMQTTFrameType.pubrec.rawValue
        self.msgid = msgid
    }
    
    mutating func pack() {
        variableHeader = []
        
        variableHeader += msgid.hlBytes
    }
}

/// MQTT PUBREL Frame
struct CocoaMQTTFramePubRel: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    init(msgid: UInt16) {
        fixedHeader = CocoaMQTTFrameType.pubrel.rawValue
        self.msgid = msgid
        self.qos = .qos1
    }
    
    mutating func pack() {
        variableHeader = []
        
        variableHeader += msgid.hlBytes
    }
}

/// MQTT PUBCOM Frame
struct CocoaMQTTFramePubCom: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    init(msgid: UInt16) {
        fixedHeader = CocoaMQTTFrameType.pubcomp.rawValue
        self.msgid = msgid
    }
    
    mutating func pack() {
        variableHeader = []
        
        variableHeader += msgid.hlBytes
    }
}

/// MQTT SUBSCRIBE Frame
struct CocoaMQTTFrameSubscribe: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    var topics: [(String, CocoaMQTTQoS)]

    init(msgid: UInt16, topic: String, reqos: CocoaMQTTQoS) {
        self.init(msgid: msgid, topics: [(topic, reqos)])
    }
    
    init(msgid: UInt16, topics: [(String, CocoaMQTTQoS)]) {
        fixedHeader = CocoaMQTTFrameType.subscribe.rawValue        
        self.msgid = msgid
        self.topics = topics        
        qos = CocoaMQTTQoS.qos1
    }

    mutating func pack() {
        variableHeader = []
        
        variableHeader += msgid.hlBytes
        for (topic, qos) in topics {
            payload += topic.bytesWithLength
            payload.append(qos.rawValue)
        }
    }
}


/// SUBSCRIBE ACK Frame
struct CocoaMQTTFrameSubAck: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    var grantedQos: [CocoaMQTTQoS]
    
    func pack() {
        // Nothing to do
    }
}

extension CocoaMQTTFrameSubAck: InitialWithBytes {
    
    init?(fixedHeader: UInt8, bytes: [UInt8]) {
        self.fixedHeader = fixedHeader
        
        // the bytes length must bigger than 3
        guard bytes.count >= 3 else {
            return nil
        }
        
        self.msgid = UInt16(bytes[0]) << 8 + UInt16(bytes[1])
        self.grantedQos = []
        for i in 2 ..< bytes.count {
            guard let qos = CocoaMQTTQoS(rawValue: bytes[i]) else {
                return nil
            }
            self.grantedQos.append(qos)
        }
    }
}

/// MQTT UNSUBSCRIBE Frame
struct CocoaMQTTFrameUnsubscribe: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    var topics: [String]

    init(msgid: UInt16, topics: [String]) {
        self.fixedHeader = CocoaMQTTFrameType.unsubscribe.rawValue
        self.msgid = msgid
        self.topics = topics
        qos = CocoaMQTTQoS.qos1
    }

    mutating func pack() {
        variableHeader = []
        
        variableHeader += msgid.hlBytes
        for t in topics {
            payload += t.bytesWithLength
        }
    }
}

// TODO: UNSUBACK

/// DISCONNECT Frame
struct CocoaMQTTFrameDisconnect: CocoaMQTTFrame {
    
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    init() {
        fixedHeader = CocoaMQTTFrameType.disconnect.rawValue
    }
    
    func pack() {
        // nothing to do
    }
}

/// PING Frame
struct CocoaMQTTFramePing: CocoaMQTTFrame {
    var fixedHeader: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    init() {
        fixedHeader = CocoaMQTTFrameType.pingreq.rawValue
    }
    
    func pack() {
        // nothing to do
    }
}

// TODO: Pong
