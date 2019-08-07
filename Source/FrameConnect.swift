//
//  ConnectFrame.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation

/// MQTT CONNECT Frame
struct FrameConnect: Frame {
    
    // --- Inherit
    
    var fixedHeader: UInt8 = FrameType.connect.rawValue
    
    var variableHeader: [UInt8] = []
    
    var payload: [UInt8] = []
    
    // --- Inherit end
    
    private let PROTOCOL_LEVEL = UInt8(4)
    private let PROTOCOL_VERSION: String  = "MQTT/3.1.1"
    private let PROTOCOL_MAGIC: String = "MQTT"
    
    var clientID: String
    
    var keepalive: UInt16 = 60
    
    var willMsg: CocoaMQTTMessage?
    
    var username: String?
    
    var password: String?
    
    /// Clean Session
    var cleansess: Bool = true
    
    init(clientID: String) {
        self.clientID = clientID
    }
    
    func bytes() -> [UInt8] {
        
        var variableHeader = [UInt8]()
        var payload = [UInt8]()
        
        var connFlag = ConnFlags()
        
        // variable header
        variableHeader += PROTOCOL_MAGIC.bytesWithLength
        variableHeader.append(PROTOCOL_LEVEL)
        
        // payload
        payload += clientID.bytesWithLength
        if let will = willMsg {
            connFlag.flagWill = true
            connFlag.flagWillQoS = will.qos.rawValue
            connFlag.flagWillRetain = will.retained
            payload += will.topic.bytesWithLength
            payload += will.payload
        }
        if let username = username {
            connFlag.flagUsername = true
            payload += username.bytesWithLength
        }
        if let password = password {
            connFlag.flagPassword = true
            payload += password.bytesWithLength
        }
        
        // flags
        connFlag.flagCleanSession = cleansess
        variableHeader.append(connFlag.rawValue)
        variableHeader += keepalive.hlBytes
        
        let length = UInt32(variableHeader.count + payload.count)
        return [fixedHeader] + remainingLen(len: length) + variableHeader + payload
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
