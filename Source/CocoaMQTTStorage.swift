//
//  CocoaMQTTStorage.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/10/6.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation

protocol CocoaMQTTStorageProtocol {
    
    var clientId: String { get set }
    
    init?(by clientId: String)
    
    func write(_ frame: FramePublish) -> Bool
    
    func write(_ frame: FramePubRel) -> Bool
    
    func remove(_ frame: FramePublish)
    
    func remove(_ frame: FramePubRel)
    
    func synchronize() -> Bool
    
    /// Read all stored messages by saving order
    func readAll() -> [Frame]
}

final class CocoaMQTTStorage: CocoaMQTTStorageProtocol {
    
    var clientId: String
    
    var userDefault: UserDefaults

    private let keyPrefix = "CocoaMQTTStorage"

    init?(by clientId: String) {
        guard let userDefault = UserDefaults(suiteName: CocoaMQTTStorage.name(clientId)) else {
            return nil
        }
        
        self.clientId = clientId
        self.userDefault = userDefault
    }
    
    deinit {
        userDefault.synchronize()
    }
    
    func write(_ frame: FramePublish) -> Bool {
        guard frame.qos > .qos0 else {
            return false
        }
        userDefault.set(frame.bytes(), forKey: key(frame.msgid))
        return true
    }
    
    func write(_ frame: FramePubRel) -> Bool {
        userDefault.set(frame.bytes(), forKey: key(frame.msgid))
        return true
    }
    
    func remove(_ frame: FramePublish) {
        userDefault.removeObject(forKey: key(frame.msgid))
    }
    
    func remove(_ frame: FramePubRel) {
        userDefault.removeObject(forKey: key(frame.msgid))
    }
    
    func remove(_ frame: Frame) {
        if let pub = frame as? FramePublish {
            userDefault.removeObject(forKey: key(pub.msgid))
        } else if let rel = frame as? FramePubRel {
            userDefault.removeObject(forKey: key(rel.msgid))
        }
    }
    
    func synchronize() -> Bool {
        return userDefault.synchronize()
    }
    
    func readAll() -> [Frame] {
        return __read(needDelete: false)
    }
    
    func takeAll() -> [Frame] {
        return __read(needDelete: true)
    }
    
    private func key(_ msgid: UInt16) -> String {
        return "\(keyPrefix).\(msgid)"
    }
    
    private class func name(_ clientId: String) -> String {
        return "cocomqtt-\(clientId)"
    }
    
    private func parse(_ bytes: [UInt8]) -> (UInt8, [UInt8])? {
        guard bytes.count >= 2 else { return nil }
        /// bytes 1..<5 may be 'Remaining Length'
        for i in 1 ..< 5 {
            if (bytes[i] & 0x80) == 0 {
                return (bytes[0], Array(bytes.suffix(from: i+1)))
            }
        }
        
        return nil
    }
    
    private func __read(needDelete: Bool)  -> [Frame] {
        return userDefault.dictionaryRepresentation().lazy
            .filter { $0.key.contains(self.keyPrefix) }
            .compactMap { k, v -> (key: String, value: (UInt8, [UInt8]))? in
                guard let array = v as? [UInt8],
                      let parse = self.parse(array) else { return nil }
                return (key: k, value: parse)
            }
            .elements
            .sorted { (k1, k2) in return k1.key < k2.key }
            .compactMap { key, parsed -> Frame? in
                if needDelete {
                    userDefault.removeObject(forKey: key)
                }

                if let f = FramePublish(fixedHeader: parsed.0, bytes: parsed.1) {
                    return f
                } else if let f = FramePubRel(fixedHeader: parsed.0, bytes: parsed.1) {
                    return f
                } else {
                    return nil
                }
            }
    }
    
}
