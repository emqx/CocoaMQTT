import Foundation
import XCTest
@testable import CocoaMQTT

final class MQTTAutoReconnectControllerTests: XCTestCase {
    private final class Task: MQTTReconnectScheduledTask {
        private let lock = NSLock()
        private var action: (() -> Void)?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return action == nil
        }

        func fire() {
            lock.lock()
            let pendingAction = action
            action = nil
            lock.unlock()
            pendingAction?()
        }

        func cancel() {
            lock.lock()
            action = nil
            lock.unlock()
        }
    }

    private final class Scheduler: MQTTReconnectScheduling {
        private(set) var intervals = [TimeInterval]()
        private(set) var tasks = [Task]()

        func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTReconnectScheduledTask {
            let task = Task(action: action)
            intervals.append(interval)
            tasks.append(task)
            return task
        }
    }

    private final class Delegate: MQTTAutoReconnectControllerDelegate {
        private(set) var reconnectCount = 0

        func autoReconnectControllerRequestsReconnect(_ controller: MQTTAutoReconnectController) {
            reconnectCount += 1
        }
    }

    func testReconnectBackoffIsSharedAndClamped() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.backoff")
        let scheduler = Scheduler()
        let delegate = Delegate()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.delegate = delegate
        controller.isEnabled = true
        controller.autoReconnectTimeInterval = 1
        controller.maxAutoReconnectTimeInterval = 3

        let first = controller.socketDidDisconnect()
        let firstSchedule = controller.completeDisconnectCallbacks(first)
        XCTAssertEqual(firstSchedule?.attemptCount, 1)
        XCTAssertEqual(firstSchedule?.interval, 1)
        scheduler.tasks[0].fire()
        eventLoop.sync {}
        XCTAssertEqual(delegate.reconnectCount, 1)
        XCTAssertEqual(controller.reconnectTimeInterval, 2)

        let second = controller.socketDidDisconnect()
        let secondSchedule = controller.completeDisconnectCallbacks(second)
        XCTAssertEqual(secondSchedule?.attemptCount, 2)
        XCTAssertEqual(secondSchedule?.interval, 2)
        scheduler.tasks[1].fire()
        eventLoop.sync {}
        XCTAssertEqual(delegate.reconnectCount, 2)
        XCTAssertEqual(controller.reconnectTimeInterval, 3)

        controller.connectionSucceeded()
        XCTAssertEqual(controller.reconnectAttemptCount, 0)
        XCTAssertEqual(controller.reconnectTimeInterval, 0)
    }

    func testReconnectWaitsForDisconnectCallbacks() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.callbacks")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertTrue(scheduler.tasks.isEmpty)

        let schedule = controller.completeDisconnectCallbacks(context)
        XCTAssertEqual(schedule?.attemptCount, 1)
        XCTAssertEqual(scheduler.intervals, [1])
    }

    func testDisablingReconnectDuringDisconnectCallbackInvalidatesAttempt() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.disable")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        controller.isEnabled = false

        XCTAssertNil(controller.completeDisconnectCallbacks(context))
        XCTAssertTrue(scheduler.tasks.isEmpty)
        XCTAssertEqual(controller.reconnectAttemptCount, 0)
        XCTAssertEqual(controller.reconnectTimeInterval, 0)
    }

    func testPauseCancelsAttemptAndResumeRunsItImmediately() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.pause")
        let scheduler = Scheduler()
        let delegate = Delegate()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.delegate = delegate
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertEqual(controller.completeDisconnectCallbacks(context)?.interval, 1)
        let delayedTask = scheduler.tasks[0]

        controller.pause()
        XCTAssertTrue(delayedTask.isCancelled)
        XCTAssertTrue(controller.isPaused)

        let resumed = controller.resume(connectionIsDisconnected: true)
        XCTAssertEqual(resumed?.attemptCount, 1)
        XCTAssertEqual(resumed?.interval, 0)
        XCTAssertEqual(scheduler.intervals, [1, 0])
        scheduler.tasks[1].fire()
        eventLoop.sync {}

        XCTAssertEqual(delegate.reconnectCount, 1)
        XCTAssertEqual(controller.reconnectTimeInterval, 2)
    }

    func testResumeDuringDisconnectCallbacksWaitsForSocketCleanup() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.pending-disconnect")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true
        controller.beginUnexpectedDisconnect()
        let context = controller.socketDidDisconnect()

        controller.pause()
        XCTAssertNil(controller.resume(connectionIsDisconnected: true))
        XCTAssertTrue(scheduler.tasks.isEmpty)

        let schedule = controller.completeDisconnectCallbacks(context)
        XCTAssertEqual(schedule?.attemptCount, 1)
        XCTAssertEqual(schedule?.interval, 0)
        XCTAssertEqual(scheduler.intervals, [0])
    }

    func testResumeBeforeUnexpectedSocketDisconnectPreservesPendingReconnect() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.resume-before-disconnect")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true
        controller.beginUnexpectedDisconnect()

        controller.pause()
        XCTAssertNil(controller.resume(connectionIsDisconnected: false))
        XCTAssertTrue(scheduler.tasks.isEmpty)

        let context = controller.socketDidDisconnect()
        let schedule = controller.completeDisconnectCallbacks(context)
        XCTAssertEqual(schedule?.attemptCount, 1)
        XCTAssertEqual(schedule?.interval, 0)
        XCTAssertEqual(scheduler.intervals, [0])
    }

    func testStaleDisconnectCallbackDoesNotBlockCurrentLifecycle() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.overlapping-disconnects")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        let staleContext = controller.socketDidDisconnect()
        controller.isEnabled = false
        controller.isEnabled = true
        let currentContext = controller.socketDidDisconnect()

        let schedule = controller.completeDisconnectCallbacks(currentContext)
        XCTAssertEqual(schedule?.attemptCount, 1)
        XCTAssertEqual(schedule?.interval, 1)
        XCTAssertEqual(scheduler.intervals, [1])

        XCTAssertNil(controller.completeDisconnectCallbacks(staleContext))
        XCTAssertEqual(scheduler.tasks.count, 1)
    }

    func testConcurrentDisconnectCallbackCompletionsScheduleOnce() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.concurrent-disconnects")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true
        let contexts = [controller.socketDidDisconnect(), controller.socketDidDisconnect()]

        DispatchQueue.concurrentPerform(iterations: contexts.count) { index in
            _ = controller.completeDisconnectCallbacks(contexts[index])
        }

        XCTAssertEqual(scheduler.tasks.count, 1)
        XCTAssertEqual(scheduler.intervals, [1])
        XCTAssertEqual(controller.reconnectAttemptCount, 1)
    }

    func testResetDoesNotReviveStaleDisconnectCallback() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.stale-disconnect")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        let staleContext = controller.socketDidDisconnect()
        controller.isEnabled = false
        controller.isEnabled = true

        XCTAssertNil(controller.completeDisconnectCallbacks(staleContext))
        XCTAssertTrue(scheduler.tasks.isEmpty)
        XCTAssertEqual(controller.reconnectAttemptCount, 0)
    }

    func testOverlappingDisconnectWhileConnectingRecoversFromSynchronousFailure() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.connecting")
        let scheduler = Scheduler()
        let delegate = Delegate()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.delegate = delegate
        controller.isEnabled = true

        let firstContext = controller.socketDidDisconnect()
        XCTAssertNotNil(controller.completeDisconnectCallbacks(firstContext))
        let overlappingContext = controller.socketDidDisconnect()

        scheduler.tasks[0].fire()
        eventLoop.sync {}
        XCTAssertEqual(delegate.reconnectCount, 1)
        XCTAssertNil(controller.completeDisconnectCallbacks(overlappingContext))
        XCTAssertEqual(scheduler.tasks.count, 1)

        let retry = controller.reconnectAttemptFailedToStart()
        XCTAssertEqual(retry?.attemptCount, 2)
        XCTAssertEqual(retry?.interval, 2)
        XCTAssertEqual(scheduler.intervals, [1, 2])
    }

    func testDeinitializingControllerCancelsScheduledTask() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.deinit")
        let scheduler = Scheduler()
        var controller: MQTTAutoReconnectController? = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller?.isEnabled = true
        let context = controller?.socketDidDisconnect()
        XCTAssertNotNil(context.flatMap { controller?.completeDisconnectCallbacks($0) })
        let task = scheduler.tasks[0]

        weak var releasedController: MQTTAutoReconnectController?
        releasedController = controller
        controller = nil

        XCTAssertNil(releasedController)
        XCTAssertTrue(task.isCancelled)
    }

    func testExpectedDisconnectNeverSchedulesReconnect() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.expected")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        XCTAssertTrue(controller.beginExpectedDisconnect())
        XCTAssertFalse(controller.beginExpectedDisconnect())
        let context = controller.socketDidDisconnect()

        XCTAssertNil(controller.completeDisconnectCallbacks(context))
        XCTAssertTrue(scheduler.tasks.isEmpty)
        XCTAssertEqual(controller.reconnectAttemptCount, 0)
    }

    func testExpectedDisconnectCancelsScheduledReconnect() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.expected-cancels-scheduled")
        let scheduler = Scheduler()
        let delegate = Delegate()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.delegate = delegate
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertNotNil(controller.completeDisconnectCallbacks(context))
        let scheduledTask = scheduler.tasks[0]

        XCTAssertTrue(controller.beginExpectedDisconnect())
        XCTAssertTrue(scheduledTask.isCancelled)
        XCTAssertEqual(controller.reconnectAttemptCount, 0)
        XCTAssertEqual(controller.reconnectTimeInterval, 0)

        scheduledTask.fire()
        eventLoop.sync {}
        XCTAssertEqual(delegate.reconnectCount, 0)
    }

    func testExpectedDisconnectDiscardsPausedReconnect() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.expected-discards-paused")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertNotNil(controller.completeDisconnectCallbacks(context))
        controller.pause()

        XCTAssertTrue(controller.beginExpectedDisconnect())
        XCTAssertFalse(controller.isPaused)
        XCTAssertNil(controller.resume(connectionIsDisconnected: true))
        XCTAssertEqual(scheduler.tasks.count, 1)
    }

    func testSynchronousReconnectFailureSchedulesNextBackoff() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.synchronous-failure")
        let scheduler = Scheduler()
        let delegate = Delegate()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.delegate = delegate
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertEqual(controller.completeDisconnectCallbacks(context)?.interval, 1)
        scheduler.tasks[0].fire()
        eventLoop.sync {}

        let retry = controller.reconnectAttemptFailedToStart()
        XCTAssertEqual(retry?.attemptCount, 2)
        XCTAssertEqual(retry?.interval, 2)
        XCTAssertEqual(scheduler.intervals, [1, 2])
    }

    func testRepeatedSynchronousReconnectFailureUsesMinimumPositiveDelay() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.repeated-synchronous-failure")
        let scheduler = Scheduler()
        let delegate = Delegate()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.delegate = delegate
        controller.autoReconnectTimeInterval = 0
        controller.maxAutoReconnectTimeInterval = 0
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertEqual(controller.completeDisconnectCallbacks(context)?.interval, 0)
        scheduler.tasks[0].fire()
        eventLoop.sync {}

        let firstRetry = controller.reconnectAttemptFailedToStart()
        XCTAssertEqual(firstRetry?.attemptCount, 2)
        XCTAssertEqual(firstRetry?.interval, 1)
        scheduler.tasks[1].fire()
        eventLoop.sync {}

        let secondRetry = controller.reconnectAttemptFailedToStart()
        XCTAssertEqual(secondRetry?.attemptCount, 3)
        XCTAssertEqual(secondRetry?.interval, 1)
        XCTAssertEqual(scheduler.intervals, [0, 1, 1])
        XCTAssertEqual(controller.reconnectTimeInterval, 0)
    }

    func testPauseDuringSynchronousReconnectFailurePreservesRetry() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.paused-synchronous-failure")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )
        controller.isEnabled = true

        let context = controller.socketDidDisconnect()
        XCTAssertNotNil(controller.completeDisconnectCallbacks(context))
        scheduler.tasks[0].fire()
        eventLoop.sync {}

        controller.pause()
        XCTAssertNil(controller.reconnectAttemptFailedToStart())
        let retry = controller.resume(connectionIsDisconnected: true)

        XCTAssertEqual(retry?.attemptCount, 2)
        XCTAssertEqual(retry?.interval, 0)
        XCTAssertEqual(scheduler.intervals, [1, 0])
    }
}
