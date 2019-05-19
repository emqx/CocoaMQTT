//
//  CocoaMQTTFrame.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation


/**
 * Encode and Decode big-endian UInt16
 */
extension UInt16 {
    // Most Significant Byte (MSB)
    private var highByte: UInt8 {
        return UInt8( (self & 0xFF00) >> 8)
    }
    // Least Significant Byte (LSB)
    private var lowByte: UInt8 {
        return UInt8(self & 0x00FF)
    }

    var hlBytes: [UInt8] {
        return [highByte, lowByte]
    }
}

/**
 * String with two bytes length
 */
extension String {
    // ok?
    var bytesWithLength: [UInt8] {
        return UInt16(utf8.count).hlBytes + utf8
    }
}

/**
 * Bool to bit
 */
extension Bool {
    fileprivate var bit: UInt8 {
        return self ? 1 : 0
    }

    fileprivate init(bit: UInt8) {
        self = (bit == 0) ? false : true
    }
}

/**
 * read bit
 */
extension UInt8 {
    fileprivate func bitAt(_ offset: UInt8) -> UInt8 {
        return (self >> offset) & 0x01
    }
}

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

/**
 * MQTT Frame
 */
protocol CocoaMQTTFrame {
    /**
     * |--------------------------------------
     * | 7 6 5 4 |     3    |  2 1  | 0      |
     * |  Type   | DUP flag |  QoS  | RETAIN |
     * |--------------------------------------
     */
    var header: UInt8 {get set}
    
    var variableHeader: [UInt8] {get set}
    var payload: [UInt8] {get set}
    
    // Pack the attribute to header/variableHeader/payload
    mutating func pack()
}

extension CocoaMQTTFrame {

    
    var type: UInt8 {
        return  UInt8(header & 0xF0)
    }
    
    var dup: Bool {
        get {
            return ((header & 0x08) >> 3) == 0 ? false : true
        }
        set {
            header = (header & 0xF7) | (newValue.bit  << 3)
        }
    }
    
    var qos: UInt8 {
        get {
            return (header & 0x06) >> 1
        }
        set {
            header = (header & 0xF9) | (newValue << 1)
        }
    }
    
    var retained: Bool {
        get {
            return (header & 0x01) == 0 ? false : true
        }
        set {
            header = (header & 0xFE) | newValue.bit
        }
    }
    
    mutating func data() -> [UInt8] {
        self.pack()
        return [UInt8]([header]) + encodeLength() + variableHeader + payload
    }
    
    func encodeLength() -> [UInt8] {
        var bytes: [UInt8] = []
        var digit: UInt8 = 0
        var len: UInt32 = UInt32(variableHeader.count+payload.count)
        
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

/**
 * MQTT CONNECT Frame
 */
struct CocoaMQTTFrameConnect: CocoaMQTTFrame {
    
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    let PROTOCOL_LEVEL = UInt8(4)
    let PROTOCOL_VERSION: String  = "MQTT/3.1.1"
    let PROTOCOL_MAGIC: String = "MQTT"

    /**
     * |----------------------------------------------------------------------------------
     * |     7    |    6     |      5     |  4   3  |     2    |       1      |     0    |
     * | username | password | willretain | willqos | willflag | cleansession | reserved |
     * |----------------------------------------------------------------------------------
     */
    var flags: UInt8 = 0

    var flagUsername: Bool {
        get {
            return Bool(bit: (flags >> 7) & 0x01)
        }

        set {
            flags = (flags & 0x7F) | (newValue.bit << 7)
        }
    }

    var flagPassword: Bool {
        get {
            return Bool(bit:(flags >> 6) & 0x01)
        }

        set {
            flags = (flags & 0xBF) | (newValue.bit << 6)
        }
    }

    var flagWillRetain: Bool {
        get {
            return Bool(bit: (flags >> 5) & 0x01)
        }
        
        set {
            flags = (flags & 0xDF) | (newValue.bit << 5)
        }
    }

    var flagWillQOS: UInt8 {
        get {
            return (flags >> 3) & 0x03
        }
        
        set {
            flags = (flags & 0xE7) | (newValue << 3)
        }
    }

    var flagWill: Bool {
        get {
            return Bool(bit:(flags >> 2) & 0x01)
        }

        set {
            flags = (flags & 0xFB) | (newValue.bit << 2)
        }
    }

    var flagCleanSession: Bool {
        get {
            return Bool(bit: (flags >> 1) & 0x01)
        }

        set {
            flags = (flags & 0xFD) | (newValue.bit << 1)

        }
    }

    var client: CocoaMQTTClient

    // TODO: refactor?
    init(client: CocoaMQTT) {
        self.client = client
        self.header = CocoaMQTTFrameType.connect.rawValue
    }

    mutating func pack() {
        // variable header
        variableHeader += PROTOCOL_MAGIC.bytesWithLength
        variableHeader.append(PROTOCOL_LEVEL)

        // payload
        payload += client.clientID.bytesWithLength
        if let will = client.willMessage {
            flagWill = true
            flagWillQOS = will.qos.rawValue
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
        variableHeader.append(flags)
        variableHeader += client.keepAlive.hlBytes
    }
}

/**
 * MQTT PUBLISH Frame
 */
struct CocoaMQTTFramePublish: CocoaMQTTFrame {
    
    
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16?
    var topic: String?
    var data: [UInt8]?

    init(msgid: UInt16, topic: String, payload: [UInt8]) {
        header = CocoaMQTTFrameType.publish.rawValue
        self.msgid = msgid
        self.topic = topic
        self.payload = payload
    }

    init(header: UInt8, data: [UInt8]) {
        self.header = header
        self.data = data
    }

    mutating func unpack() {
        // topic
        if data!.count < 2 {
            printWarning("Invalid format of received message.")
            return
        }
        var msb = data![0]
        var lsb = data![1]
        let len = UInt16(msb) << 8 + UInt16(lsb)
        var pos = 2 + Int(len)
        
        if data!.count < pos {
            printWarning("Invalid format of received message.")
            return
        }
        
        topic = NSString(bytes: [UInt8](data![2...(pos-1)]), length: Int(len), encoding: String.Encoding.utf8.rawValue) as String?

        // msgid
        if qos == 0 {
            msgid = 0
        } else {
            if data!.count < pos + 2 {
                printWarning("Invalid format of received message.")
                return
            }
            msb = data![pos]
            lsb = data![pos+1]
            pos += 2
            msgid = UInt16(msb) << 8 + UInt16(lsb)
        }
        
        // payload
        let end = data!.count - 1
        
        if (end - pos >= 0) {
            payload = [UInt8](data![pos...end])
        // receives an empty message
        } else {
            payload = []
        }
    }

    mutating func pack() {
        variableHeader += topic!.bytesWithLength
        if qos > 0 {
            variableHeader += msgid!.hlBytes
        }
    }
}

extension CocoaMQTTFramePublish: CustomStringConvertible {
    var description: String {
        return "PUBLISH(msgid: \(msgid ?? 0), topic: \(topic ?? ""), payload: \(payload))"
    }
}


/**
 * MQTT PUBACK/PUBREC/PUBREL/PUBCOM Frame
 */
struct CocoaMQTTFramePubAck: CocoaMQTTFrame {
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    
    init(type: CocoaMQTTFrameType, msgid: UInt16) {
        header = type.rawValue
        self.msgid = msgid
        if type == CocoaMQTTFrameType.pubrel {
            qos = CocoaMQTTQOS.qos1.rawValue
        }
    }

    mutating func pack() {
        variableHeader += msgid.hlBytes
    }
}

/**
 * MQTT SUBSCRIBE Frame
 */
struct CocoaMQTTFrameSubscribe: CocoaMQTTFrame {
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    var topics: [(String, CocoaMQTTQOS)]

    init(msgid: UInt16, topic: String, reqos: CocoaMQTTQOS) {
        self.init(msgid: msgid, topics: [(topic, reqos)])
    }
    
    init(msgid: UInt16, topics: [(String, CocoaMQTTQOS)]) {
        header = CocoaMQTTFrameType.subscribe.rawValue        
        self.msgid = msgid
        self.topics = topics        
        qos = CocoaMQTTQOS.qos1.rawValue
    }

    mutating func pack() {
        variableHeader += msgid.hlBytes
        for (topic, qos) in topics {
            payload += topic.bytesWithLength
            payload.append(qos.rawValue)
        }
    }
}

/**
 * MQTT UNSUBSCRIBE Frame
 */
struct CocoaMQTTFrameUnsubscribe: CocoaMQTTFrame {
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    var msgid: UInt16
    var topic: String

    init(msgid: UInt16, topic: String) {
        // TODO: Support topic tables!!
        self.header = CocoaMQTTFrameType.unsubscribe.rawValue
        self.msgid = msgid
        self.topic = topic
        qos = CocoaMQTTQOS.qos1.rawValue
    }

    mutating func pack() {
        variableHeader += msgid.hlBytes
        payload += topic.bytesWithLength
    }
}

/// DISCONNECT Frame
struct CocoaMQTTFrameDisconnect: CocoaMQTTFrame {
    
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    init() {
        header = CocoaMQTTFrameType.disconnect.rawValue
    }
    
    func pack() {
        // nothing to do
    }
}

/// PING Frame
struct CocoaMQTTFramePing: CocoaMQTTFrame {
    var header: UInt8
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    init() {
        header = CocoaMQTTFrameType.pingreq.rawValue
    }
    
    func pack() {
        // nothing to do
    }
}
