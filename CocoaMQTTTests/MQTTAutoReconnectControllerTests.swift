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

    func testReconnectBackoffIsSharedAndClamped() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.backoff")
        let scheduler = Scheduler()
        var reconnectCount = 0
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler,
            reconnect: { reconnectCount += 1 }
        )
        controller.isEnabled = true
        controller.autoReconnectTimeInterval = 1
        controller.maxAutoReconnectTimeInterval = 3

        let first = controller.socketDidDisconnect()
        let firstSchedule = controller.completeDisconnectCallbacks(first)
        XCTAssertEqual(firstSchedule?.attemptCount, 1)
        XCTAssertEqual(firstSchedule?.interval, 1)
        scheduler.tasks[0].fire()
        eventLoop.sync {}
        XCTAssertEqual(reconnectCount, 1)
        XCTAssertEqual(controller.reconnectTimeInterval, 2)

        let second = controller.socketDidDisconnect()
        let secondSchedule = controller.completeDisconnectCallbacks(second)
        XCTAssertEqual(secondSchedule?.attemptCount, 2)
        XCTAssertEqual(secondSchedule?.interval, 2)
        scheduler.tasks[1].fire()
        eventLoop.sync {}
        XCTAssertEqual(reconnectCount, 2)
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
            scheduler: scheduler,
            reconnect: {}
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
            scheduler: scheduler,
            reconnect: {}
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
        var reconnectCount = 0
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler,
            reconnect: { reconnectCount += 1 }
        )
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

        XCTAssertEqual(reconnectCount, 1)
        XCTAssertEqual(controller.reconnectTimeInterval, 2)
    }

    func testResumeDuringDisconnectCallbacksWaitsForSocketCleanup() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.pending-disconnect")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler,
            reconnect: {}
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

    func testExpectedDisconnectNeverSchedulesReconnect() {
        let eventLoop = DispatchQueue(label: "tests.reconnect-controller.expected")
        let scheduler = Scheduler()
        let controller = MQTTAutoReconnectController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler,
            reconnect: {}
        )
        controller.isEnabled = true

        XCTAssertTrue(controller.beginExpectedDisconnect())
        XCTAssertFalse(controller.beginExpectedDisconnect())
        let context = controller.socketDidDisconnect()

        XCTAssertTrue(context.suppressesReconnect)
        XCTAssertNil(controller.completeDisconnectCallbacks(context))
        XCTAssertTrue(scheduler.tasks.isEmpty)
        XCTAssertEqual(controller.reconnectAttemptCount, 0)
    }
}
