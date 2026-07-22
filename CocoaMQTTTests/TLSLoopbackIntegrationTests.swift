#if os(macOS)
import Security
import XCTest
@testable import CocoaMQTT

final class TLSLoopbackIntegrationTests: XCTestCase {

    private static let fixture = Result { try TLSLoopbackCertificateFixture() }

    override static func tearDown() {
        try? fixture.get().removeTemporaryFiles()
        super.tearDown()
    }

    func testMQTT311ConnectsUsingBuiltInPrivateCATrust() throws {
        let fixture = try Self.fixture.get()
        let broker = try TLSMQTTLoopbackBroker(identity: fixture.serverIdentity)
        let port = try start(broker)
        let connected = expectation(description: "MQTT 3.1.1 connected")
        let mqtt = CocoaMQTT(
            clientID: "tls-loopback-311",
            host: "127.0.0.1",
            port: port
        )
        configurePrivateCATrust(
            on: mqtt,
            rootCertificate: fixture.rootCertificate,
            usesSystemTrustStore: false
        )
        mqtt.didConnectAck = { client, ack in
            XCTAssertEqual(ack, .accept)
            connected.fulfill()
            client.disconnect()
        }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [connected], timeout: 3)

        XCTAssertEqual(broker.receivedProtocolLevels, [4])
    }

    func testMQTT5ConnectsUsingConnectionHostAndBuiltInPrivateCATrust() throws {
        let fixture = try Self.fixture.get()
        let broker = try TLSMQTTLoopbackBroker(identity: fixture.serverIdentity)
        let port = try start(broker)
        let connected = expectation(description: "MQTT 5 connected")
        let mqtt = CocoaMQTT5(
            clientID: "tls-loopback-5",
            host: "127.0.0.1",
            port: port
        )
        configurePrivateCATrust(on: mqtt, rootCertificate: fixture.rootCertificate)
        mqtt.didConnectAck = { client, reasonCode, _ in
            XCTAssertEqual(reasonCode, .success)
            connected.fulfill()
            client.disconnect()
        }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [connected], timeout: 3)

        XCTAssertEqual(broker.receivedProtocolLevels, [5])
    }

    func testWrongHostnameIsRejectedBeforeMQTTConnect() throws {
        let fixture = try Self.fixture.get()
        let unexpectedConnect = expectation(description: "MQTT CONNECT not received")
        unexpectedConnect.isInverted = true
        let broker = try TLSMQTTLoopbackBroker(identity: fixture.serverIdentity) { _ in
            unexpectedConnect.fulfill()
        }
        let port = try start(broker)
        let disconnected = expectation(description: "TLS connection rejected")
        let mqtt = CocoaMQTT(
            clientID: "tls-loopback-wrong-host",
            host: "127.0.0.1",
            port: port
        )
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.logLevel = .off
        mqtt.tlsServerName = "wrong.example.com"
        mqtt.trustedServerCertificates = [fixture.rootCertificate]
        mqtt.usesSystemTrustStore = false
        mqtt.didDisconnect = { _, _ in disconnected.fulfill() }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [disconnected], timeout: 3)
        wait(for: [unexpectedConnect], timeout: 0.2)

        XCTAssertTrue(broker.receivedProtocolLevels.isEmpty)
    }

    func testWrongCAIsRejectedBeforeMQTTConnect() throws {
        let fixture = try Self.fixture.get()
        let unexpectedConnect = expectation(description: "MQTT CONNECT not received")
        unexpectedConnect.isInverted = true
        let broker = try TLSMQTTLoopbackBroker(identity: fixture.serverIdentity) { _ in
            unexpectedConnect.fulfill()
        }
        let port = try start(broker)
        let disconnected = expectation(description: "untrusted TLS connection rejected")
        let mqtt = CocoaMQTT(
            clientID: "tls-loopback-wrong-ca",
            host: "127.0.0.1",
            port: port
        )
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.logLevel = .off
        mqtt.tlsServerName = "broker.example.com"
        mqtt.trustedServerCertificates = [fixture.untrustedRootCertificate]
        mqtt.usesSystemTrustStore = false
        mqtt.didDisconnect = { _, _ in disconnected.fulfill() }

        XCTAssertTrue(mqtt.connect(timeout: 2))
        wait(for: [disconnected], timeout: 3)
        wait(for: [unexpectedConnect], timeout: 0.2)

        XCTAssertTrue(broker.receivedProtocolLevels.isEmpty)
    }

    private func start(_ broker: TLSMQTTLoopbackBroker) throws -> UInt16 {
        let ready = expectation(description: "TLS broker ready")
        broker.start { ready.fulfill() }
        addTeardownBlock { broker.stop() }
        wait(for: [ready], timeout: 2)
        return try XCTUnwrap(broker.port)
    }

    private func configurePrivateCATrust(
        on mqtt: CocoaMQTT,
        rootCertificate: SecCertificate,
        usesSystemTrustStore: Bool
    ) {
        // No trust callback: success must come from CocoaMQTT's built-in policy.
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.logLevel = .off
        mqtt.tlsServerName = "broker.example.com"
        mqtt.trustedServerCertificates = [rootCertificate]
        mqtt.usesSystemTrustStore = usesSystemTrustStore
    }

    private func configurePrivateCATrust(
        on mqtt: CocoaMQTT5,
        rootCertificate: SecCertificate
    ) {
        // Keep the default system trust store enabled to cover both trust modes.
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.logLevel = .off
        mqtt.trustedServerCertificates = [rootCertificate]
    }
}
#endif
