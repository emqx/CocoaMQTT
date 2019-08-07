//
//  CocoaMQTTFrame.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation

/// MQTT Frame Type
enum FrameType: UInt8 {
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
protocol Frame {
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
    //mutating func pack()
    
    /// Compact all attributes to a binary array
    func bytes() -> [UInt8]
}

extension Frame {

    /// The type of the Frame
    var type: FrameType {
        return  FrameType(rawValue: fixedHeader & 0xF0)!
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
}

extension Frame {
    
    func remainingLen(len: UInt32) -> [UInt8] {
        var bytes: [UInt8] = []
        var digit: UInt8 = 0
        
        var len = len
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
