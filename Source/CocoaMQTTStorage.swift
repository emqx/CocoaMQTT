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

    func removeAll()

    func synchronize() -> Bool

    /// Read all stored messages by saving order
    func readAll() -> [Frame]
}

final class CocoaMQTTStorage: CocoaMQTTStorageProtocol {

    private struct StoredFrameValue {
        let key: String
        let msgid: UInt16
        let value: Any
    }

    var clientId: String = ""

    var userDefault: UserDefaults = UserDefaults()

    var versionDefault: UserDefaults = UserDefaults()

    private var protocolVersion: CocoaMQTTProtocolVersion = .v311

    private var usesVersionedKeys = false

    init?() {
        versionDefault = UserDefaults()
    }

    init?(by clientId: String) {
        self.protocolVersion = .v311
        guard let userDefault = UserDefaults(suiteName: CocoaMQTTStorage.name(clientId)) else {
            return nil
        }

        self.clientId = clientId
        self.userDefault = userDefault
    }

    init?(by clientId: String, protocolVersion: CocoaMQTTProtocolVersion) {
        self.protocolVersion = protocolVersion
        self.usesVersionedKeys = true
        guard let userDefault = UserDefaults(suiteName: CocoaMQTTStorage.name(clientId)) else {
            return nil
        }

        self.clientId = clientId
        self.userDefault = userDefault
        migrateLegacyFramesIfNeeded()
    }

    deinit {
        userDefault.synchronize()
        versionDefault.synchronize()
    }

    func setMQTTVersion(_ version: String) {
        versionDefault.set(version, forKey: "cocoamqtt.emqx.version")
    }

    func queryMQTTVersion() -> String {
        return versionDefault.string(forKey: "cocoamqtt.emqx.version") ?? "3.1.1"
    }

    func write(_ frame: FramePublish) -> Bool {
        guard frame.qos > .qos0 else {
            return false
        }
        userDefault.set(frame.bytes(version: protocolVersion.rawValue), forKey: key(frame.msgid))
        return true
    }

    func write(_ frame: FramePubRel) -> Bool {
        userDefault.set(frame.bytes(version: protocolVersion.rawValue), forKey: key(frame.msgid))
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

    func removeAll() {
        for storedKey in userDefault.dictionaryRepresentation().keys where messageIdentifier(for: storedKey) != nil {
            userDefault.removeObject(forKey: storedKey)
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
        guard usesVersionedKeys else {
            return "\(msgid)"
        }
        return "\(namespacePrefix)\(msgid)"
    }

    private var namespacePrefix: String {
        return "mqtt-\(protocolVersion.rawValue)-"
    }

    private func messageIdentifier(for storedKey: String) -> UInt16? {
        guard usesVersionedKeys else {
            return UInt16(storedKey)
        }
        guard storedKey.hasPrefix(namespacePrefix) else {
            return nil
        }
        return UInt16(storedKey.dropFirst(namespacePrefix.count))
    }

    private static func name(_ clientId: String) -> String {
        return "cocomqtt-\(clientId)"
    }

    private func migrateLegacyFramesIfNeeded() {
        guard queryMQTTVersion() == protocolVersion.rawValue else {
            return
        }

        let legacyFrames = userDefault.dictionaryRepresentation().compactMap { storedKey, value -> StoredFrameValue? in
            guard let msgid = UInt16(storedKey) else {
                return nil
            }
            return StoredFrameValue(key: storedKey, msgid: msgid, value: value)
        }

        for legacyFrame in legacyFrames {
            let versionedKey = key(legacyFrame.msgid)
            if userDefault.object(forKey: versionedKey) == nil {
                userDefault.set(legacyFrame.value, forKey: versionedKey)
            }
            userDefault.removeObject(forKey: legacyFrame.key)
        }
        if !legacyFrames.isEmpty {
            userDefault.synchronize()
        }
    }

    private func parse(_ bytes: [UInt8]) -> (UInt8, [UInt8])? {
        // FramePubRel is 4 bytes long
        guard bytes.count > 3 else {
            return nil
        }
        // bytes 1..<5 may be 'Remaining Length'
        for i in 1 ..< min(5, bytes.count) where (bytes[i] & 0x80) == 0 {
            return (bytes[0], Array(bytes.suffix(from: i + 1)))
        }

        return nil
    }

    private func __read(needDelete: Bool) -> [Frame] {
        var frames = [Frame]()
        let allObjs = userDefault.dictionaryRepresentation().compactMap { storedKey, value -> StoredFrameValue? in
            guard let msgid = messageIdentifier(for: storedKey) else {
                return nil
            }
            return StoredFrameValue(key: storedKey, msgid: msgid, value: value)
        }.sorted { $0.msgid < $1.msgid }
        for storedFrame in allObjs {
            let v = storedFrame.value
            guard let bytes = v as? [UInt8] else { continue }
            guard let parsed = parse(bytes) else { continue }

            if needDelete {
                userDefault.removeObject(forKey: storedFrame.key)
            }

            if let f = FramePublish(packetFixedHeaderType: parsed.0, bytes: parsed.1, protocolVersion: protocolVersion) {
                frames.append(f)
            } else if let f = FramePubRel(packetFixedHeaderType: parsed.0, bytes: parsed.1, protocolVersion: protocolVersion) {
                frames.append(f)
            }
        }
        return frames
    }

}
