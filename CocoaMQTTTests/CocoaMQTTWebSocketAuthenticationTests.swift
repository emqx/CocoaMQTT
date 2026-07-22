import Foundation
import XCTest
@testable import CocoaMQTT
#if IS_SWIFT_PACKAGE
@testable import CocoaMQTTWebSocket
#endif

final class CocoaMQTTWebSocketAuthenticationTests: XCTestCase {
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
