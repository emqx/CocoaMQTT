//
//  MQTTPacketIdentifierAllocator.swift
//  CocoaMQTT
//

import Foundation

/// Reserves Packet Identifiers across PUBLISH, SUBSCRIBE, and UNSUBSCRIBE flows.
final class MQTTPacketIdentifierAllocator {
    private let lock = NSLock()
    private var nextCandidate: UInt16 = 1
    private var inUse = Set<UInt16>()

    func reserve() -> UInt16? {
        lock.lock()
        defer { lock.unlock() }

        guard inUse.count < Int(UInt16.max) else { return nil }
        for _ in 0..<Int(UInt16.max) {
            let candidate = nextCandidate
            nextCandidate = candidate == UInt16.max ? 1 : candidate + 1
            if inUse.insert(candidate).inserted {
                return candidate
            }
        }
        return nil
    }

    func reserve(_ identifier: UInt16) -> Bool {
        guard identifier != 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        return inUse.insert(identifier).inserted
    }

    func markInUse(_ identifier: UInt16) {
        guard identifier != 0 else { return }
        lock.lock()
        inUse.insert(identifier)
        lock.unlock()
    }

    func release(_ identifier: UInt16) {
        guard identifier != 0 else { return }
        lock.lock()
        inUse.remove(identifier)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        inUse.removeAll(keepingCapacity: true)
        nextCandidate = 1
        lock.unlock()
    }

    var reservedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inUse.count
    }
}
