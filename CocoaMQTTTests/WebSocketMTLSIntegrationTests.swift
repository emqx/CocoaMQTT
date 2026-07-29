#if os(macOS) && IS_SWIFT_PACKAGE
import Security
import XCTest
@testable import CocoaMQTT
@testable import CocoaMQTTWebSocket

@available(macOS 10.15, *)
final class WebSocketMTLSIntegrationTests: XCTestCase {

    private static let fixture = Result { try TLSLoopbackCertificateFixture() }

    private final class ChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
        func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
        func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
    }

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

    func testWebSocketRejectsServerSignedByUntrustedCA() throws {
        let fixture = try Self.fixture.get()
        let broker = try TLSWebSocketMQTTLoopbackBroker(
            identity: fixture.serverIdentity,
            trustedClientRootCertificate: fixture.rootCertificate
        )
        let port = try start(broker)
        let disconnected = expectation(description: "untrusted WSS server rejected")
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT(
            clientID: "wss-untrusted-server",
            host: "127.0.0.1",
            port: port,
            socket: socket
        )
        configure(
            mqtt,
            identity: try makeClientIdentity(fixture),
            trustedRoot: fixture.untrustedRootCertificate
        )
        mqtt.didDisconnect = { _, _ in disconnected.fulfill() }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [disconnected], timeout: 5)
        XCTAssertTrue(broker.receivedProtocolLevels.isEmpty)
    }

    func testFoundationConnectionUsesIdentityForMatchingEndpoint() throws {
        let fixture = try Self.fixture.get()
        let identity = try makeClientIdentity(fixture)
        let connection = try makeFoundationConnection()
        connection.clientIdentity = identity
        addTeardownBlock { connection.disconnect() }

        let completed = expectation(description: "client identity supplied")
        performClientCertificateChallenge(on: connection, host: "broker.example.com") { disposition, credential in
            XCTAssertEqual(disposition, .useCredential)
            XCTAssertTrue(credential?.identity === identity.identity)
            XCTAssertEqual(credential?.certificates.count, 1)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testFoundationConnectionCancelsChallengeWithoutConfiguredIdentity() throws {
        let connection = try makeFoundationConnection()
        addTeardownBlock { connection.disconnect() }

        let completed = expectation(description: "missing identity rejected")
        performClientCertificateChallenge(on: connection, host: "broker.example.com") { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testFoundationConnectionDoesNotSendIdentityToAnotherHost() throws {
        let fixture = try Self.fixture.get()
        let connection = try makeFoundationConnection()
        connection.clientIdentity = try makeClientIdentity(fixture)
        addTeardownBlock { connection.disconnect() }

        let completed = expectation(description: "cross-host identity rejected")
        performClientCertificateChallenge(on: connection, host: "redirect.example.com") { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
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

    private func makeFoundationConnection() throws -> CocoaMQTTWebSocket.FoundationConnection {
        CocoaMQTTWebSocket.FoundationConnection(
            url: try XCTUnwrap(URL(string: "wss://broker.example.com:443/mqtt")),
            config: .ephemeral
        )
    }

    private func performClientCertificateChallenge(
        on connection: CocoaMQTTWebSocket.FoundationConnection,
        host: String,
        completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = URLProtectionSpace(
            host: host,
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodClientCertificate
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: ChallengeSenderStub()
        )
        connection.urlSession(
            connection.session!,
            task: connection.task!,
            didReceive: challenge,
            completionHandler: completion
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
        mqtt.tlsServerName = "broker.example.com"
        mqtt.trustedServerCertificates = [trustedRoot]
        mqtt.usesSystemTrustStore = false
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
        mqtt.tlsServerName = "broker.example.com"
        mqtt.trustedServerCertificates = [trustedRoot]
        mqtt.usesSystemTrustStore = false
    }
}
#endif
