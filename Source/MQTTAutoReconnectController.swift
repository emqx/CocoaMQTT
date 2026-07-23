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

protocol MQTTAutoReconnectControllerDelegate: AnyObject {
    func autoReconnectControllerRequestsReconnect(_ controller: MQTTAutoReconnectController)
}

extension CocoaMQTTTimer: MQTTReconnectScheduledTask {}

private struct CocoaMQTTReconnectScheduler: MQTTReconnectScheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTReconnectScheduledTask {
        CocoaMQTTTimer.after(interval, name: "autoReconnTimer", action)
    }
}

struct MQTTAutoReconnectDisconnectContext {
    fileprivate let epoch: UInt64
    fileprivate let token: UInt64
}

/// Owns protocol-neutral reconnect state for both MQTT 3.1.1 and MQTT 5 clients.
final class MQTTAutoReconnectController {
    private static let minimumFailedStartRetryInterval: UInt16 = 1

    private enum PendingAttempt: Equatable {
        case none
        case unprepared
        case prepared

        func merging(_ other: PendingAttempt) -> PendingAttempt {
            switch (self, other) {
            case (.prepared, _), (_, .prepared):
                return .prepared
            case (.unprepared, _), (_, .unprepared):
                return .unprepared
            case (.none, .none):
                return .none
            }
        }
    }

    private struct ScheduledAttempt {
        let generation: UInt64
        let task: MQTTReconnectScheduledTask
    }

    private enum AttemptState {
        case idle
        case scheduled(ScheduledAttempt)
        case connecting
        case paused(PendingAttempt)
    }

    private enum DisconnectIntent {
        case none
        case expected(requestPending: Bool)
        case unexpected
    }

    private enum ReconnectDelay: Equatable {
        case normal
        case immediate
    }

    private struct PendingReconnect {
        var attemptCountBeforeDisconnect: UInt
        var pendingAttempt: PendingAttempt
        var delay: ReconnectDelay
    }

    private let lock = NSLock()
    private let eventLoopQueue: DispatchQueue
    private let scheduler: MQTTReconnectScheduling

    weak var delegate: MQTTAutoReconnectControllerDelegate?

    private var enabled = false
    private var initialInterval: UInt16 = 1
    private var maximumInterval: UInt16 = 128
    private var currentInterval: UInt16 = 0
    private var attemptCount: UInt = 0
    private var generation: UInt64 = 0
    private var attemptState = AttemptState.idle
    private var disconnectIntent = DisconnectIntent.none
    private var pendingReconnect: PendingReconnect?
    private var disconnectEpoch: UInt64 = 0
    private var nextDisconnectToken: UInt64 = 0
    private var inFlightDisconnectCallbacks = Set<UInt64>()

    init(
        eventLoopQueue: DispatchQueue,
        scheduler: MQTTReconnectScheduling = CocoaMQTTReconnectScheduler()
    ) {
        self.eventLoopQueue = eventLoopQueue
        self.scheduler = scheduler
    }

    deinit {
        if case let .scheduled(attempt) = attemptState {
            attempt.task.cancel()
        }
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
                resetReconnectCycleLocked()
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
        if case .paused = attemptState {
            return true
        }
        return false
    }

    /// Prevents duplicate expected disconnect requests until the socket either
    /// connects again or reports its disconnect.
    func beginExpectedDisconnect() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .expected(requestPending: true) = disconnectIntent {
            return false
        }
        disconnectIntent = .expected(requestPending: true)
        resetReconnectCycleLocked()
        return true
    }

    /// Records the reconnect cycle before requesting an unexpected socket close.
    func beginUnexpectedDisconnect() {
        lock.lock()
        disconnectIntent = .unexpected
        registerPendingReconnectLocked(attemptCountBeforeDisconnect: attemptCount)
        lock.unlock()
    }

    func socketConnected() {
        lock.lock()
        if case .expected = disconnectIntent {
            disconnectIntent = .expected(requestPending: false)
        }
        lock.unlock()
    }

    func connectionSucceeded() {
        lock.lock()
        disconnectIntent = .none
        resetReconnectCycleLocked()
        lock.unlock()
    }

    func pause() {
        lock.lock()
        let pendingAttempt: PendingAttempt
        switch attemptState {
        case let .scheduled(attempt):
            attempt.task.cancel()
            pendingAttempt = .prepared
        case let .paused(existing):
            pendingAttempt = existing
        case .idle, .connecting:
            pendingAttempt = .none
        }
        attemptState = .paused(pendingAttempt)
        generation &+= 1
        lock.unlock()
    }

    func resume(connectionIsDisconnected: Bool) -> CocoaMQTTAutoReconnectSchedule? {
        lock.lock()
        defer { lock.unlock() }
        guard case let .paused(pausedAttempt) = attemptState else { return nil }

        attemptState = .idle
        guard enabled else {
            pendingReconnect = nil
            return nil
        }

        // An unexpected disconnect owns this pending work until the socket
        // callback confirms that transport cleanup has completed.
        if var pendingReconnect = pendingReconnect {
            pendingReconnect.pendingAttempt = pendingReconnect.pendingAttempt.merging(pausedAttempt)
            pendingReconnect.delay = .immediate
            self.pendingReconnect = pendingReconnect
        }

        guard connectionIsDisconnected else { return nil }
        guard pendingReconnect == nil else { return nil }
        guard inFlightDisconnectCallbacks.isEmpty else {
            assert(pausedAttempt == .none, "An in-flight unexpected disconnect must retain its pending reconnect")
            return nil
        }

        guard pausedAttempt != .none else { return nil }
        if pausedAttempt == .unprepared {
            prepareAttemptLocked()
        }
        return scheduleLocked(after: 0)
    }

    func socketDidDisconnect() -> MQTTAutoReconnectDisconnectContext {
        lock.lock()
        defer { lock.unlock() }

        let suppressesReconnect: Bool
        switch disconnectIntent {
        case .expected:
            suppressesReconnect = true
        case .none, .unexpected:
            suppressesReconnect = false
        }

        let wasUnexpectedRequest: Bool
        if case .unexpected = disconnectIntent {
            wasUnexpectedRequest = true
        } else {
            wasUnexpectedRequest = false
        }
        disconnectIntent = .none

        if case .connecting = attemptState {
            attemptState = .idle
        }

        if suppressesReconnect || !enabled {
            resetReconnectCycleLocked()
        } else if !wasUnexpectedRequest {
            registerPendingReconnectLocked(attemptCountBeforeDisconnect: attemptCount)
        }

        nextDisconnectToken &+= 1
        let token = nextDisconnectToken
        inFlightDisconnectCallbacks.insert(token)
        return MQTTAutoReconnectDisconnectContext(
            epoch: disconnectEpoch,
            token: token
        )
    }

    /// Must be called after the public disconnect callbacks have completed.
    func completeDisconnectCallbacks(
        _ context: MQTTAutoReconnectDisconnectContext
    ) -> CocoaMQTTAutoReconnectSchedule? {
        lock.lock()
        defer { lock.unlock() }

        guard context.epoch == disconnectEpoch,
              inFlightDisconnectCallbacks.remove(context.token) != nil else { return nil }
        guard inFlightDisconnectCallbacks.isEmpty else { return nil }
        guard enabled else {
            resetReconnectCycleLocked()
            return nil
        }
        guard let pendingReconnect = pendingReconnect else { return nil }
        self.pendingReconnect = nil
        guard attemptCount == pendingReconnect.attemptCountBeforeDisconnect else { return nil }

        switch attemptState {
        case let .paused(pausedAttempt):
            attemptState = .paused(pausedAttempt.merging(pendingReconnect.pendingAttempt))
            return nil
        case .scheduled, .connecting:
            return nil
        case .idle:
            if pendingReconnect.pendingAttempt != .prepared {
                prepareAttemptLocked()
            }
            let delay: UInt16? = pendingReconnect.delay == .immediate ? 0 : nil
            return scheduleLocked(after: delay)
        }
    }

    /// Restores backoff after the transport rejects a reconnect synchronously.
    func reconnectAttemptFailedToStart() -> CocoaMQTTAutoReconnectSchedule? {
        lock.lock()
        defer { lock.unlock() }

        guard enabled else { return nil }
        switch attemptState {
        case .connecting:
            attemptState = .idle
            prepareAttemptLocked()
            // A zero backoff is valid for the first reconnect, but repeatedly
            // retrying a synchronously rejected connection without delay forms
            // a hot loop. Keep the configured backoff unchanged and apply the
            // floor only to this failed-start retry.
            return scheduleLocked(after: max(currentInterval, Self.minimumFailedStartRetryInterval))
        case .paused:
            attemptState = .paused(.unprepared)
            return nil
        case .idle, .scheduled:
            return nil
        }
    }

    func isCurrent(_ schedule: CocoaMQTTAutoReconnectSchedule) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled && generation == schedule.generation
    }

    private func registerPendingReconnectLocked(attemptCountBeforeDisconnect: UInt) {
        let statePendingAttempt: PendingAttempt
        if case .paused(.prepared) = attemptState {
            statePendingAttempt = .prepared
        } else {
            statePendingAttempt = .unprepared
        }

        let existingPendingAttempt = pendingReconnect?.pendingAttempt ?? .none
        let existingDelay = pendingReconnect?.delay ?? .normal
        pendingReconnect = PendingReconnect(
            attemptCountBeforeDisconnect: attemptCountBeforeDisconnect,
            pendingAttempt: existingPendingAttempt.merging(statePendingAttempt),
            delay: existingDelay
        )
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
        generation &+= 1
        let scheduledGeneration = generation
        let task = scheduler.schedule(after: Double(delay)) { [weak self] in
            guard let self = self else { return }
            self.eventLoopQueue.async { [weak self] in
                guard let self = self,
                      self.prepareScheduledAttempt(generation: scheduledGeneration) else { return }
                self.delegate?.autoReconnectControllerRequestsReconnect(self)
            }
        }
        attemptState = .scheduled(ScheduledAttempt(generation: scheduledGeneration, task: task))
        return CocoaMQTTAutoReconnectSchedule(
            attemptCount: attemptCount,
            interval: delay,
            generation: scheduledGeneration
        )
    }

    private func prepareScheduledAttempt(generation scheduledGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == scheduledGeneration,
              case let .scheduled(attempt) = attemptState,
              attempt.generation == scheduledGeneration,
              enabled else { return false }
        attemptState = .connecting
        let doubled = UInt32(currentInterval) * 2
        currentInterval = UInt16(min(doubled, UInt32(maximumInterval)))
        return true
    }

    private func resetReconnectCycleLocked() {
        if case let .scheduled(attempt) = attemptState {
            attempt.task.cancel()
        }
        attemptState = .idle
        currentInterval = 0
        attemptCount = 0
        pendingReconnect = nil
        if case .unexpected = disconnectIntent {
            disconnectIntent = .none
        }
        disconnectEpoch &+= 1
        inFlightDisconnectCallbacks.removeAll(keepingCapacity: true)
        generation &+= 1
    }
}
