#if os(macOS) && IS_SWIFT_PACKAGE
import Security
import XCTest
@testable import CocoaMQTT
@testable import CocoaMQTTWebSocket

@available(macOS 10.15, *)
final class WebSocketMTLSIntegrationTests: XCTestCase {

    private static let fixture = Result { try TLSLoopbackCertificateFixture() }

    override static func tearDown() {
        try? fixture.get().removeTemporaryFiles()
        super.tearDown()
    }

    func testMQTT311ConnectsOverWebSocketWithClientIdentity() throws {
        let fixture = try Self.fixture.get()
        let broker = try TLSWebSocketMQTTLoopbackBroker(
            identity: fixture.serverIdentity,
            trustedClientRootCertificate: fixture.rootCertificate
        )
        let port = try start(broker)
        let connected = expectation(description: "MQTT 3.1.1 connected over mTLS WebSocket")
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT(
            clientID: "wss-mtls-311",
            host: "127.0.0.1",
            port: port,
            socket: socket
        )
        configure(
            mqtt,
            identity: try makeClientIdentity(fixture),
            trustedRoot: fixture.rootCertificate
        )
        mqtt.didConnectAck = { client, ack in
            XCTAssertEqual(ack, .accept)
            connected.fulfill()
            client.disconnect()
        }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [connected], timeout: 5)
        XCTAssertEqual(broker.receivedProtocolLevels, [4])
    }

    func testMQTT5ConnectsOverWebSocketWithClientIdentity() throws {
        let fixture = try Self.fixture.get()
        let broker = try TLSWebSocketMQTTLoopbackBroker(
            identity: fixture.serverIdentity,
            trustedClientRootCertificate: fixture.rootCertificate
        )
        let port = try start(broker)
        let connected = expectation(description: "MQTT 5 connected over mTLS WebSocket")
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT5(
            clientID: "wss-mtls-5",
            host: "127.0.0.1",
            port: port,
            socket: socket
        )
        configure(
            mqtt,
            identity: try makeClientIdentity(fixture),
            trustedRoot: fixture.rootCertificate
        )
        mqtt.didConnectAck = { client, reasonCode, _ in
            XCTAssertEqual(reasonCode, .success)
            connected.fulfill()
            client.disconnect()
        }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [connected], timeout: 5)
        XCTAssertEqual(broker.receivedProtocolLevels, [5])
    }

    func testWebSocketBrokerRequiringClientCertificateRejectsMissingIdentity() throws {
        let fixture = try Self.fixture.get()
        let broker = try TLSWebSocketMQTTLoopbackBroker(
            identity: fixture.serverIdentity,
            trustedClientRootCertificate: fixture.rootCertificate
        )
        let port = try start(broker)
        let disconnected = expectation(description: "WebSocket mTLS connection rejected")
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT(
            clientID: "wss-mtls-missing",
            host: "127.0.0.1",
            port: port,
            socket: socket
        )
        configure(mqtt, identity: nil, trustedRoot: fixture.rootCertificate)
        mqtt.didDisconnect = { _, _ in disconnected.fulfill() }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [disconnected], timeout: 5)
        XCTAssertTrue(broker.receivedProtocolLevels.isEmpty)
    }

    private func start(_ broker: TLSWebSocketMQTTLoopbackBroker) throws -> UInt16 {
        let ready = expectation(description: "mTLS WebSocket broker ready")
        broker.start { ready.fulfill() }
        addTeardownBlock { broker.stop() }
        wait(for: [ready], timeout: 2)
        return try XCTUnwrap(broker.port)
    }

    private func makeClientIdentity(
        _ fixture: TLSLoopbackCertificateFixture
    ) throws -> CocoaMQTTClientIdentity {
        try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM,
            intermediateCertificateData: [fixture.intermediateCertificatePEM]
        )
    }

    private func configure(
        _ mqtt: CocoaMQTT,
        identity: CocoaMQTTClientIdentity?,
        trustedRoot: SecCertificate
    ) {
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.logLevel = .off
        mqtt.clientIdentity = identity
        mqtt.didReceiveTrust = { _, trust, completion in
            completion(Self.evaluate(trust, trustedRoot: trustedRoot))
        }
    }

    private func configure(
        _ mqtt: CocoaMQTT5,
        identity: CocoaMQTTClientIdentity,
        trustedRoot: SecCertificate
    ) {
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.logLevel = .off
        mqtt.clientIdentity = identity
        mqtt.didReceiveTrust = { _, trust, completion in
            completion(Self.evaluate(trust, trustedRoot: trustedRoot))
        }
    }

    private static func evaluate(
        _ trust: SecTrust,
        trustedRoot: SecCertificate
    ) -> Bool {
        guard SecTrustSetPolicies(
            trust,
            SecPolicyCreateSSL(true, "127.0.0.1" as CFString)
        ) == errSecSuccess,
        SecTrustSetAnchorCertificates(
            trust,
            [trustedRoot] as CFArray
        ) == errSecSuccess,
        SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
            return false
        }
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }
}
#endif
