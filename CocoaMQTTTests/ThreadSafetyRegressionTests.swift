//
//  ThreadSafetyRegressionTests.swift
//  CocoaMQTTTests
//

import XCTest
@testable import CocoaMQTT
#if IS_SWIFT_PACKAGE
@testable import CocoaMQTTWebSocket
#endif

final class ThreadSafetyRegressionTests: XCTestCase {

    private final class SocketDelegateStub: CocoaMQTTSocketDelegate {
        func socketConnected(_ socket: CocoaMQTTSocketProtocol) {}
        func socket(_ socket: CocoaMQTTSocketProtocol, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
        func socketUrlSession(_ socket: CocoaMQTTSocketProtocol, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }
        func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {}
        func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {}
        func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError err: Error?) {}
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            usleep(10_000)
        }
        return condition()
    }

    func testCocoaMQTTSubscriptionsConcurrentAccess() {
        let mqtt = CocoaMQTT(clientID: "thread-safe-subscriptions-\(UUID().uuidString)")
        let _: [String: CocoaMQTTQoS] = mqtt.subscriptions
        mqtt.subscriptions = ["seed/topic": .qos1]
        XCTAssertEqual(mqtt.subscriptions["seed/topic"], .qos1)

        let store = ThreadSafeDictionary<String, CocoaMQTTQoS>(label: "tests.threadsafe.subscriptions.store")
        let topics = (0..<80).map { "t/\($0)" }
        let queue = DispatchQueue(label: "tests.threadsafe.subscriptions", attributes: .concurrent)
        let group = DispatchGroup()
        let inflightLimit = DispatchSemaphore(value: 8)
        let iterations = 400

        for idx in 0..<iterations {
            group.enter()
            queue.async {
                inflightLimit.wait()
                defer {
                    inflightLimit.signal()
                    group.leave()
                }

                let topic = topics[idx % topics.count]
                store[topic] = (idx % 4 == 0) ? .qos0 : .qos1
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(store.snapshot().count, topics.count)

        let readQueue = DispatchQueue(label: "tests.threadsafe.subscriptions.read", attributes: .concurrent)
        let readGroup = DispatchGroup()
        for idx in 0..<iterations {
            readGroup.enter()
            readQueue.async {
                _ = store[topics[idx % topics.count]]
                readGroup.leave()
            }
        }
        XCTAssertEqual(readGroup.wait(timeout: .now() + 10), .success)
    }

    func testThreadSafeDictionarySequenceIterationUsesSnapshots() {
        let store = ThreadSafeDictionary<String, Int>(
            label: "tests.threadsafe.collection",
            dict: ["a": 1, "b": 2]
        )
        let sequence = AnySequence(store)

        XCTAssertEqual(store.count, 2)
        XCTAssertFalse(store.isEmpty)
        XCTAssertNotNil(store.first)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: sequence.map { ($0.key, $0.value) }),
            ["a": 1, "b": 2]
        )
    }

    func testThreadSafeDictionaryIteratesWhileMutating() {
        let store = ThreadSafeDictionary<Int, Int>(label: "tests.threadsafe.snapshot-iteration")
        let queue = DispatchQueue(label: "tests.threadsafe.snapshot-writes", attributes: .concurrent)
        let group = DispatchGroup()

        for worker in 0..<4 {
            group.enter()
            queue.async {
                for value in stride(from: worker, to: 2_000, by: 4) {
                    store[value] = value
                }
                group.leave()
            }
        }

        for _ in 0..<100 {
            XCTAssertTrue(store.allSatisfy { $0.key == $0.value })
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(store.count, 2_000)
    }

    func testWebSocketDelegateAndLoggerConcurrentAccess() {
        let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
        let delegateA = SocketDelegateStub()
        let delegateB = SocketDelegateStub()

        let queue = DispatchQueue(label: "tests.threadsafe.websocket", attributes: .concurrent)
        let group = DispatchGroup()
        let inflightLimit = DispatchSemaphore(value: 8)
        let iterations = 300

        for idx in 0..<iterations {
            group.enter()
            queue.async {
                inflightLimit.wait()
                defer {
                    inflightLimit.signal()
                    group.leave()
                }

                let delegate = (idx % 2 == 0) ? delegateA : delegateB
                websocket.setDelegate(delegate, delegateQueue: DispatchQueue.global())
                CocoaMQTTLogger.logger.minLevel = (idx % 2 == 0) ? .debug : .error
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        websocket.internalQueue.sync {}

        XCTAssertTrue(waitUntil(timeout: 2) { websocket.delegate != nil })
        XCTAssertTrue([.debug, .error].contains(CocoaMQTTLogger.logger.minLevel))

        let readQueue = DispatchQueue(label: "tests.threadsafe.websocket.read", attributes: .concurrent)
        let readGroup = DispatchGroup()
        for _ in 0..<iterations {
            readGroup.enter()
            readQueue.async {
                _ = websocket.delegate
                _ = CocoaMQTTLogger.logger.minLevel
                readGroup.leave()
            }
        }
        XCTAssertEqual(readGroup.wait(timeout: .now() + 10), .success)
    }

    func testCocoaMQTT5ConnStateConcurrentAccess() {
        let mqtt5 = CocoaMQTT5(clientID: "thread-safe-connstate-\(UUID().uuidString)")
        let queue = DispatchQueue(label: "tests.threadsafe.connstate", attributes: .concurrent)
        let group = DispatchGroup()
        let inflightLimit = DispatchSemaphore(value: 8)

        for idx in 0..<300 {
            group.enter()
            queue.async {
                inflightLimit.wait()
                defer {
                    inflightLimit.signal()
                    group.leave()
                }

                mqtt5.connState = (idx % 2 == 0) ? .connecting : .connected
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        let readQueue = DispatchQueue(label: "tests.threadsafe.connstate.read", attributes: .concurrent)
        let readGroup = DispatchGroup()
        for _ in 0..<300 {
            readGroup.enter()
            readQueue.async {
                _ = mqtt5.connState
                readGroup.leave()
            }
        }

        XCTAssertEqual(readGroup.wait(timeout: .now() + 10), .success)
        XCTAssertTrue([.connecting, .connected, .disconnected].contains(mqtt5.connState))
    }

    func testCocoaMQTT311ConnStateConcurrentAccess() {
        let mqtt = CocoaMQTT(clientID: "thread-safe-connstate-311-\(UUID().uuidString)")
        let queue = DispatchQueue(label: "tests.threadsafe.connstate-311", attributes: .concurrent)
        let group = DispatchGroup()

        for idx in 0..<300 {
            group.enter()
            queue.async {
                mqtt.connState = (idx % 2 == 0) ? .connecting : .connected
                _ = mqtt.connState
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertTrue([.connecting, .connected].contains(mqtt.connState))
    }

    func testCocoaMQTT5ConnStateCallbacksPreserveWrittenStates() {
        let mqtt5 = CocoaMQTT5(clientID: "connstate-callbacks-\(UUID().uuidString)")
        let callbackQueue = DispatchQueue(label: "tests.threadsafe.connstate-callbacks")
        let callbackGate = DispatchSemaphore(value: 0)
        let callbacksReceived = expectation(description: "State callbacks received")
        callbacksReceived.expectedFulfillmentCount = 2
        var receivedStates = [CocoaMQTTConnState]()

        callbackQueue.async {
            callbackGate.wait()
        }
        mqtt5.delegateQueue = callbackQueue
        mqtt5.didChangeState = { _, state in
            receivedStates.append(state)
            callbacksReceived.fulfill()
        }

        mqtt5.connState = .connecting
        mqtt5.connState = .connected
        callbackGate.signal()

        wait(for: [callbacksReceived], timeout: 1)
        callbackQueue.sync {}
        XCTAssertEqual(receivedStates, [.connecting, .connected])
    }

    func testCocoaMQTT5ConnStateCallbacksFollowConcurrentDelegateQueueSemantics() {
        let mqtt5 = CocoaMQTT5(clientID: "connstate-concurrent-callbacks-\(UUID().uuidString)")
        mqtt5.delegateQueue = DispatchQueue(
            label: "tests.threadsafe.connstate-concurrent-callbacks",
            attributes: .concurrent
        )
        let firstCallbackStarted = DispatchSemaphore(value: 0)
        let releaseFirstCallback = DispatchSemaphore(value: 0)
        let secondCallbackStarted = DispatchSemaphore(value: 0)
        let callbacksFinished = expectation(description: "Concurrent state callbacks finished")
        callbacksFinished.expectedFulfillmentCount = 2

        mqtt5.didChangeState = { _, state in
            if state == .connecting {
                firstCallbackStarted.signal()
                releaseFirstCallback.wait()
            } else if state == .connected {
                secondCallbackStarted.signal()
            }
            callbacksFinished.fulfill()
        }

        mqtt5.connState = .connecting
        mqtt5.connState = .connected

        XCTAssertEqual(firstCallbackStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(secondCallbackStarted.wait(timeout: .now() + 1), .success)
        releaseFirstCallback.signal()
        wait(for: [callbacksFinished], timeout: 1)
    }

    func testConcurrentPublishesAllocateUniquePacketIdentifiers() {
        let mqtt = CocoaMQTT(clientID: "thread-safe-publish-\(UUID().uuidString)", socket: SocketStub())
        mqtt.delegateQueue = DispatchQueue(label: "tests.threadsafe.publish.delegate")
        let queue = DispatchQueue(label: "tests.threadsafe.publish", attributes: .concurrent)
        let group = DispatchGroup()
        let identifiers = ThreadSafeDictionary<Int, Bool>(label: "tests.threadsafe.publish.identifiers")

        for index in 0..<400 {
            group.enter()
            queue.async {
                let identifier = mqtt.publish(
                    CocoaMQTTMessage(topic: "t/\(index)", payload: [UInt8(index % 255)], qos: .qos1)
                )
                identifiers[identifier] = true
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(identifiers.snapshot().count, 400)
        XCTAssertFalse(identifiers.snapshot().keys.contains(-1))

        mqtt.socketDidDisconnect(SocketStub(), withError: nil)
    }

    func testPacketIdentifierAllocatorExhaustionAndReuse() {
        let allocator = MQTTPacketIdentifierAllocator()
        var identifiers = Set<UInt16>()

        for _ in 0..<Int(UInt16.max) {
            guard let identifier = allocator.reserve() else {
                return XCTFail("Allocator exhausted before all valid identifiers were reserved")
            }
            XCTAssertTrue(identifiers.insert(identifier).inserted)
        }

        XCTAssertEqual(allocator.reservedCount, Int(UInt16.max))
        XCTAssertNil(allocator.reserve())
        allocator.release(42)
        XCTAssertEqual(allocator.reserve(), 42)
        XCTAssertFalse(allocator.reserve(0))
    }

    private final class SocketStub: CocoaMQTTSocketProtocol {
        var enableSSL = false

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }
}
