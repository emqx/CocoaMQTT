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
        XCTAssertTrue(waitUntil(timeout: 2) { store.snapshot().count == topics.count })

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
}
