//
//  MQTTKeepAliveController.swift
//  CocoaMQTT
//

import Foundation

protocol MQTTKeepAliveScheduledTask: AnyObject {
    func cancel()
}

protocol MQTTKeepAliveScheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTKeepAliveScheduledTask
}

protocol MQTTKeepAliveControllerDelegate: AnyObject {
    func keepAliveControllerRequestsPing(_ controller: MQTTKeepAliveController)
    func keepAliveControllerDidTimeOut(_ controller: MQTTKeepAliveController)
}

extension CocoaMQTTTimer: MQTTKeepAliveScheduledTask {}

private struct CocoaMQTTKeepAliveScheduler: MQTTKeepAliveScheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTKeepAliveScheduledTask {
        CocoaMQTTTimer.after(interval, name: "keepAliveTimer", action)
    }
}

/// Owns protocol-neutral PINGREQ/PINGRESP liveness state.
final class MQTTKeepAliveController: @unchecked Sendable {
    private enum Phase {
        case stopped
        case idle
        case awaitingResponse
    }

    private let eventLoopQueue: DispatchQueue
    private let scheduler: MQTTKeepAliveScheduling
    private let lock = NSLock()

    weak var delegate: MQTTKeepAliveControllerDelegate?

    private var phase = Phase.stopped
    private var scheduledTask: MQTTKeepAliveScheduledTask?
    private var generation: UInt64 = 0
    private var configuredInterval: TimeInterval?

    init(
        eventLoopQueue: DispatchQueue,
        scheduler: MQTTKeepAliveScheduling = CocoaMQTTKeepAliveScheduler()
    ) {
        self.eventLoopQueue = eventLoopQueue
        self.scheduler = scheduler
    }

    deinit {
        stop()
    }

    var interval: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return configuredInterval
    }

    func start(interval: UInt16) {
        lock.lock()
        stopLocked()
        guard interval > 0 else {
            lock.unlock()
            return
        }
        configuredInterval = TimeInterval(interval)
        phase = .idle
        scheduleNextEventLocked()
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    private func stopLocked() {
        generation &+= 1
        scheduledTask?.cancel()
        scheduledTask = nil
        configuredInterval = nil
        phase = .stopped
    }

    func pingSent() {
        lock.lock()
        guard phase == .idle else {
            lock.unlock()
            return
        }
        phase = .awaitingResponse
        scheduleNextEventLocked()
        lock.unlock()
    }

    func pingResponseReceived() {
        lock.lock()
        guard phase == .awaitingResponse else {
            lock.unlock()
            return
        }
        phase = .idle
        scheduleNextEventLocked()
        lock.unlock()
    }

    private func scheduleNextEventLocked() {
        guard let interval = configuredInterval else { return }
        generation &+= 1
        let scheduledGeneration = generation
        scheduledTask?.cancel()
        scheduledTask = scheduler.schedule(after: interval) { [weak self] in
            guard let self = self else { return }
            self.eventLoopQueue.async {
                self.handleScheduledEvent(generation: scheduledGeneration)
            }
        }
    }

    private func handleScheduledEvent(generation scheduledGeneration: UInt64) {
        lock.lock()
        guard scheduledGeneration == generation else {
            lock.unlock()
            return
        }
        scheduledTask = nil

        switch phase {
        case .stopped:
            lock.unlock()
            return
        case .idle:
            phase = .awaitingResponse
            scheduleNextEventLocked()
            let delegate = delegate
            lock.unlock()
            delegate?.keepAliveControllerRequestsPing(self)
        case .awaitingResponse:
            phase = .stopped
            configuredInterval = nil
            let delegate = delegate
            lock.unlock()
            delegate?.keepAliveControllerDidTimeOut(self)
        }
    }
}
