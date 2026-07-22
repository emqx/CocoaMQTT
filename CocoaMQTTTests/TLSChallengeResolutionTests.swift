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

    func testManualTrustHandlerTakesPriorityOverBuiltInFallback() {
        var fallbackCalled = false
        var decisions = [Bool]()

        CocoaMQTTTrustHandling.resolveManualTrust(
            handler: { completion in
                completion(false)
                return true
            },
            fallback: { _ in
                fallbackCalled = true
                return true
            },
            completionHandler: { decisions.append($0) }
        )

        XCTAssertFalse(fallbackCalled)
        XCTAssertEqual(decisions, [false])
    }

    func testTLSSettingsUseConnectionHostByDefault() {
        let socket = CocoaMQTTSocket()

        let settings = socket.tlsSettings(forHost: "broker.example.com")

        XCTAssertEqual(settings[kCFStreamSSLPeerName as String] as? String, "broker.example.com")
    }

    func testTLSSettingsAllowServerNameAndRawSettingsOverrides() {
        let socket = CocoaMQTTSocket()
        socket.tlsServerName = "certificate.example.com"
        XCTAssertEqual(
            socket.tlsSettings(forHost: "192.0.2.1")[kCFStreamSSLPeerName as String] as? String,
            "certificate.example.com"
        )

        socket.sslSettings = [kCFStreamSSLPeerName as String: "raw.example.com" as NSString]
        XCTAssertEqual(
            socket.tlsSettings(forHost: "192.0.2.1")[kCFStreamSSLPeerName as String] as? String,
            "raw.example.com"
        )
    }

    func testCustomAnchorsEnableManualEvaluation() throws {
        let socket = CocoaMQTTSocket()
        socket.trustedServerCertificates = [try certificate(base64: testRootCertificate)]

        let settings = socket.tlsSettings(forHost: "broker.example.com")

        XCTAssertEqual(
            (settings["MGCDAsyncSocketManuallyEvaluateTrust"] as? NSNumber)?.boolValue,
            true
        )
    }

    func testServerCertificateLoadsDERAndPEM() throws {
        let der = try XCTUnwrap(Data(base64Encoded: testRootCertificate))
        XCTAssertNotNil(CocoaMQTTSocket.serverCertificate(from: der))

        let pem = """
        -----BEGIN CERTIFICATE-----
        \(testRootCertificate)
        -----END CERTIFICATE-----
        """
        XCTAssertNotNil(CocoaMQTTSocket.serverCertificate(from: Data(pem.utf8)))
        XCTAssertNil(CocoaMQTTSocket.serverCertificate(from: Data("invalid".utf8)))
    }

    func testCustomCAAcceptsMatchingServerAndRejectsWrongHostname() throws {
        let socket = CocoaMQTTSocket()
        socket.tlsServerName = "broker.example.com"
        socket.trustedServerCertificates = [try certificate(base64: testRootCertificate)]
        socket.usesSystemTrustStore = false

        let accepted = expectation(description: "matching hostname accepted")
        XCTAssertTrue(socket.evaluateServerTrust(try leafTrust()) { trusted in
            XCTAssertTrue(trusted)
            accepted.fulfill()
        })
        wait(for: [accepted], timeout: 2)

        socket.tlsServerName = "wrong.example.com"
        let rejected = expectation(description: "wrong hostname rejected")
        XCTAssertTrue(socket.evaluateServerTrust(try leafTrust()) { trusted in
            XCTAssertFalse(trusted)
            rejected.fulfill()
        })
        wait(for: [rejected], timeout: 2)
    }

    func testCustomCAUsesRawPeerNameOverride() throws {
        let socket = CocoaMQTTSocket()
        socket.tlsServerName = "wrong.example.com"
        socket.sslSettings = [
            kCFStreamSSLPeerName as String: "broker.example.com" as NSString
        ]
        socket.trustedServerCertificates = [try certificate(base64: testRootCertificate)]
        socket.usesSystemTrustStore = false
        let accepted = expectation(description: "raw peer name accepted")

        XCTAssertTrue(socket.evaluateServerTrust(try leafTrust()) { trusted in
            XCTAssertTrue(trusted)
            accepted.fulfill()
        })
        wait(for: [accepted], timeout: 2)
    }

    func testMQTT311UsesBuiltInCustomCAFallback() throws {
        let socket = CocoaMQTTSocket()
        let mqtt = CocoaMQTT(clientID: "custom-ca-311", socket: socket)
        try configureCustomCA(on: mqtt)
        let completed = expectation(description: "MQTT 3.1.1 trust accepted")

        mqtt.socket(socket, didReceive: try leafTrust()) { trusted in
            XCTAssertTrue(trusted)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
    }

    func testMQTT5UsesBuiltInCustomCAFallback() throws {
        let socket = CocoaMQTTSocket()
        let mqtt = CocoaMQTT5(clientID: "custom-ca-5", socket: socket)
        try configureCustomCA(on: mqtt)
        let completed = expectation(description: "MQTT 5 trust accepted")

        mqtt.socket(socket, didReceive: try leafTrust()) { trusted in
            XCTAssertTrue(trusted)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
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

    func testMQTT311URLSessionChallengeCancelsIfClientIsReleasedBeforeCallback() throws {
        let socket = SocketStub()
        let trust = try makeTrust()
        let challenge = makeChallenge()
        let callbackQueue = DispatchQueue(label: "tests.tls-release-311")
        let completed = expectation(description: "challenge cancelled")
        callbackQueue.suspend()
        var mqtt: CocoaMQTT? = CocoaMQTT(clientID: "tls-release-311", socket: socket)
        mqtt?.delegateQueue = callbackQueue

        mqtt?.socketUrlSession(
            socket,
            didReceiveTrust: trust,
            didReceiveChallenge: challenge
        ) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completed.fulfill()
        }

        weak var releasedClient = mqtt
        mqtt = nil
        XCTAssertNil(releasedClient)
        callbackQueue.resume()
        wait(for: [completed], timeout: 1)
    }

    func testMQTT5URLSessionChallengeCancelsIfClientIsReleasedBeforeCallback() throws {
        let socket = SocketStub()
        let trust = try makeTrust()
        let challenge = makeChallenge()
        let callbackQueue = DispatchQueue(label: "tests.tls-release-5")
        let completed = expectation(description: "challenge cancelled")
        callbackQueue.suspend()
        var mqtt: CocoaMQTT5? = CocoaMQTT5(clientID: "tls-release-5", socket: socket)
        mqtt?.delegateQueue = callbackQueue

        mqtt?.socketUrlSession(
            socket,
            didReceiveTrust: trust,
            didReceiveChallenge: challenge
        ) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completed.fulfill()
        }

        weak var releasedClient = mqtt
        mqtt = nil
        XCTAssertNil(releasedClient)
        callbackQueue.resume()
        wait(for: [completed], timeout: 1)
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

    private func certificate(base64: String) throws -> SecCertificate {
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        return try XCTUnwrap(CocoaMQTTSocket.serverCertificate(from: data))
    }

    private func leafTrust() throws -> SecTrust {
        let leaf = try certificate(base64: testLeafCertificate)
        let policy = SecPolicyCreateSSL(true, "broker.example.com" as CFString)
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(leaf, policy, &trust), errSecSuccess)
        let unwrappedTrust = try XCTUnwrap(trust)
        let verificationDate = Date(timeIntervalSince1970: 1_784_764_800)
        XCTAssertEqual(SecTrustSetVerifyDate(unwrappedTrust, verificationDate as CFDate), errSecSuccess)
        return unwrappedTrust
    }

    private func configureCustomCA(on mqtt: CocoaMQTT) throws {
        mqtt.tlsServerName = "broker.example.com"
        mqtt.trustedServerCertificates = [try certificate(base64: testRootCertificate)]
        mqtt.usesSystemTrustStore = false
    }

    private func configureCustomCA(on mqtt: CocoaMQTT5) throws {
        mqtt.tlsServerName = "broker.example.com"
        mqtt.trustedServerCertificates = [try certificate(base64: testRootCertificate)]
        mqtt.usesSystemTrustStore = false
    }

    private let testRootCertificate = "MIIDGTCCAgGgAwIBAgIUDyLKePsFbiSs+UbrI28jTUZjkaowDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRQ29jb2FNUVRUIFRlc3QgQ0EwHhcNMjYwNzIyMTIzOTI5WhcNMzYwNzE5MTIzOTI5WjAcMRowGAYDVQQDDBFDb2NvYU1RVFQgVGVzdCBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAI6FS7w/lPHRmKHshtuBptgkyufKRAGyEv+nyeOfX/J7iZ42NtaMk5AC5UVWozBhX2zpx4QzfNy/KeILSUhJmAtK5F64z/MktJTjTep9eng/zSUvP/HtzP4cY1ShMEWZlgIhuq/+8bzcw2Et0DDaIUuhZZWUirnAMdsuiUcFbG6LXSjPg3yiCym8z/Hj8FVi/Dv/3N75dD1HGfJfT9xRzYNZTCBySj/LtkQG3pO7ea7UgaNHAY4rvYaIESdaoG8rNfxrnpwO56iauHWxW+WOKoeSaLzYexl62/VrBJi2O3297e2bSJ/f+cjz6lhBmZTLlzPuMqO6plHOZomfQym33FkCAwEAAaNTMFEwHQYDVR0OBBYEFNK/zQbngegfsls/g4m05iuAQFvnMB8GA1UdIwQYMBaAFNK/zQbngegfsls/g4m05iuAQFvnMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBACL9lfvv3teAoQUOpMenpKy6GAx6l7KM7Pn6TxIP9SJvd0ZXcwY/HqzuuHUtvG9+ien7sDx4XYBVuSgpLXVg853oHCDR6X2R5sQcFBOAls5sqeaTR7GsyVhljhvkqdBUaBpE7n6mWm2Njb9YvNZqxjMqjz0e/bv7izVFHfLAz9mgfCG2whm7+iT61lqJJe9Z6/fSKMMxmDPahFnICAodcRsabAgqJ6al5JuT6vkrcPYGDio/mj3j200v1sKPs7H05HjH3th0/7WeupPiGGjZK6MuM1ZNo8hxtbseIYDtnRFsL7z+9EIxVBc6Rh1RECo0LVqbKPN3obvMDYYGVgDSyJM="

    private let testLeafCertificate = "MIIDPTCCAiWgAwIBAgIUJeIajR3eWzfdKZ3nP0bqRBIvDj8wDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRQ29jb2FNUVRUIFRlc3QgQ0EwHhcNMjYwNzIyMTI0MzIyWhcNMjcwNzIyMTI0MzIyWjAdMRswGQYDVQQDDBJicm9rZXIuZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDFvlsaaGQrskF1IUJsNkWo7OgVAbcqSmY2MhtN8l0OfHV+CSNdwDBJHX/HWL1Zpvh/L3hylSDIKat6PiaWtUQr6C3UREuQJgp+vOg/+CCTer7MB3qjT/0BLW2Hz2q6fFpULrEFswPMcYinALV3TQslbSvqq6oUPhisH1wFR/6E9mcdBlfFwfF4OjNjAqOt2Uv1TNuBNtvyYsTO8GU6+1bqVTnF8gMVrvgVnpf3LBWTr9XJJGkXfhk1cvJBOW2VsNK4uM7pJblFXYCgJPNZZXzjhIk1ZtweRsld2l85rEyruQKndDFhApNxLi3MxDA2TpWiFZI50nsjxWUWqXBoN+J9AgMBAAGjdjB0MB0GA1UdEQQWMBSCEmJyb2tlci5leGFtcGxlLmNvbTATBgNVHSUEDDAKBggrBgEFBQcDATAdBgNVHQ4EFgQU1n3Uvp2QkGPQ6u0oyJ6CrYjBO78wHwYDVR0jBBgwFoAU0r/NBueB6B+yWz+DibTmK4BAW+cwDQYJKoZIhvcNAQELBQADggEBAEsXExWdIuHHqZNMK/D+PgjfgTEpJAUmFWyGMUFmRE+iKOJdcdZ0iofkvHVtonBg1DZXbkYgLx48gIqPbFUryE74N0KegKB4NieQkkBmppML4GmeaFXB0VByAFsF2x9/3iKCuQo+xvJ1VaC40d9BshOYh7l28qJH+FFU1IvDEVFtnbd2qm4R3HJq2v/iuE5ckssvXOlHTtqQLIjfL+iM7A3lIKiFxw3sPsAv6pgx1VvnkHXMMMOgbY9eC7CEe1mZRD3LmUbPWpHRTJSUvDbCRU7yLm6mxfdmRb2VDjcg7Y/zNyUW75hBKCOhv1ONu6UUk6tVqT2CndcL1yLK24ONUR0="
}
