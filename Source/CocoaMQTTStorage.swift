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

    private static let legacyMigrationLock = NSLock()

    private struct StoredFrameValue {
        let key: String
        let msgid: UInt16
        let value: Any
        let order: UInt64
    }

    var clientId: String = ""

    var userDefault: UserDefaults = UserDefaults()

    var versionDefault: UserDefaults = UserDefaults()

    private var protocolVersion: CocoaMQTTProtocolVersion = .v311

    private var usesVersionedKeys = false

    private let legacyMigrationProtocolKey = "cocoamqtt.legacy-protocol-version"

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
        var persistedFrame = frame
        if let persistenceTopic = frame.persistenceTopic {
            persistedFrame.topic = persistenceTopic
        }
        ensureOrder(for: frame.msgid)
        userDefault.set(persistedFrame.bytes(version: protocolVersion.rawValue), forKey: key(frame.msgid))
        return true
    }

    func write(_ frame: FramePubRel) -> Bool {
        ensureOrder(for: frame.msgid)
        userDefault.set(frame.bytes(version: protocolVersion.rawValue), forKey: key(frame.msgid))
        return true
    }

    func remove(_ frame: FramePublish) {
        userDefault.removeObject(forKey: key(frame.msgid))
        userDefault.removeObject(forKey: orderKey(frame.msgid))
    }

    func remove(_ frame: FramePubRel) {
        userDefault.removeObject(forKey: key(frame.msgid))
        userDefault.removeObject(forKey: orderKey(frame.msgid))
    }

    func remove(_ frame: Frame) {
        if let pub = frame as? FramePublish {
            userDefault.removeObject(forKey: key(pub.msgid))
            userDefault.removeObject(forKey: orderKey(pub.msgid))
        } else if let rel = frame as? FramePubRel {
            userDefault.removeObject(forKey: key(rel.msgid))
            userDefault.removeObject(forKey: orderKey(rel.msgid))
        }
    }

    func removeAll() {
        for storedKey in userDefault.dictionaryRepresentation().keys where messageIdentifier(for: storedKey) != nil {
            userDefault.removeObject(forKey: storedKey)
        }
        for storedKey in userDefault.dictionaryRepresentation().keys where storedKey.hasPrefix(orderKeyPrefix) {
            userDefault.removeObject(forKey: storedKey)
        }
        userDefault.removeObject(forKey: orderCounterKey)
        userDefault.removeObject(forKey: receivedQoS2Key)
        userDefault.removeObject(forKey: sessionExpiryDeadlineKey)
    }

    func receivedQoS2Identifiers() -> Set<UInt16> {
        let values = userDefault.array(forKey: receivedQoS2Key) as? [NSNumber] ?? []
        return Set(values.compactMap { UInt16(exactly: $0.intValue) }.filter { $0 != 0 })
    }

    @discardableResult
    func markReceivedQoS2(_ identifier: UInt16) -> Bool {
        guard identifier != 0 else { return false }
        var identifiers = receivedQoS2Identifiers()
        let inserted = identifiers.insert(identifier).inserted
        if inserted {
            persistReceivedQoS2Identifiers(identifiers)
        }
        return inserted
    }

    @discardableResult
    func completeReceivedQoS2(_ identifier: UInt16) -> Bool {
        var identifiers = receivedQoS2Identifiers()
        guard identifiers.remove(identifier) != nil else { return false }
        persistReceivedQoS2Identifiers(identifiers)
        return true
    }

    func setSessionExpiryDeadline(_ deadline: Date?) {
        if let deadline = deadline {
            userDefault.set(deadline.timeIntervalSince1970, forKey: sessionExpiryDeadlineKey)
        } else {
            userDefault.removeObject(forKey: sessionExpiryDeadlineKey)
        }
    }

    func sessionExpiryDeadline() -> Date? {
        guard userDefault.object(forKey: sessionExpiryDeadlineKey) != nil else { return nil }
        return Date(timeIntervalSince1970: userDefault.double(forKey: sessionExpiryDeadlineKey))
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

    private var sessionExpiryDeadlineKey: String {
        return "\(namespacePrefix)session-expiry-deadline"
    }

    private var orderKeyPrefix: String {
        return "\(namespacePrefix)message-order-"
    }

    private var orderCounterKey: String {
        return "\(namespacePrefix)message-order-counter"
    }

    private var receivedQoS2Key: String {
        return "\(namespacePrefix)received-qos2"
    }

    private func orderKey(_ msgid: UInt16) -> String {
        return "\(orderKeyPrefix)\(msgid)"
    }

    private func ensureOrder(for msgid: UInt16) {
        guard userDefault.object(forKey: orderKey(msgid)) == nil else { return }
        let current = (userDefault.object(forKey: orderCounterKey) as? NSNumber)?.uint64Value ?? 0
        let next = current == UInt64.max ? UInt64.max : current + 1
        userDefault.set(NSNumber(value: next), forKey: orderCounterKey)
        userDefault.set(NSNumber(value: next), forKey: orderKey(msgid))
    }

    private func persistReceivedQoS2Identifiers(_ identifiers: Set<UInt16>) {
        if identifiers.isEmpty {
            userDefault.removeObject(forKey: receivedQoS2Key)
        } else {
            userDefault.set(identifiers.sorted().map { NSNumber(value: $0) }, forKey: receivedQoS2Key)
        }
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
        CocoaMQTTStorage.legacyMigrationLock.lock()
        defer { CocoaMQTTStorage.legacyMigrationLock.unlock() }

        let legacyFrames = userDefault.dictionaryRepresentation().compactMap { storedKey, value -> StoredFrameValue? in
            guard let msgid = UInt16(storedKey) else {
                return nil
            }
            return StoredFrameValue(key: storedKey, msgid: msgid, value: value, order: UInt64(msgid))
        }

        guard !legacyFrames.isEmpty else { return }

        // Legacy storage did not record a protocol per Client Identifier. The
        // first client instance that can decode the suite claims its migration;
        // the process-global compatibility version is not reliable when MQTT
        // 3.1.1 and MQTT 5 clients coexist.
        if let claimedProtocol = userDefault.string(forKey: legacyMigrationProtocolKey) {
            guard claimedProtocol == protocolVersion.rawValue else { return }
        }

        let decodableFrames = legacyFrames.filter { legacyFrame in
            guard let bytes = legacyFrame.value as? [UInt8],
                  let parsed = parse(bytes) else { return false }
            return decodeFrame(header: parsed.0, bytes: parsed.1) != nil
        }

        guard !decodableFrames.isEmpty else { return }
        userDefault.set(protocolVersion.rawValue, forKey: legacyMigrationProtocolKey)

        for legacyFrame in decodableFrames {
            let versionedKey = key(legacyFrame.msgid)
            if userDefault.object(forKey: versionedKey) == nil {
                userDefault.set(legacyFrame.value, forKey: versionedKey)
            }
            userDefault.removeObject(forKey: legacyFrame.key)
        }
        for legacyFrame in decodableFrames.sorted(by: { $0.msgid < $1.msgid }) {
            ensureOrder(for: legacyFrame.msgid)
        }
        userDefault.synchronize()
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

    private func decodeFrame(header: UInt8, bytes: [UInt8]) -> Frame? {
        if let publish = FramePublish(
            packetFixedHeaderType: header,
            bytes: bytes,
            protocolVersion: protocolVersion
        ) {
            return publish
        }
        return FramePubRel(
            packetFixedHeaderType: header,
            bytes: bytes,
            protocolVersion: protocolVersion
        )
    }

    private func __read(needDelete: Bool) -> [Frame] {
        var frames = [Frame]()
        let storedObjects = userDefault.dictionaryRepresentation().compactMap { storedKey, value -> StoredFrameValue? in
            guard let msgid = messageIdentifier(for: storedKey) else {
                return nil
            }
            let order = (userDefault.object(forKey: orderKey(msgid)) as? NSNumber)?.uint64Value
                ?? UInt64(msgid)
            return StoredFrameValue(key: storedKey, msgid: msgid, value: value, order: order)
        }
        for storedFrame in storedObjects.sorted(by: { $0.msgid < $1.msgid })
        where userDefault.object(forKey: orderKey(storedFrame.msgid)) == nil {
            ensureOrder(for: storedFrame.msgid)
        }
        let orderedObjects = storedObjects.map { storedFrame -> StoredFrameValue in
            let order = (userDefault.object(forKey: orderKey(storedFrame.msgid)) as? NSNumber)?.uint64Value
                ?? storedFrame.order
            return StoredFrameValue(
                key: storedFrame.key,
                msgid: storedFrame.msgid,
                value: storedFrame.value,
                order: order
            )
        }
        let allObjs = orderedObjects.sorted {
            $0.order == $1.order ? $0.msgid < $1.msgid : $0.order < $1.order
        }
        for storedFrame in allObjs {
            let v = storedFrame.value
            guard let bytes = v as? [UInt8] else { continue }
            guard let parsed = parse(bytes) else { continue }

            if needDelete {
                userDefault.removeObject(forKey: storedFrame.key)
                userDefault.removeObject(forKey: orderKey(storedFrame.msgid))
            }

            if let frame = decodeFrame(header: parsed.0, bytes: parsed.1) {
                frames.append(frame)
            }
        }
        return frames
    }

}
