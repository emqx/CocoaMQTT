//
//  MutualTLSConfiguration.swift
//  Example
//

import CocoaMQTT
import Foundation
import Security

protocol CocoaMQTTMutualTLSConfiguring: AnyObject {
    var clientIdentity: CocoaMQTTClientIdentity? { get set }
    var trustedServerCertificates: [SecCertificate] { get set }
    var usesSystemTrustStore: Bool { get set }
    var enableSSL: Bool { get set }
}

extension CocoaMQTT: CocoaMQTTMutualTLSConfiguring {}
extension CocoaMQTT5: CocoaMQTTMutualTLSConfiguring {}

enum MutualTLSExampleError: Error {
    case invalidBrokerCertificate(URL)
    case pkcs12ImportFailed(OSStatus)
    case pkcs12IdentityMissing
    case identityCertificateUnavailable
    case invalidPKCS12CertificateChain
}

enum MutualTLSConfiguration {

    /// Configures either MQTT client with an in-memory PEM/DER client identity.
    ///
    /// Obtain private-key data through secure provisioning. Do not embed a
    /// production private key in the application bundle.
    static func configureMutualTLSWithPEM<Client: CocoaMQTTMutualTLSConfiguring>(
        client: Client,
        clientCertificateURL: URL,
        privateKeyURL: URL,
        intermediateCertificateURLs: [URL] = [],
        brokerCAURLs: [URL] = [],
        usesSystemTrustStore: Bool = true
    ) throws {
        let identity = try CocoaMQTTClientIdentity(
            certificateData: try Data(contentsOf: clientCertificateURL),
            privateKeyData: try Data(contentsOf: privateKeyURL),
            intermediateCertificateData: try intermediateCertificateURLs.map {
                try Data(contentsOf: $0)
            }
        )
        try configure(
            client: client,
            identity: identity,
            brokerCAURLs: brokerCAURLs,
            usesSystemTrustStore: usesSystemTrustStore
        )
    }

    /// Configures either MQTT client with a password-protected PKCS#12 identity.
    ///
    /// Obtain the password from user input or secure storage. Never embed a
    /// production PKCS#12 password in the application.
    static func configureMutualTLSWithPKCS12<Client: CocoaMQTTMutualTLSConfiguring>(
        client: Client,
        pkcs12URL: URL,
        password: String,
        brokerCAURLs: [URL] = [],
        usesSystemTrustStore: Bool = true
    ) throws {
        let identity = try clientIdentity(
            fromPKCS12: Data(contentsOf: pkcs12URL),
            password: password
        )
        try configure(
            client: client,
            identity: identity,
            brokerCAURLs: brokerCAURLs,
            usesSystemTrustStore: usesSystemTrustStore
        )
    }

    private static func clientIdentity(
        fromPKCS12 data: Data,
        password: String
    ) throws -> CocoaMQTTClientIdentity {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &rawItems)
        guard status == errSecSuccess else {
            throw MutualTLSExampleError.pkcs12ImportFailed(status)
        }
        guard let items = rawItems as? [[String: Any]],
              let item = items.first(where: { item in
                  guard let value = item[kSecImportItemIdentity as String] else {
                      return false
                  }
                  return CFGetTypeID(value as CFTypeRef) == SecIdentityGetTypeID()
              }),
              let identityValue = item[kSecImportItemIdentity as String] else {
            throw MutualTLSExampleError.pkcs12IdentityMissing
        }
        let identity = identityValue as! SecIdentity

        var leafCertificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &leafCertificate) == errSecSuccess,
              let leafCertificate else {
            throw MutualTLSExampleError.identityCertificateUnavailable
        }

        var seenCertificates = Set([SecCertificateCopyData(leafCertificate) as Data])
        let certificateChain = try certificates(
            fromPKCS12Item: item[kSecImportItemCertChain as String]
        )
        let intermediates = certificateChain.filter {
            seenCertificates.insert(SecCertificateCopyData($0) as Data).inserted
        }
        return CocoaMQTTClientIdentity(
            identity: identity,
            intermediateCertificates: intermediates
        )
    }

    private static func certificates(fromPKCS12Item value: Any?) throws -> [SecCertificate] {
        guard let value else {
            return []
        }
        guard CFGetTypeID(value as CFTypeRef) == CFArrayGetTypeID() else {
            throw MutualTLSExampleError.invalidPKCS12CertificateChain
        }

        let array = value as! CFArray
        return try (0..<CFArrayGetCount(array)).map { index in
            let element = unsafeBitCast(
                CFArrayGetValueAtIndex(array, index),
                to: CFTypeRef.self
            )
            guard CFGetTypeID(element) == SecCertificateGetTypeID() else {
                throw MutualTLSExampleError.invalidPKCS12CertificateChain
            }
            return unsafeBitCast(element, to: SecCertificate.self)
        }
    }

    private static func configure<Client: CocoaMQTTMutualTLSConfiguring>(
        client: Client,
        identity: CocoaMQTTClientIdentity,
        brokerCAURLs: [URL],
        usesSystemTrustStore: Bool
    ) throws {
        let brokerCertificates = try brokerCAURLs.map { url in
            let data = try Data(contentsOf: url)
            guard let certificate = CocoaMQTTSocket.serverCertificate(from: data) else {
                throw MutualTLSExampleError.invalidBrokerCertificate(url)
            }
            return certificate
        }

        client.clientIdentity = identity
        client.trustedServerCertificates = brokerCertificates
        client.usesSystemTrustStore = usesSystemTrustStore
        client.enableSSL = true
    }
}
