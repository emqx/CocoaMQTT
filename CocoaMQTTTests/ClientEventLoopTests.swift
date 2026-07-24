import Foundation
import XCTest
@testable import CocoaMQTT

final class ClientEventLoopTests: XCTestCase {

    private final class WeakBox<Value: AnyObject> {
        weak var value: Value?

        init(_ value: Value?) {
            self.value = value
        }
    }

    private final class ClientHolder: @unchecked Sendable {
        var client: AnyObject?

        init(_ client: AnyObject) {
            self.client = client
        }
    }

    private final class BlockingTeardownSocket: CocoaMQTTSocketProtocol, MQTTClientTeardownSocket, @unchecked Sendable {
        var enableSSL = false

        let disconnectStarted = DispatchSemaphore(value: 0)
        let allowDisconnect = DispatchSemaphore(value: 0)

        func prepareClientTeardown() -> Bool {
            setDelegate(nil, delegateQueue: nil)
            return true
        }

        func performClientTeardown() {
            disconnect()
        }

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {
            disconnectStarted.signal()
            allowDisconnect.wait()
        }
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL = false

        private let lock = NSLock()
        private weak var delegate: CocoaMQTTSocketDelegate?
        private var _delegateQueue: DispatchQueue?
        private var _disconnectCallCount = 0
        var writeHandler: (() -> Void)?

        var capturedDelegateQueue: DispatchQueue? {
            lock.lock()
            defer { lock.unlock() }
            return _delegateQueue
        }

        var disconnectCallCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _disconnectCallCount
        }

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
            lock.lock()
            delegate = theDelegate
            _delegateQueue = delegateQueue
            lock.unlock()
        }

        func emitConnectedIgnoringDelegateQueue() {
            lock.lock()
            let delegate = delegate
            lock.unlock()
            delegate?.socketConnected(self)
        }

        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {
            lock.lock()
            _disconnectCallCount += 1
            lock.unlock()
        }
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

    func testMQTT311CustomSocketCallbacksAreNormalizedOntoEventLoop() {
        let socket = SocketSpy()
        let mqtt = CocoaMQTT(clientID: "custom-socket-event-loop-311", socket: socket)
        let eventLoopKey = DispatchSpecificKey<Bool>()
        mqtt.eventLoopQueue.setSpecific(key: eventLoopKey, value: true)
        let write = expectation(description: "CONNECT is written from event loop")
        socket.writeHandler = {
            XCTAssertEqual(DispatchQueue.getSpecific(key: eventLoopKey), true)
            write.fulfill()
        }

        XCTAssertTrue(mqtt.connect())
        DispatchQueue.global().async {
            socket.emitConnectedIgnoringDelegateQueue()
        }

        wait(for: [write], timeout: 1)
    }

    func testMQTT5CustomSocketCallbacksAreNormalizedOntoEventLoop() {
        let socket = SocketSpy()
        let mqtt5 = CocoaMQTT5(clientID: "custom-socket-event-loop-5", socket: socket)
        let eventLoopKey = DispatchSpecificKey<Bool>()
        mqtt5.eventLoopQueue.setSpecific(key: eventLoopKey, value: true)
        let write = expectation(description: "CONNECT is written from event loop")
        socket.writeHandler = {
            XCTAssertEqual(DispatchQueue.getSpecific(key: eventLoopKey), true)
            write.fulfill()
        }

        XCTAssertTrue(mqtt5.connect())
        DispatchQueue.global().async {
            socket.emitConnectedIgnoringDelegateQueue()
        }

        wait(for: [write], timeout: 1)
    }

    func testPendingCallbackDoesNotRetainMQTT311Client() {
        let callbackQueue = DispatchQueue(label: "tests.event-loop.blocked-callback-311")
        let releaseQueue = DispatchSemaphore(value: 0)
        callbackQueue.async { releaseQueue.wait() }

        var mqtt: CocoaMQTT? = CocoaMQTT(clientID: "callback-lifetime-311")
        let weakMQTT = WeakBox(mqtt)
        mqtt?.delegateQueue = callbackQueue
        mqtt?.ping()
        mqtt = nil

        XCTAssertNil(weakMQTT.value)
        releaseQueue.signal()
        callbackQueue.sync {}
    }

    func testPendingCallbackDoesNotRetainMQTT5Client() {
        let callbackQueue = DispatchQueue(label: "tests.event-loop.blocked-callback-5")
        let releaseQueue = DispatchSemaphore(value: 0)
        callbackQueue.async { releaseQueue.wait() }

        var mqtt5: CocoaMQTT5? = CocoaMQTT5(clientID: "callback-lifetime-5")
        let weakMQTT5 = WeakBox(mqtt5)
        mqtt5?.delegateQueue = callbackQueue
        mqtt5?.ping()
        mqtt5 = nil

        XCTAssertNil(weakMQTT5.value)
        releaseQueue.signal()
        callbackQueue.sync {}
    }

    func testMQTT311DeinitDoesNotWaitForNativeTransportDisconnect() {
        assertDeinitDoesNotWaitForNativeTransportDisconnect {
            CocoaMQTT(clientID: "nonblocking-deinit-311", socket: $0)
        }
    }

    func testMQTT5DeinitDoesNotWaitForNativeTransportDisconnect() {
        assertDeinitDoesNotWaitForNativeTransportDisconnect {
            CocoaMQTT5(clientID: "nonblocking-deinit-5", socket: $0)
        }
    }

    func testCustomSocketRetainsSynchronousDeinitCleanupByDefault() {
        let socket = SocketSpy()
        var mqtt311: CocoaMQTT? = CocoaMQTT(clientID: "custom-deinit-311", socket: socket)
        var mqtt5: CocoaMQTT5? = CocoaMQTT5(clientID: "custom-deinit-5", socket: socket)

        XCTAssertNotNil(mqtt311)
        XCTAssertNotNil(mqtt5)
        mqtt311 = nil
        XCTAssertEqual(socket.disconnectCallCount, 1)
        mqtt5 = nil
        XCTAssertEqual(socket.disconnectCallCount, 2)
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

    private func assertDeinitDoesNotWaitForNativeTransportDisconnect(
        makeClient: (CocoaMQTTSocketProtocol) -> AnyObject
    ) {
        let socket = BlockingTeardownSocket()
        let holder = ClientHolder(makeClient(socket))
        let releaseReturned = DispatchSemaphore(value: 0)

        DispatchQueue(label: "tests.client-release").async {
            holder.client = nil
            releaseReturned.signal()
        }

        XCTAssertEqual(socket.disconnectStarted.wait(timeout: .now() + 1), .success)
        let result = releaseReturned.wait(timeout: .now() + 1)
        socket.allowDisconnect.signal()

        XCTAssertEqual(result, .success)
        if result != .success {
            XCTAssertEqual(releaseReturned.wait(timeout: .now() + 1), .success)
        }
    }
}
