//
//  CocoaMQTTClientIdentity.swift
//  CocoaMQTT
//

import Foundation
import Security
import Darwin

/// Errors raised while creating a mutual-TLS client identity.
public enum CocoaMQTTClientIdentityError: Error, Equatable {
    case invalidCertificate
    case invalidPrivateKey
    case encryptedPrivateKeyUnsupported
    case unsupportedPrivateKeyAlgorithm
    case identityCreationUnavailable
    case certificatePrivateKeyMismatch
    case invalidIntermediateCertificate(index: Int)
}

extension CocoaMQTTClientIdentityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            return "The client certificate is not valid PEM or DER data."
        case .invalidPrivateKey:
            return "The client private key is not valid RSA PKCS#1 or PKCS#8 data."
        case .encryptedPrivateKeyUnsupported:
            return "Encrypted PEM private keys are not supported."
        case .unsupportedPrivateKeyAlgorithm:
            return "Only RSA PEM private keys are supported."
        case .identityCreationUnavailable:
            return "Client identity creation is unavailable on this operating system."
        case .certificatePrivateKeyMismatch:
            return "The client certificate and private key do not match."
        case let .invalidIntermediateCertificate(index):
            return "The intermediate certificate at index \(index) is not valid PEM or DER data."
        }
    }
}

/// A client identity and certificate chain used for mutual TLS.
///
/// The PEM/DER convenience initializer imports the identity in memory and does
/// not add the private key to the Keychain. It supports RSA PKCS#1
/// (`RSA PRIVATE KEY`) and unencrypted RSA PKCS#8 (`PRIVATE KEY`) input.
public final class CocoaMQTTClientIdentity: NSObject {
    public let identity: SecIdentity
    public let intermediateCertificates: [SecCertificate]

    public init(
        identity: SecIdentity,
        intermediateCertificates: [SecCertificate] = []
    ) {
        self.identity = identity
        self.intermediateCertificates = intermediateCertificates
        super.init()
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
    public convenience init(
        certificateData: Data,
        privateKeyData: Data,
        intermediateCertificateData: [Data] = []
    ) throws {
        guard let certificate = CocoaMQTTSocket.serverCertificate(from: certificateData) else {
            throw CocoaMQTTClientIdentityError.invalidCertificate
        }

        let privateKey = try Self.makeRSAPrivateKey(from: privateKeyData)
        guard Self.keysMatch(certificate: certificate, privateKey: privateKey) else {
            throw CocoaMQTTClientIdentityError.certificatePrivateKeyMismatch
        }
        let identity = try Self.makeIdentity(certificate: certificate, privateKey: privateKey)

        let intermediates = try intermediateCertificateData.enumerated().map { index, data in
            guard let certificate = CocoaMQTTSocket.serverCertificate(from: data) else {
                throw CocoaMQTTClientIdentityError.invalidIntermediateCertificate(index: index)
            }
            return certificate
        }
        self.init(identity: identity, intermediateCertificates: intermediates)
    }

    private static func makeRSAPrivateKey(from data: Data) throws -> SecKey {
        let keyData: Data
        if let pem = String(data: data, encoding: .utf8),
           pem.contains("-----BEGIN") {
            let uppercasePEM = pem.uppercased()
            if uppercasePEM.contains("ENCRYPTED PRIVATE KEY") ||
                uppercasePEM.contains("PROC-TYPE: 4,ENCRYPTED") ||
                uppercasePEM.contains("DEK-INFO:") {
                throw CocoaMQTTClientIdentityError.encryptedPrivateKeyUnsupported
            }
            if pem.contains("-----BEGIN EC PRIVATE KEY-----") {
                throw CocoaMQTTClientIdentityError.unsupportedPrivateKeyAlgorithm
            }
            let privateKeyBeginCount = pem.components(separatedBy: "-----BEGIN ")
                .dropFirst()
                .filter { $0.contains("PRIVATE KEY-----") }
                .count
            guard privateKeyBeginCount == 1 else {
                throw CocoaMQTTClientIdentityError.invalidPrivateKey
            }
            if pem.contains("-----BEGIN RSA PRIVATE KEY-----") {
                keyData = try decodePEM(pem, label: "RSA PRIVATE KEY")
            } else if pem.contains("-----BEGIN PRIVATE KEY-----") {
                let pkcs8 = try decodePEM(pem, label: "PRIVATE KEY")
                keyData = try unwrapRSAPKCS8(pkcs8)
            } else {
                throw CocoaMQTTClientIdentityError.unsupportedPrivateKeyAlgorithm
            }
        } else if let key = createRSAKey(data) {
            return key
        } else {
            keyData = try unwrapRSAPKCS8(data)
        }

        guard let key = createRSAKey(keyData) else {
            throw CocoaMQTTClientIdentityError.invalidPrivateKey
        }
        return key
    }

    private static func createRSAKey(_ data: Data) -> SecKey? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        return SecKeyCreateWithData(data as CFData, attributes as CFDictionary, nil)
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
    private static func keysMatch(
        certificate: SecCertificate,
        privateKey: SecKey
    ) -> Bool {
        guard let certificateKey = SecCertificateCopyKey(certificate),
              let derivedKey = SecKeyCopyPublicKey(privateKey),
              let certificateKeyData = SecKeyCopyExternalRepresentation(
                certificateKey,
                nil
              ),
              let derivedKeyData = SecKeyCopyExternalRepresentation(derivedKey, nil) else {
            return false
        }
        return CFEqual(certificateKeyData, derivedKeyData)
    }

    private typealias SecIdentityCreateFunction = @convention(c) (
        CFAllocator?,
        SecCertificate,
        SecKey
    ) -> Unmanaged<SecIdentity>?

    /// `SecIdentityCreate` has been available in Apple operating systems for
    /// years, but was absent from older SDK headers. Resolve the public Security
    /// framework symbol at runtime so clients can still build with those SDKs.
    private static func makeIdentity(
        certificate: SecCertificate,
        privateKey: SecKey
    ) throws -> SecIdentity {
        let defaultSymbolScope = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultSymbolScope, "SecIdentityCreate") else {
            throw CocoaMQTTClientIdentityError.identityCreationUnavailable
        }
        let createIdentity = unsafeBitCast(symbol, to: SecIdentityCreateFunction.self)
        guard let identity = createIdentity(nil, certificate, privateKey)?.takeRetainedValue() else {
            throw CocoaMQTTClientIdentityError.certificatePrivateKeyMismatch
        }
        return identity
    }

    private static func decodePEM(_ pem: String, label: String) throws -> Data {
        let beginMarker = "-----BEGIN \(label)-----"
        let endMarker = "-----END \(label)-----"
        guard let begin = pem.range(of: beginMarker),
              pem.range(of: beginMarker, range: begin.upperBound..<pem.endIndex) == nil,
              let end = pem.range(of: endMarker, range: begin.upperBound..<pem.endIndex),
              pem.range(of: endMarker, range: end.upperBound..<pem.endIndex) == nil else {
            throw CocoaMQTTClientIdentityError.invalidPrivateKey
        }

        let encoded = pem[begin.upperBound..<end.lowerBound]
            .filter { !$0.isWhitespace }
        guard !encoded.isEmpty, let decoded = Data(base64Encoded: String(encoded)) else {
            throw CocoaMQTTClientIdentityError.invalidPrivateKey
        }
        return decoded
    }

    private static func unwrapRSAPKCS8(_ data: Data) throws -> Data {
        do {
            var outerReader = DERReader(data)
            var privateKeyInfo = try outerReader.readConstructed(tag: 0x30)
            try outerReader.requireEnd()

            let version = try privateKeyInfo.readValue(tag: 0x02)
            guard version == Data([0]) else {
                throw DERError.invalid
            }

            var algorithm = try privateKeyInfo.readConstructed(tag: 0x30)
            let rsaEncryptionOID = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01])
            guard try algorithm.readValue(tag: 0x06) == rsaEncryptionOID else {
                throw CocoaMQTTClientIdentityError.unsupportedPrivateKeyAlgorithm
            }
            if !algorithm.isAtEnd {
                guard try algorithm.readValue(tag: 0x05).isEmpty else {
                    throw DERError.invalid
                }
            }
            try algorithm.requireEnd()

            let privateKey = try privateKeyInfo.readValue(tag: 0x04)
            if !privateKeyInfo.isAtEnd {
                _ = try privateKeyInfo.readValue(tag: 0xa0)
            }
            try privateKeyInfo.requireEnd()
            return privateKey
        } catch let error as CocoaMQTTClientIdentityError {
            throw error
        } catch {
            throw CocoaMQTTClientIdentityError.invalidPrivateKey
        }
    }
}

private enum DERError: Error {
    case invalid
}

private struct DERReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readConstructed(tag: UInt8) throws -> DERReader {
        DERReader(try readValue(tag: tag))
    }

    mutating func readValue(tag: UInt8) throws -> Data {
        guard offset < data.count, data[offset] == tag else {
            throw DERError.invalid
        }
        offset += 1
        let length = try readLength()
        guard length <= data.count - offset else {
            throw DERError.invalid
        }
        let value = data.subdata(in: offset..<(offset + length))
        offset += length
        return value
    }

    mutating func requireEnd() throws {
        guard isAtEnd else {
            throw DERError.invalid
        }
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else {
            throw DERError.invalid
        }
        let first = data[offset]
        offset += 1
        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7f)
        guard byteCount > 0,
              byteCount <= MemoryLayout<Int>.size,
              byteCount <= data.count - offset,
              data[offset] != 0 else {
            throw DERError.invalid
        }

        var length = 0
        for _ in 0..<byteCount {
            guard length <= (Int.max - Int(data[offset])) / 256 else {
                throw DERError.invalid
            }
            length = length * 256 + Int(data[offset])
            offset += 1
        }
        guard length >= 128 else {
            throw DERError.invalid
        }
        return length
    }
}
