//
//  MQTTAutoReconnectController.swift
//  CocoaMQTT
//

import Foundation

protocol MQTTReconnectScheduledTask: AnyObject {
    func cancel()
}

protocol MQTTReconnectScheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTReconnectScheduledTask
}

extension CocoaMQTTTimer: MQTTReconnectScheduledTask {}

private struct CocoaMQTTReconnectScheduler: MQTTReconnectScheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTReconnectScheduledTask {
        CocoaMQTTTimer.after(interval, name: "autoReconnTimer", action)
    }
}

struct MQTTAutoReconnectDisconnectContext {
    let attemptCountBeforeCallbacks: UInt
    let suppressesReconnect: Bool
}

/// Owns protocol-neutral reconnect state for both MQTT 3.1.1 and MQTT 5 clients.
final class MQTTAutoReconnectController {
    private let lock = NSRecursiveLock()
    private let eventLoopQueue: DispatchQueue
    private let scheduler: MQTTReconnectScheduling
    private let reconnect: () -> Void

    private var enabled = false
    private var initialInterval: UInt16 = 1
    private var maximumInterval: UInt16 = 128
    private var currentInterval: UInt16 = 0
    private var attemptCount: UInt = 0
    private var paused = false
    private var scheduledTask: MQTTReconnectScheduledTask?
    private var isAttemptScheduled = false
    private var hasPausedAttempt = false
    private var hasPendingAttempt = false
    private var generation: UInt64 = 0
    private var pendingSocketDisconnectAttemptCount: UInt?
    private var shouldResumeAfterPendingDisconnect = false
    private var expectedDisconnectPending = false
    private var suppressReconnectForNextDisconnect = false

    init(
        eventLoopQueue: DispatchQueue,
        scheduler: MQTTReconnectScheduling = CocoaMQTTReconnectScheduler(),
        reconnect: @escaping () -> Void
    ) {
        self.eventLoopQueue = eventLoopQueue
        self.scheduler = scheduler
        self.reconnect = reconnect
    }

    deinit {
        scheduledTask?.cancel()
    }

    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            enabled = newValue
            if !newValue {
                resetLocked()
            }
            lock.unlock()
        }
    }

    var autoReconnectTimeInterval: UInt16 {
        get {
            lock.lock()
            defer { lock.unlock() }
            return initialInterval
        }
        set {
            lock.lock()
            initialInterval = newValue
            lock.unlock()
        }
    }

    var maxAutoReconnectTimeInterval: UInt16 {
        get {
            lock.lock()
            defer { lock.unlock() }
            return maximumInterval
        }
        set {
            lock.lock()
            maximumInterval = newValue
            lock.unlock()
        }
    }

    var reconnectTimeInterval: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return currentInterval
    }

    var reconnectAttemptCount: UInt {
        lock.lock()
        defer { lock.unlock() }
        return attemptCount
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    /// Prevents duplicate expected disconnect requests until the socket either
    /// connects again or reports its disconnect.
    func beginExpectedDisconnect() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !expectedDisconnectPending else { return false }
        expectedDisconnectPending = true
        suppressReconnectForNextDisconnect = true
        return true
    }

    /// Records the reconnect generation before requesting an unexpected socket close.
    func beginUnexpectedDisconnect() {
        lock.lock()
        pendingSocketDisconnectAttemptCount = attemptCount
        suppressReconnectForNextDisconnect = false
        lock.unlock()
    }

    func socketConnected() {
        lock.lock()
        expectedDisconnectPending = false
        lock.unlock()
    }

    func connectionSucceeded() {
        lock.lock()
        suppressReconnectForNextDisconnect = false
        resetLocked()
        lock.unlock()
    }

    func pause() {
        lock.lock()
        paused = true
        if isAttemptScheduled {
            hasPausedAttempt = true
            isAttemptScheduled = false
        }
        shouldResumeAfterPendingDisconnect = false
        cancelScheduledTaskLocked()
        generation &+= 1
        lock.unlock()
    }

    func resume(connectionIsDisconnected: Bool) -> CocoaMQTTAutoReconnectSchedule? {
        lock.lock()
        defer { lock.unlock() }
        guard paused else { return nil }

        paused = false
        guard enabled, connectionIsDisconnected else {
            hasPausedAttempt = false
            hasPendingAttempt = false
            shouldResumeAfterPendingDisconnect = false
            return nil
        }

        if pendingSocketDisconnectAttemptCount != nil {
            // The old socket delegate must be cleared before a new connection starts.
            shouldResumeAfterPendingDisconnect = true
            return nil
        }

        guard hasPausedAttempt || hasPendingAttempt else { return nil }
        if !hasPausedAttempt {
            prepareAttemptLocked()
        }
        hasPausedAttempt = false
        hasPendingAttempt = false
        return scheduleLocked(after: 0)
    }

    func socketDidDisconnect() -> MQTTAutoReconnectDisconnectContext {
        lock.lock()
        defer { lock.unlock() }

        expectedDisconnectPending = false
        let suppressesReconnect = suppressReconnectForNextDisconnect
        suppressReconnectForNextDisconnect = false
        if suppressesReconnect || !enabled {
            resetLocked()
        }

        let countBeforeCallbacks = pendingSocketDisconnectAttemptCount ?? attemptCount
        if !suppressesReconnect && enabled {
            pendingSocketDisconnectAttemptCount = countBeforeCallbacks
        }
        return MQTTAutoReconnectDisconnectContext(
            attemptCountBeforeCallbacks: countBeforeCallbacks,
            suppressesReconnect: suppressesReconnect
        )
    }

    /// Must be called after the public disconnect callbacks have completed.
    func completeDisconnectCallbacks(
        _ context: MQTTAutoReconnectDisconnectContext
    ) -> CocoaMQTTAutoReconnectSchedule? {
        lock.lock()
        defer { lock.unlock() }

        guard !context.suppressesReconnect else { return nil }
        guard enabled else {
            resetLocked()
            return nil
        }

        pendingSocketDisconnectAttemptCount = nil
        guard !paused,
              !isAttemptScheduled,
              attemptCount == context.attemptCountBeforeCallbacks else {
            if paused,
               !isAttemptScheduled,
               attemptCount == context.attemptCountBeforeCallbacks {
                hasPendingAttempt = true
            }
            shouldResumeAfterPendingDisconnect = false
            return nil
        }

        let resumeImmediately = shouldResumeAfterPendingDisconnect
        shouldResumeAfterPendingDisconnect = false
        if !hasPausedAttempt {
            prepareAttemptLocked()
        }
        hasPausedAttempt = false
        hasPendingAttempt = false
        return scheduleLocked(after: resumeImmediately ? 0 : nil)
    }

    func isCurrent(_ schedule: CocoaMQTTAutoReconnectSchedule) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled && generation == schedule.generation
    }

    private func prepareAttemptLocked() {
        if currentInterval == 0 {
            currentInterval = min(initialInterval, maximumInterval)
        }
        attemptCount += 1
    }

    private func scheduleLocked(after interval: UInt16?) -> CocoaMQTTAutoReconnectSchedule {
        let delay = interval ?? currentInterval
        printInfo("Try reconnect to server after \(delay)s")
        isAttemptScheduled = true
        generation &+= 1
        let scheduledGeneration = generation
        cancelScheduledTaskLocked()
        scheduledTask = scheduler.schedule(after: Double(delay)) { [weak self] in
            guard let self = self else { return }
            self.eventLoopQueue.async { [weak self] in
                guard let self = self,
                      self.prepareScheduledAttempt(generation: scheduledGeneration) else { return }
                self.reconnect()
            }
        }
        return CocoaMQTTAutoReconnectSchedule(
            attemptCount: attemptCount,
            interval: delay,
            generation: scheduledGeneration
        )
    }

    private func prepareScheduledAttempt(generation scheduledGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == scheduledGeneration else { return false }
        guard enabled, !paused else {
            isAttemptScheduled = false
            return false
        }
        isAttemptScheduled = false
        scheduledTask = nil
        let doubled = UInt32(currentInterval) * 2
        currentInterval = UInt16(min(doubled, UInt32(maximumInterval)))
        return true
    }

    private func resetLocked() {
        currentInterval = 0
        attemptCount = 0
        paused = false
        cancelScheduledTaskLocked()
        isAttemptScheduled = false
        hasPausedAttempt = false
        hasPendingAttempt = false
        pendingSocketDisconnectAttemptCount = nil
        shouldResumeAfterPendingDisconnect = false
        generation &+= 1
    }

    private func cancelScheduledTaskLocked() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }
}
