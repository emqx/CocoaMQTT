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
    
    var fixedHeader: UInt8 = FrameType.connect.rawValue
    
    private let PROTOCOL_LEVEL = UInt8(4)
    private let PROTOCOL_VERSION: String  = "MQTT/3.1.1"
    private let PROTOCOL_MAGIC: String = "MQTT"
    
    // --- Attributes
    
    var clientID: String
    
    var keepalive: UInt16 = 60
    
    var willMsg: CocoaMQTTMessage?
    
    var username: String?
    
    var password: String?
    
    var cleansess: Bool = true
    
    // --- Attributes End
    
    init(clientID: String) {
        self.clientID = clientID
    }
}

extension FrameConnect {
    
    func variableHeader() -> [UInt8] {
        var header = [UInt8]()
        var flags = ConnFlags()
        
        // variable header
        header += PROTOCOL_MAGIC.bytesWithLength
        header.append(PROTOCOL_LEVEL)
        
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
        header += keepalive.hlBytes
        
        return header
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
}

extension FrameConnect: CustomStringConvertible {
    
    var description: String {
        return "CONNECT(id: \(clientID), username: \(username ?? "nil"), " +
               "password: \(password ?? "nil"), keepalive : \(keepalive), " +
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
