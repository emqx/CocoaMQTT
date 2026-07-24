import Foundation
import XCTest
@testable import CocoaMQTT

final class KeepAliveTests: XCTestCase {

    private final class ScheduledTask: MQTTKeepAliveScheduledTask {
        private let action: () -> Void
        private(set) var isCancelled = false

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }

        func fireIgnoringCancellation() {
            action()
        }
    }

    private final class Scheduler: MQTTKeepAliveScheduling {
        private(set) var intervals = [TimeInterval]()
        private(set) var tasks = [ScheduledTask]()

        func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> MQTTKeepAliveScheduledTask {
            let task = ScheduledTask(action: action)
            intervals.append(interval)
            tasks.append(task)
            return task
        }
    }

    private final class KeepAliveDelegate: MQTTKeepAliveControllerDelegate {
        private(set) var pingCount = 0
        private(set) var timeoutCount = 0

        func keepAliveControllerRequestsPing(_ controller: MQTTKeepAliveController) {
            pingCount += 1
        }

        func keepAliveControllerDidTimeOut(_ controller: MQTTKeepAliveController) {
            timeoutCount += 1
        }
    }

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL = false

        private let lock = NSLock()
        private weak var delegate: CocoaMQTTSocketDelegate?
        private var delegateQueue: DispatchQueue?

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
            lock.lock()
            delegate = theDelegate
            self.delegateQueue = delegateQueue
            lock.unlock()
        }
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {
            lock.lock()
            let delegate = delegate
            let delegateQueue = delegateQueue
            lock.unlock()
            delegateQueue?.async {
                delegate?.socketDidDisconnect(self, withError: nil)
            }
        }
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    func testMQTT311DisconnectsWhenPingResponseDoesNotArrive() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "keepalive-timeout-\(UUID().uuidString)", socket: socket)
        mqtt.keepAlive = 1
        mqtt.autoReconnect = true
        let reconnectScheduled = expectation(description: "missing PINGRESP schedules reconnect")
        mqtt.didScheduleReconnect = { _, _, _ in
            reconnectScheduled.fulfill()
        }

        establishSession(mqtt, socket: socket)

        wait(for: [reconnectScheduled], timeout: 2.5)
    }

    func testMQTT5DisconnectsWhenPingResponseDoesNotArrive() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT5(clientID: "keepalive-timeout-5-\(UUID().uuidString)", socket: socket)
        mqtt.keepAlive = 1
        mqtt.autoReconnect = true
        let reconnectScheduled = expectation(description: "missing MQTT 5 PINGRESP schedules reconnect")
        mqtt.didScheduleReconnect = { _, _, _ in
            reconnectScheduled.fulfill()
        }

        establishSession(mqtt, socket: socket)

        wait(for: [reconnectScheduled], timeout: 2.5)
    }

    func testMQTT311KeepAliveZeroDisablesAutomaticPing() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "keepalive-disabled-\(UUID().uuidString)", socket: socket)
        mqtt.keepAlive = 0

        establishSession(mqtt, socket: socket)

        XCTAssertNil(mqtt.t_keepAliveInterval())
    }

    func testControllerTimesOutAfterOneUnansweredPing() {
        let eventLoop = DispatchQueue(label: "tests.keepalive.timeout")
        let scheduler = Scheduler()
        let delegate = KeepAliveDelegate()
        let controller = MQTTKeepAliveController(eventLoopQueue: eventLoop, scheduler: scheduler)
        controller.delegate = delegate

        controller.start(interval: 7)
        XCTAssertEqual(scheduler.intervals, [7])

        scheduler.tasks[0].fireIgnoringCancellation()
        eventLoop.sync {}
        XCTAssertEqual(delegate.pingCount, 1)
        XCTAssertEqual(delegate.timeoutCount, 0)
        XCTAssertEqual(scheduler.intervals, [7, 7])

        scheduler.tasks[1].fireIgnoringCancellation()
        eventLoop.sync {}
        XCTAssertEqual(delegate.timeoutCount, 1)
        XCTAssertNil(controller.interval)
    }

    func testPingResponseStartsANewIdlePeriodAndInvalidatesOldTimeout() {
        let eventLoop = DispatchQueue(label: "tests.keepalive.response")
        let scheduler = Scheduler()
        let delegate = KeepAliveDelegate()
        let controller = MQTTKeepAliveController(eventLoopQueue: eventLoop, scheduler: scheduler)
        controller.delegate = delegate

        controller.start(interval: 9)
        scheduler.tasks[0].fireIgnoringCancellation()
        eventLoop.sync {}
        let staleTimeout = scheduler.tasks[1]

        controller.pingResponseReceived()
        XCTAssertTrue(staleTimeout.isCancelled)
        staleTimeout.fireIgnoringCancellation()
        eventLoop.sync {}
        XCTAssertEqual(delegate.timeoutCount, 0)

        scheduler.tasks[2].fireIgnoringCancellation()
        eventLoop.sync {}
        XCTAssertEqual(delegate.pingCount, 2)
    }

    func testRepeatedManualPingDoesNotExtendOutstandingResponseDeadline() {
        let eventLoop = DispatchQueue(label: "tests.keepalive.manual-ping")
        let scheduler = Scheduler()
        let controller = MQTTKeepAliveController(eventLoopQueue: eventLoop, scheduler: scheduler)

        controller.start(interval: 5)
        controller.pingSent()
        let responseDeadline = scheduler.tasks[1]
        controller.pingSent()

        XCTAssertEqual(scheduler.tasks.count, 2)
        XCTAssertFalse(responseDeadline.isCancelled)
    }

    func testStartingWithZeroKeepAliveSchedulesNothing() {
        let eventLoop = DispatchQueue(label: "tests.keepalive.disabled")
        let scheduler = Scheduler()
        let controller = MQTTKeepAliveController(eventLoopQueue: eventLoop, scheduler: scheduler)

        controller.start(interval: 0)

        XCTAssertTrue(scheduler.tasks.isEmpty)
        XCTAssertNil(controller.interval)
    }

    func testDeinitializingControllerCancelsScheduledTask() {
        let eventLoop = DispatchQueue(label: "tests.keepalive.deinit")
        let scheduler = Scheduler()
        var controller: MQTTKeepAliveController? = MQTTKeepAliveController(
            eventLoopQueue: eventLoop,
            scheduler: scheduler
        )

        controller?.start(interval: 5)
        let scheduledTask = scheduler.tasks[0]
        controller = nil

        XCTAssertTrue(scheduledTask.isCancelled)
    }

    private func establishSession(_ mqtt: CocoaMQTT, socket: SocketSpy) {
        XCTAssertTrue(mqtt.connect())
        mqtt.socketConnected(socket)
        let connack = FrameConnAck(
            packetFixedHeaderType: FrameType.connack.rawValue,
            bytes: [0, CocoaMQTTConnAck.accept.rawValue],
            protocolVersion: .v311
        )
        XCTAssertNotNil(connack)
        if let connack {
            mqtt.didReceive(
                CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v311),
                connack: connack
            )
        }
    }

    private func establishSession(_ mqtt: CocoaMQTT5, socket: SocketSpy) {
        XCTAssertTrue(mqtt.connect())
        mqtt.socketConnected(socket)
        let connack = FrameConnAck(
            packetFixedHeaderType: FrameType.connack.rawValue,
            bytes: [
                0,
                CocoaMQTTCONNACKReasonCode.success.rawValue,
                0
            ],
            protocolVersion: .v5
        )
        XCTAssertNotNil(connack)
        if let connack {
            mqtt.didReceive(
                CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5),
                connack: connack
            )
        }
    }
}
