//
//  MQTT5SessionState.swift
//  CocoaMQTT
//

import Foundation

final class MQTT5SessionExpiryController {
    private let clientID: String
    private let discardSession: () -> Void
    private let lock = NSLock()
    private var expiryWorkItem: DispatchWorkItem?
    private var generation: UInt64 = 0
    private var expiryInterval: UInt32 = 0
    private var isEstablished = false

    init(clientID: String, discardSession: @escaping () -> Void) {
        self.clientID = clientID
        self.discardSession = discardSession
    }

    deinit {
        expiryWorkItem?.cancel()
    }

    func prepareStoredSessionForConnect() {
        guard let storage = storage,
              let deadline = storage.sessionExpiryDeadline() else { return }
        let remaining = deadline.timeIntervalSinceNow

        lock.lock()
        generation &+= 1
        let currentGeneration = generation
        expiryWorkItem?.cancel()
        expiryWorkItem = nil
        guard remaining > 0 else {
            expire(generation: currentGeneration, lockIsHeld: true)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.expire(generation: currentGeneration)
        }
        expiryWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + remaining, execute: workItem)
        lock.unlock()
    }

    func begin(expiryInterval: UInt32) {
        lock.lock()
        generation &+= 1
        expiryWorkItem?.cancel()
        expiryWorkItem = nil
        self.expiryInterval = expiryInterval
        isEstablished = true
        lock.unlock()
        storage?.setSessionExpiryDeadline(nil)
    }

    func handleDisconnect() {
        lock.lock()
        guard isEstablished else {
            lock.unlock()
            return
        }
        isEstablished = false
        generation &+= 1
        let currentGeneration = generation
        let expiryInterval = self.expiryInterval
        expiryWorkItem?.cancel()
        expiryWorkItem = nil
        lock.unlock()

        guard expiryInterval != 0 else {
            expire(generation: currentGeneration)
            return
        }
        guard expiryInterval != UInt32.max else {
            storage?.setSessionExpiryDeadline(nil)
            return
        }

        storage?.setSessionExpiryDeadline(
            Date().addingTimeInterval(TimeInterval(expiryInterval))
        )
        lock.lock()
        guard currentGeneration == generation, !isEstablished else {
            lock.unlock()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.expire(generation: currentGeneration)
        }
        expiryWorkItem = workItem
        DispatchQueue.global().asyncAfter(
            deadline: .now() + TimeInterval(expiryInterval),
            execute: workItem
        )
        lock.unlock()
    }

    private var storage: CocoaMQTTStorage? {
        return CocoaMQTTStorage(by: clientID, protocolVersion: .v5)
    }

    private func expire(generation expectedGeneration: UInt64,
                        lockIsHeld: Bool = false) {
        if !lockIsHeld { lock.lock() }
        guard expectedGeneration == generation, !isEstablished else {
            lock.unlock()
            return
        }
        expiryWorkItem = nil
        storage?.removeAll()
        discardSession()
        lock.unlock()
    }
}

final class MQTT5TopicAliasStore {
    private let lock = NSLock()
    private var inbound = [UInt16: String]()
    private var outbound = [UInt16: String]()
    private var inboundMaximum: UInt16 = 0
    private var outboundMaximum: UInt16 = 0

    func configure(inboundMaximum: UInt16, outboundMaximum: UInt16) {
        lock.lock()
        inbound.removeAll()
        outbound.removeAll()
        self.inboundMaximum = inboundMaximum
        self.outboundMaximum = outboundMaximum
        lock.unlock()
    }

    func clear() {
        configure(inboundMaximum: 0, outboundMaximum: 0)
    }

    func resolvedOutboundTopic(topic: String, alias: UInt16?) -> String? {
        guard let alias = alias else { return topic.isEmpty ? nil : topic }
        lock.lock()
        defer { lock.unlock() }
        guard alias != 0, alias <= outboundMaximum else { return nil }
        return topic.isEmpty ? outbound[alias] : topic
    }

    func recordOutbound(alias: UInt16?, topic: String) {
        guard let alias = alias, !topic.isEmpty else { return }
        lock.lock()
        outbound[alias] = topic
        lock.unlock()
    }

    func resolveInbound(topic: String, alias: UInt16?) -> String? {
        guard let alias = alias else { return topic }
        lock.lock()
        defer { lock.unlock() }
        guard alias != 0, alias <= inboundMaximum else { return nil }
        if !topic.isEmpty {
            inbound[alias] = topic
            return topic
        }
        return inbound[alias]
    }
}
