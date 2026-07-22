import Foundation
import Security
import XCTest
@testable import CocoaMQTT
#if IS_SWIFT_PACKAGE
@testable import CocoaMQTTWebSocket
#endif

final class CocoaMQTTWebSocketAuthenticationTests: XCTestCase {
    private final class ChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
        func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
        func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
    }

    private final class SocketDelegateSpy: CocoaMQTTSocketDelegate {
        private(set) var urlSessionTrustCallCount = 0

        func socketConnected(_ socket: CocoaMQTTSocketProtocol) {}
        func socket(_ socket: CocoaMQTTSocketProtocol, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {}
        func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {}
        func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {}
        func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError err: Error?) {}

        func socketUrlSession(
            _ socket: CocoaMQTTSocketProtocol,
            didReceiveTrust trust: SecTrust,
            didReceiveChallenge challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            urlSessionTrustCallCount += 1
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private final class ConnectionSpy: NSObject, CocoaMQTTWebSocketConnection {
        weak var delegate: CocoaMQTTWebSocketConnectionDelegate?
        var queue = DispatchQueue(label: "tests.websocket-auth.connection")
        private(set) var connectCallCount = 0

        func connect() {
            connectCallCount += 1
        }

        func disconnect() {}

        func write(data: Data, handler: @escaping (Error?) -> Void) {
            handler(nil)
        }
    }

    private final class BuilderSpy: CocoaMQTTWebSocketConnectionBuilder {
        let connection = ConnectionSpy()
        private(set) var url: URL?
        private(set) var headers: [String: String]?

        func buildConnection(
            forURL url: URL,
            withHeaders headers: [String: String]
        ) throws -> CocoaMQTTWebSocketConnection {
            self.url = url
            self.headers = headers
            return connection
        }
    }

    func testSecureConnectForwardsCustomAuthorizerHeaders() throws {
        let builder = BuilderSpy()
        let websocket = CocoaMQTTWebSocket(uri: "/mqtt", builder: builder)
        let headers = [
            "x-amz-customauthorizer-name": "authorizer",
            "x-amz-customauthorizer-signature": "signature",
            "custom-token": "token",
            "Sec-WebSocket-Protocol": "mqtt"
        ]
        websocket.enableSSL = true
        websocket.headers = headers

        try websocket.connect(toHost: "example-ats.iot.example.com", onPort: 443)

        XCTAssertEqual(builder.url, URL(string: "wss://example-ats.iot.example.com:443/mqtt"))
        XCTAssertEqual(builder.headers, headers)
        XCTAssertEqual(builder.connection.connectCallCount, 1)
    }

    func testMissingSocketDelegateQueueUsesSystemTrustHandling() throws {
        let builder = BuilderSpy()
        let websocket = CocoaMQTTWebSocket(uri: "/mqtt", builder: builder)
        let delegate = SocketDelegateSpy()
        let completed = expectation(description: "challenge completed")
        websocket.enableSSL = true
        websocket.setDelegate(delegate, delegateQueue: nil)
        try websocket.connect(toHost: "broker.example.com", onPort: 443)

        websocket.urlSessionConnection(
            builder.connection,
            didReceiveTrust: try makeTrust(),
            didReceiveChallenge: makeChallenge()
        ) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(delegate.urlSessionTrustCallCount, 0)
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
}

final class AWSIoTIntegrationTests: XCTestCase {
    private final class Delegate: CocoaMQTTDelegate {
        var connected: (() -> Void)?
        var disconnected: (() -> Void)?

        func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
            if ack == .accept {
                connected?()
            }
        }

        func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {}
        func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
        func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
        func mqttDidPing(_ mqtt: CocoaMQTT) {}
        func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

        func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
            disconnected?()
        }

        func mqttUrlSession(
            _ mqtt: CocoaMQTT,
            didReceiveTrust trust: SecTrust,
            didReceiveChallenge challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func testCustomAuthorizerConnection() throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let host = environment["COCOAMQTT_AWS_IOT_HOST"], !host.isEmpty,
            let authorizer = environment["COCOAMQTT_AWS_AUTHORIZER_NAME"], !authorizer.isEmpty,
            let signature = environment["COCOAMQTT_AWS_AUTHORIZER_SIGNATURE"], !signature.isEmpty,
            let tokenKeyName = environment["COCOAMQTT_AWS_TOKEN_KEY_NAME"], !tokenKeyName.isEmpty,
            let token = environment["COCOAMQTT_AWS_AUTHORIZER_TOKEN"], !token.isEmpty
        else {
            throw XCTSkip("Set the COCOAMQTT_AWS_* variables to run the AWS IoT integration test")
        }

        let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
        websocket.enableSSL = true
        websocket.headers = [
            "x-amz-customauthorizer-name": authorizer,
            "x-amz-customauthorizer-signature": signature,
            tokenKeyName: token,
            "Sec-WebSocket-Protocol": "mqtt"
        ]

        let mqtt = CocoaMQTT(
            clientID: "CocoaMQTT-AWS-integration-\(UUID().uuidString)",
            host: host,
            port: 443,
            socket: websocket
        )
        let delegate = Delegate()
        let connected = expectation(description: "AWS IoT accepted the connection")
        let disconnected = expectation(description: "AWS IoT connection closed")
        delegate.connected = { connected.fulfill() }
        delegate.disconnected = { disconnected.fulfill() }
        mqtt.delegate = delegate
        mqtt.delegateQueue = DispatchQueue(label: "tests.aws-iot-integration.callbacks")
        mqtt.autoReconnect = false
        mqtt.logLevel = .error

        if !mqtt.connect() {
            XCTFail("Failed to start the AWS IoT connection")
            return
        }
        wait(for: [connected], timeout: 30)
        XCTAssertEqual(mqtt.connState, .connected)

        mqtt.disconnect()
        wait(for: [disconnected], timeout: 10)
    }
}
