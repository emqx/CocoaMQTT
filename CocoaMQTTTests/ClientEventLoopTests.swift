import Foundation
import XCTest
@testable import CocoaMQTT

final class ClientEventLoopTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL = false

        private let lock = NSLock()
        private var _delegateQueue: DispatchQueue?
        var writeHandler: (() -> Void)?

        var capturedDelegateQueue: DispatchQueue? {
            lock.lock()
            defer { lock.unlock() }
            return _delegateQueue
        }

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
            lock.lock()
            _delegateQueue = delegateQueue
            lock.unlock()
        }

        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
            writeHandler?()
        }
    }

    func testMQTT311SocketAndCallbacksUseSeparateQueues() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "event-loop-311", socket: socket)
        let eventLoopKey = DispatchSpecificKey<String>()
        let callbackKey = DispatchSpecificKey<String>()
        let callbackQueue = DispatchQueue(label: "tests.event-loop.callback-311", attributes: .concurrent)
        mqtt.eventLoopQueue.setSpecific(key: eventLoopKey, value: "event-loop")
        callbackQueue.setSpecific(key: callbackKey, value: "callback")
        mqtt.delegateQueue = callbackQueue

        XCTAssertTrue(mqtt.connect())
        XCTAssertTrue(socket.capturedDelegateQueue === mqtt.eventLoopQueue)
        XCTAssertFalse(socket.capturedDelegateQueue === callbackQueue)

        let callback = expectation(description: "PONG callback")
        mqtt.didReceivePong = { _ in
            XCTAssertEqual(DispatchQueue.getSpecific(key: callbackKey), "callback")
            XCTAssertNil(DispatchQueue.getSpecific(key: eventLoopKey))
            callback.fulfill()
        }
        mqtt.eventLoopQueue.async {
            mqtt.didReceive(
                CocoaMQTTReader(socket: socket, delegate: nil),
                pingresp: FramePingResp()
            )
        }

        wait(for: [callback], timeout: 1)
    }

    func testMQTT5SocketAndCallbacksUseSeparateQueues() {
        let socket = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: "event-loop-5", socket: socket)
        let eventLoopKey = DispatchSpecificKey<String>()
        let callbackKey = DispatchSpecificKey<String>()
        let callbackQueue = DispatchQueue(label: "tests.event-loop.callback-5", attributes: .concurrent)
        mqtt5.eventLoopQueue.setSpecific(key: eventLoopKey, value: "event-loop")
        callbackQueue.setSpecific(key: callbackKey, value: "callback")
        mqtt5.delegateQueue = callbackQueue

        XCTAssertTrue(mqtt5.connect())
        XCTAssertTrue(socket.capturedDelegateQueue === mqtt5.eventLoopQueue)
        XCTAssertFalse(socket.capturedDelegateQueue === callbackQueue)

        let callback = expectation(description: "PONG callback")
        mqtt5.didReceivePong = { _ in
            XCTAssertEqual(DispatchQueue.getSpecific(key: callbackKey), "callback")
            XCTAssertNil(DispatchQueue.getSpecific(key: eventLoopKey))
            callback.fulfill()
        }
        mqtt5.eventLoopQueue.async {
            mqtt5.didReceive(
                CocoaMQTTReader(socket: socket, delegate: nil, protocolVersion: .v5),
                pingresp: FramePingResp()
            )
        }

        wait(for: [callback], timeout: 1)
    }

    func testCallbackQueueChangeDoesNotMoveAlreadySubmittedCallbacks() {
        let mqtt = CocoaMQTT(clientID: "callback-queue-snapshot")
        let firstQueue = DispatchQueue(label: "tests.event-loop.first-callback")
        let secondQueue = DispatchQueue(label: "tests.event-loop.second-callback")
        let queueKey = DispatchSpecificKey<String>()
        let unblockFirstQueue = DispatchSemaphore(value: 0)
        firstQueue.setSpecific(key: queueKey, value: "first")
        secondQueue.setSpecific(key: queueKey, value: "second")

        firstQueue.async {
            unblockFirstQueue.wait()
        }

        let callbacks = expectation(description: "callbacks use event-time queue snapshots")
        callbacks.expectedFulfillmentCount = 2
        let lock = NSLock()
        var observedQueues: [String] = []
        mqtt.didReceivePong = { _ in
            lock.lock()
            observedQueues.append(DispatchQueue.getSpecific(key: queueKey) ?? "unknown")
            lock.unlock()
            callbacks.fulfill()
        }

        mqtt.delegateQueue = firstQueue
        mqtt.didReceive(
            CocoaMQTTReader(socket: CocoaMQTTSocket(), delegate: nil),
            pingresp: FramePingResp()
        )
        mqtt.delegateQueue = secondQueue
        mqtt.didReceive(
            CocoaMQTTReader(socket: CocoaMQTTSocket(), delegate: nil),
            pingresp: FramePingResp()
        )
        unblockFirstQueue.signal()

        wait(for: [callbacks], timeout: 1)
        XCTAssertEqual(Set(observedQueues), Set(["first", "second"]))
    }

    func testDeliveryWorkReturnsToMQTT311EventLoop() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "delivery-event-loop-311", socket: socket)
        let eventLoopKey = DispatchSpecificKey<Bool>()
        mqtt.eventLoopQueue.setSpecific(key: eventLoopKey, value: true)
        let write = expectation(description: "delivery writes from event loop")
        socket.writeHandler = {
            XCTAssertEqual(DispatchQueue.getSpecific(key: eventLoopKey), true)
            write.fulfill()
        }

        XCTAssertEqual(mqtt.publish("event/loop", withString: "payload", qos: .qos0), 0)

        wait(for: [write], timeout: 1)
    }

    func testDeliveryWorkReturnsToMQTT5EventLoop() {
        let socket = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: "delivery-event-loop-5", socket: socket)
        let eventLoopKey = DispatchSpecificKey<Bool>()
        mqtt5.eventLoopQueue.setSpecific(key: eventLoopKey, value: true)
        let write = expectation(description: "delivery writes from event loop")
        socket.writeHandler = {
            XCTAssertEqual(DispatchQueue.getSpecific(key: eventLoopKey), true)
            write.fulfill()
        }

        XCTAssertEqual(
            mqtt5.publish(
                "event/loop",
                withString: "payload",
                qos: .qos0,
                properties: MqttPublishProperties()
            ),
            0
        )

        wait(for: [write], timeout: 1)
    }
}
