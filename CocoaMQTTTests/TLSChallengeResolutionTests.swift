import Foundation
import Security
import XCTest
@testable import CocoaMQTT

final class TLSChallengeResolutionTests: XCTestCase {
    private final class SocketStub: CocoaMQTTSocketProtocol {
        var enableSSL = false

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {}
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    private final class ChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
        func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
        func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
    }

    private final class MQTT311DelegateStub: NSObject, CocoaMQTTDelegate {
        var legacyTrustCallCount = 0
        var urlSessionTrustCallCount = 0

        func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {}
        func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
        func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
        func mqttDidPing(_ mqtt: CocoaMQTT) {}
        func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
        func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {}

        func mqtt(
            _ mqtt: CocoaMQTT,
            didReceive trust: SecTrust,
            completionHandler: @escaping (Bool) -> Void
        ) {
            legacyTrustCallCount += 1
            completionHandler(false)
        }

        func mqttUrlSession(
            _ mqtt: CocoaMQTT,
            didReceiveTrust trust: SecTrust,
            didReceiveChallenge challenge: URLAuthenticationChallenge,
            completionHandler: @escaping CocoaMQTTTrustHandling.URLSessionCompletion
        ) {
            urlSessionTrustCallCount += 1
            completionHandler(.performDefaultHandling, nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private final class MQTT5DelegateStub: NSObject, CocoaMQTT5Delegate {
        var legacyTrustCallCount = 0
        var urlSessionTrustCallCount = 0

        func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}
        func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
        func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
        func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}
        func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {}

        func mqtt5(
            _ mqtt5: CocoaMQTT5,
            didReceive trust: SecTrust,
            completionHandler: @escaping (Bool) -> Void
        ) {
            legacyTrustCallCount += 1
            completionHandler(false)
        }

        func mqtt5UrlSession(
            _ mqtt5: CocoaMQTT5,
            didReceiveTrust trust: SecTrust,
            didReceiveChallenge challenge: URLAuthenticationChallenge,
            completionHandler: @escaping CocoaMQTTTrustHandling.URLSessionCompletion
        ) {
            urlSessionTrustCallCount += 1
            completionHandler(.performDefaultHandling, nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func testManualTrustDefaultsToRejecting() {
        var decisions = [Bool]()

        CocoaMQTTTrustHandling.resolveManualTrust(
            handler: { _ in false },
            completionHandler: { decisions.append($0) }
        )

        XCTAssertEqual(decisions, [false])
    }

    func testManualTrustHandlerCanCompleteOnlyOnce() {
        var decisions = [Bool]()

        CocoaMQTTTrustHandling.resolveManualTrust(
            handler: { completion in
                completion(true)
                completion(false)
                return true
            },
            completionHandler: { decisions.append($0) }
        )

        XCTAssertEqual(decisions, [true])
    }

    func testURLSessionChallengeDefaultsToSystemValidation() throws {
        var dispositions = [URLSession.AuthChallengeDisposition]()

        CocoaMQTTTrustHandling.resolveURLSessionChallenge(
            urlSessionHandler: { _ in false },
            legacyHandler: { _ in false },
            legacyCredential: try makeCredential(),
            completionHandler: { disposition, _ in dispositions.append(disposition) }
        )

        XCTAssertEqual(dispositions, [.performDefaultHandling])
    }

    func testURLSessionHandlerTakesPrecedenceOverLegacyHandler() throws {
        var legacyHandlerCalled = false
        var dispositions = [URLSession.AuthChallengeDisposition]()

        CocoaMQTTTrustHandling.resolveURLSessionChallenge(
            urlSessionHandler: { completion in
                completion(.cancelAuthenticationChallenge, nil)
                return true
            },
            legacyHandler: { _ in
                legacyHandlerCalled = true
                return true
            },
            legacyCredential: try makeCredential(),
            completionHandler: { disposition, _ in dispositions.append(disposition) }
        )

        XCTAssertFalse(legacyHandlerCalled)
        XCTAssertEqual(dispositions, [.cancelAuthenticationChallenge])
    }

    func testURLSessionChallengeWaitsForAsynchronousLegacyDecision() throws {
        var legacyCompletion: ((Bool) -> Void)?
        var dispositions = [URLSession.AuthChallengeDisposition]()

        CocoaMQTTTrustHandling.resolveURLSessionChallenge(
            urlSessionHandler: { _ in false },
            legacyHandler: { completion in
                legacyCompletion = completion
                return true
            },
            legacyCredential: try makeCredential(),
            completionHandler: { disposition, _ in dispositions.append(disposition) }
        )

        XCTAssertTrue(dispositions.isEmpty)
        try XCTUnwrap(legacyCompletion)(false)
        XCTAssertEqual(dispositions, [.rejectProtectionSpace])
    }

    func testURLSessionCompletionIsThreadSafeAndRunsOnce() throws {
        var challengeCompletion: CocoaMQTTTrustHandling.URLSessionCompletion?
        let callbackLock = NSLock()
        var callbackCount = 0

        CocoaMQTTTrustHandling.resolveURLSessionChallenge(
            urlSessionHandler: { completion in
                challengeCompletion = completion
                return true
            },
            legacyHandler: { _ in false },
            legacyCredential: try makeCredential(),
            completionHandler: { _, _ in
                callbackLock.lock()
                callbackCount += 1
                callbackLock.unlock()
            }
        )

        let completion = try XCTUnwrap(challengeCompletion)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            completion(.performDefaultHandling, nil)
        }

        XCTAssertEqual(callbackCount, 1)
    }

    func testMQTT311URLSessionChallengeUsesSystemValidationByDefault() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT(clientID: "tls-default-311", socket: socket)

        try assertSystemDefaultChallengeHandling(client: mqtt, socket: socket)
    }

    func testMQTT5URLSessionChallengeUsesSystemValidationByDefault() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT5(clientID: "tls-default-5", socket: socket)

        try assertSystemDefaultChallengeHandling(client: mqtt, socket: socket)
    }

    func testMQTT311URLSessionChallengeFallsBackToTrustClosure() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT(clientID: "tls-closure-311", socket: socket)
        let trust = try makeTrust()
        let challenge = makeChallenge()
        let completed = expectation(description: "challenge completed")
        var closureCalled = false
        mqtt.didReceiveTrust = { _, _, completion in
            closureCalled = true
            completion(false)
        }

        mqtt.socketUrlSession(
            socket,
            didReceiveTrust: trust,
            didReceiveChallenge: challenge
        ) { disposition, _ in
            XCTAssertEqual(disposition, .rejectProtectionSpace)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertTrue(closureCalled)
    }

    func testMQTT5URLSessionChallengeFallsBackToTrustClosure() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT5(clientID: "tls-closure-5", socket: socket)
        let trust = try makeTrust()
        let challenge = makeChallenge()
        let completed = expectation(description: "challenge completed")
        var closureCalled = false
        mqtt.didReceiveTrust = { _, _, completion in
            closureCalled = true
            completion(true)
        }

        mqtt.socketUrlSession(
            socket,
            didReceiveTrust: trust,
            didReceiveChallenge: challenge
        ) { disposition, credential in
            XCTAssertEqual(disposition, .useCredential)
            XCTAssertNotNil(credential)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertTrue(closureCalled)
    }

    func testMQTT311URLSessionDelegateHasExclusivePriorityAndCompletesOnce() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT(clientID: "tls-priority-311", socket: socket)
        let delegate = MQTT311DelegateStub()
        let completed = expectation(description: "challenge completed")
        var closureCalled = false
        var completionCount = 0
        mqtt.delegate = delegate
        mqtt.didReceiveTrust = { _, _, completion in
            closureCalled = true
            completion(true)
        }

        mqtt.socketUrlSession(
            socket,
            didReceiveTrust: try makeTrust(),
            didReceiveChallenge: makeChallenge()
        ) { disposition, _ in
            completionCount += 1
            XCTAssertEqual(disposition, .performDefaultHandling)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(delegate.urlSessionTrustCallCount, 1)
        XCTAssertEqual(delegate.legacyTrustCallCount, 0)
        XCTAssertFalse(closureCalled)
    }

    func testMQTT5URLSessionDelegateHasExclusivePriorityAndCompletesOnce() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT5(clientID: "tls-priority-5", socket: socket)
        let delegate = MQTT5DelegateStub()
        let completed = expectation(description: "challenge completed")
        var closureCalled = false
        var completionCount = 0
        mqtt.delegate = delegate
        mqtt.didReceiveTrust = { _, _, completion in
            closureCalled = true
            completion(true)
        }

        mqtt.socketUrlSession(
            socket,
            didReceiveTrust: try makeTrust(),
            didReceiveChallenge: makeChallenge()
        ) { disposition, _ in
            completionCount += 1
            XCTAssertEqual(disposition, .performDefaultHandling)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(delegate.urlSessionTrustCallCount, 1)
        XCTAssertEqual(delegate.legacyTrustCallCount, 0)
        XCTAssertFalse(closureCalled)
    }

    func testMQTT311ManualTrustDelegateHasExclusivePriority() throws {
        let socket = SocketStub()
        let mqtt = CocoaMQTT(clientID: "tls-manual-priority-311", socket: socket)
        let delegate = MQTT311DelegateStub()
        let completed = expectation(description: "trust decision completed")
        var closureCalled = false
        var decisions = [Bool]()
        mqtt.delegate = delegate
        mqtt.didReceiveTrust = { _, _, completion in
            closureCalled = true
            completion(true)
        }

        mqtt.socket(socket, didReceive: try makeTrust()) { decision in
            decisions.append(decision)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(decisions, [false])
        XCTAssertEqual(delegate.legacyTrustCallCount, 1)
        XCTAssertFalse(closureCalled)
    }

    private func assertSystemDefaultChallengeHandling(
        client: CocoaMQTTSocketDelegate,
        socket: CocoaMQTTSocketProtocol,
        line: UInt = #line
    ) throws {
        let completed = expectation(description: "challenge completed")

        client.socketUrlSession(
            socket,
            didReceiveTrust: try makeTrust(),
            didReceiveChallenge: makeChallenge()
        ) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling, line: line)
            XCTAssertNil(credential, line: line)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    private func makeTrust() throws -> SecTrust {
        #if IS_SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: type(of: self))
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "client-keycert", withExtension: "p12"))
        let data = try Data(contentsOf: url)
        let options = [kSecImportExportPassphrase as String: "MySecretPassword"] as CFDictionary
        var importedItems: CFArray?

        XCTAssertEqual(SecPKCS12Import(data as CFData, options, &importedItems), errSecSuccess)
        let items = try XCTUnwrap(importedItems as? [[String: Any]])
        let trust = try XCTUnwrap(items.first?[kSecImportItemTrust as String])
        return trust as! SecTrust
    }

    private func makeChallenge() -> URLAuthenticationChallenge {
        let protectionSpace = URLProtectionSpace(
            host: "broker.example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        return URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: ChallengeSenderStub()
        )
    }

    private func makeCredential() throws -> URLCredential {
        URLCredential(trust: try makeTrust())
    }
}
