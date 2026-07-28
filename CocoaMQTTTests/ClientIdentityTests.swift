#if os(macOS)
import Security
import XCTest
@testable import CocoaMQTT
#if IS_SWIFT_PACKAGE
@testable import CocoaMQTTWebSocket
#endif

final class ClientIdentityTests: XCTestCase {

    private static let fixture = Result { try TLSLoopbackCertificateFixture() }

    override static func tearDown() {
        try? fixture.get().removeTemporaryFiles()
        super.tearDown()
    }

    func testCreatesIdentityFromRSAPKCS1PEM() throws {
        let fixture = try Self.fixture.get()

        let identity = try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM,
            intermediateCertificateData: [fixture.intermediateCertificatePEM]
        )

        XCTAssertEqual(identity.intermediateCertificates.count, 1)
    }

    func testCreatesIdentityFromRSAPKCS8PEMWithCRLF() throws {
        let fixture = try Self.fixture.get()
        let key = try XCTUnwrap(String(data: fixture.clientPrivateKeyPKCS8PEM, encoding: .utf8))
            .replacingOccurrences(of: "\n", with: "\r\n")

        XCTAssertNoThrow(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: Data(key.utf8)
        ))
    }

    func testCreatesIdentityFromCertificateChainPEMBundle() throws {
        let fixture = try Self.fixture.get()
        let certificateChain = fixture.clientCertificatePEM
            + fixture.intermediateCertificatePEM

        let identity = try CocoaMQTTClientIdentity(
            certificateData: certificateChain,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM
        )

        XCTAssertEqual(identity.intermediateCertificates.count, 1)
    }

    func testFlattensIntermediateCertificatePEMBundles() throws {
        let fixture = try Self.fixture.get()
        let intermediateBundle = fixture.intermediateCertificatePEM
            + fixture.rootCertificatePEM

        let identity = try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM,
            intermediateCertificateData: [intermediateBundle]
        )

        XCTAssertEqual(identity.intermediateCertificates.count, 2)
    }

    func testRemovesDuplicateAndRepeatedLeafCertificatesFromChain() throws {
        let fixture = try Self.fixture.get()
        let certificateChain = fixture.clientCertificatePEM
            + fixture.intermediateCertificatePEM

        let identity = try CocoaMQTTClientIdentity(
            certificateData: certificateChain,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM,
            intermediateCertificateData: [
                fixture.clientCertificatePEM,
                fixture.intermediateCertificatePEM
            ]
        )

        XCTAssertEqual(identity.intermediateCertificates.count, 1)
        XCTAssertTrue(CFEqual(
            identity.intermediateCertificates[0],
            try XCTUnwrap(CocoaMQTTSocket.serverCertificate(
                from: fixture.intermediateCertificatePEM
            ))
        ))
    }

    func testRejectsMalformedCertificatePEMBundle() throws {
        let fixture = try Self.fixture.get()
        let malformedBundle = fixture.clientCertificatePEM
            + Data("-----BEGIN CERTIFICATE-----\ninvalid\n".utf8)

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: malformedBundle,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM
        )) { error in
            XCTAssertEqual(error as? CocoaMQTTClientIdentityError, .invalidCertificate)
        }
    }

    func testCreatesIdentityFromDERCertificateAndPrivateKeys() throws {
        let fixture = try Self.fixture.get()
        let certificate = try XCTUnwrap(
            CocoaMQTTSocket.serverCertificate(from: fixture.clientCertificatePEM)
        )
        let certificateDER = SecCertificateCopyData(certificate) as Data

        XCTAssertNoThrow(try CocoaMQTTClientIdentity(
            certificateData: certificateDER,
            privateKeyData: try pemDER(
                fixture.clientPrivateKeyPKCS1PEM,
                label: "RSA PRIVATE KEY"
            )
        ))
        XCTAssertNoThrow(try CocoaMQTTClientIdentity(
            certificateData: certificateDER,
            privateKeyData: try pemDER(
                fixture.clientPrivateKeyPKCS8PEM,
                label: "PRIVATE KEY"
            )
        ))
    }

    func testRejectsCertificateAndPrivateKeyMismatch() throws {
        let fixture = try Self.fixture.get()

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.wrongPrivateKeyPEM
        )) { error in
            XCTAssertEqual(
                error as? CocoaMQTTClientIdentityError,
                .certificatePrivateKeyMismatch
            )
        }
    }

    func testRejectsEncryptedAndECPrivateKeysExplicitly() throws {
        let fixture = try Self.fixture.get()

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: Data("""
            -----BEGIN ENCRYPTED PRIVATE KEY-----
            AA==
            -----END ENCRYPTED PRIVATE KEY-----
            """.utf8)
        )) { error in
            XCTAssertEqual(
                error as? CocoaMQTTClientIdentityError,
                .encryptedPrivateKeyUnsupported
            )
        }

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: Data("""
            -----BEGIN EC PRIVATE KEY-----
            AA==
            -----END EC PRIVATE KEY-----
            """.utf8)
        )) { error in
            XCTAssertEqual(
                error as? CocoaMQTTClientIdentityError,
                .unsupportedPrivateKeyAlgorithm
            )
        }

        let ecPKCS8DER = Data([
            0x30, 0x12,
            0x02, 0x01, 0x00,
            0x30, 0x09,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x04, 0x02, 0x30, 0x00
        ])
        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: ecPKCS8DER
        )) { error in
            XCTAssertEqual(
                error as? CocoaMQTTClientIdentityError,
                .unsupportedPrivateKeyAlgorithm
            )
        }
    }

    func testRejectsMalformedPKCS8AndDuplicatePEMBlocks() throws {
        let fixture = try Self.fixture.get()
        let duplicateKey = fixture.clientPrivateKeyPKCS1PEM
            + fixture.clientPrivateKeyPKCS1PEM

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: duplicateKey
        )) { error in
            XCTAssertEqual(error as? CocoaMQTTClientIdentityError, .invalidPrivateKey)
        }

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: Data([0x30, 0x82, 0xff, 0xff])
        )) { error in
            XCTAssertEqual(error as? CocoaMQTTClientIdentityError, .invalidPrivateKey)
        }
    }

    func testReportsInvalidIntermediateCertificateIndex() throws {
        let fixture = try Self.fixture.get()

        XCTAssertThrowsError(try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM,
            intermediateCertificateData: [
                fixture.intermediateCertificatePEM,
                Data("not a certificate".utf8)
            ]
        )) { error in
            XCTAssertEqual(
                error as? CocoaMQTTClientIdentityError,
                .invalidIntermediateCertificate(index: 1)
            )
        }
    }

    func testClientIdentityPopulatesTLSSettingsWithoutOverridingRawSettings() throws {
        let fixture = try Self.fixture.get()
        let identity = try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM,
            intermediateCertificateData: [fixture.intermediateCertificatePEM]
        )
        let socket = CocoaMQTTSocket()
        socket.clientIdentity = identity
        let key = kCFStreamSSLCertificates as String

        let generated = try XCTUnwrap(socket.tlsSettings(forHost: "broker.example.com")[key] as? [Any])
        XCTAssertEqual(generated.count, 2)
        XCTAssertTrue(CFEqual(generated[0] as CFTypeRef, identity.identity))
        XCTAssertTrue(CFEqual(generated[1] as CFTypeRef, identity.intermediateCertificates[0]))

        let rawValue = NSArray(object: "raw")
        socket.sslSettings = [key: rawValue]
        XCTAssertTrue(socket.tlsSettings(forHost: "broker.example.com")[key] === rawValue)
    }

    func testMQTTClientsProxyIdentityForBuiltInSocket() throws {
        let fixture = try Self.fixture.get()
        let identity = try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM
        )
        let mqtt = CocoaMQTT(clientID: "identity-311", host: "localhost")
        let mqtt5 = CocoaMQTT5(clientID: "identity-5", host: "localhost")

        mqtt.clientIdentity = identity
        mqtt5.clientIdentity = identity

        XCTAssertTrue(mqtt.clientIdentity === identity)
        XCTAssertTrue(mqtt5.clientIdentity === identity)
    }

#if IS_SWIFT_PACKAGE
    func testMQTTClientsDoNotApplyIdentityToWebSocketTransport() throws {
        let fixture = try Self.fixture.get()
        let identity = try CocoaMQTTClientIdentity(
            certificateData: fixture.clientCertificatePEM,
            privateKeyData: fixture.clientPrivateKeyPKCS1PEM
        )
        let mqtt = CocoaMQTT(
            clientID: "identity-websocket-311",
            socket: CocoaMQTTWebSocket(uri: "/mqtt")
        )
        let mqtt5 = CocoaMQTT5(
            clientID: "identity-websocket-5",
            socket: CocoaMQTTWebSocket(uri: "/mqtt")
        )

        mqtt.clientIdentity = identity
        mqtt5.clientIdentity = identity

        XCTAssertNil(mqtt.clientIdentity)
        XCTAssertNil(mqtt5.clientIdentity)
    }
#endif

    private func pemDER(_ data: Data, label: String) throws -> Data {
        let pem = try XCTUnwrap(String(data: data, encoding: .utf8))
        let begin = try XCTUnwrap(pem.range(of: "-----BEGIN \(label)-----"))
        let end = try XCTUnwrap(pem.range(of: "-----END \(label)-----"))
        let base64 = pem[begin.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        return try XCTUnwrap(Data(base64Encoded: String(base64)))
    }
}
#endif
