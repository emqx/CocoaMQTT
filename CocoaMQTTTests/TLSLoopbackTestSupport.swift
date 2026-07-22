#if os(macOS)
import Foundation
import Network
import Security
@testable import CocoaMQTT

/// Minimal TLS broker that records CONNECT protocol levels and returns CONNACK.
final class TLSMQTTLoopbackBroker {

    private let queue = DispatchQueue(label: "tests.cocoamqtt.tls-loopback-broker")
    private let listener: NWListener
    private let onConnect: ((UInt8) -> Void)?
    private let lock = NSLock()
    private var connections = [NWConnection]()
    private var protocolLevels = [UInt8]()

    var port: UInt16? {
        listener.port?.rawValue
    }

    var receivedProtocolLevels: [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        return protocolLevels
    }

    init(identity: SecIdentity, onConnect: ((UInt8) -> Void)? = nil) throws {
        self.onConnect = onConnect
        let tlsOptions = NWProtocolTLS.Options()
        guard let protocolIdentity = sec_identity_create(identity) else {
            throw TLSLoopbackError.invalidIdentity
        }
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            protocolIdentity
        )
        listener = try NWListener(
            using: NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options()),
            on: .any
        )
    }

    func start(onReady: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                onReady()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock()
            self.connections.append(connection)
            self.lock.unlock()
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, case .ready = state else { return }
                self.receiveConnect(from: connection)
            }
            connection.start(queue: self.queue)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let activeConnections = connections
        connections.removeAll()
        lock.unlock()
        activeConnections.forEach { $0.cancel() }
    }

    private func receiveConnect(from connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            if let protocolLevel = Self.connectProtocolLevel(in: nextBuffer) {
                self.lock.lock()
                self.protocolLevels.append(protocolLevel)
                self.lock.unlock()
                self.onConnect?(protocolLevel)
                let connAck = protocolLevel == 5
                    ? Data([0x20, 0x03, 0x00, 0x00, 0x00])
                    : Data([0x20, 0x02, 0x00, 0x00])
                connection.send(content: connAck, completion: .contentProcessed { _ in })
                return
            }
            if !isComplete && error == nil {
                self.receiveConnect(from: connection, buffer: nextBuffer)
            }
        }
    }

    private static func connectProtocolLevel(in data: Data) -> UInt8? {
        guard data.count >= 2, data[0] >> 4 == 1 else { return nil }
        var remainingLength = 0
        var multiplier = 1
        var index = 1

        for _ in 0..<4 {
            guard index < data.count else { return nil }
            let byte = data[index]
            remainingLength += Int(byte & 0x7f) * multiplier
            index += 1
            if byte & 0x80 == 0 {
                guard remainingLength >= 7,
                      data.count >= index + remainingLength else { return nil }
                return data[index + 6]
            }
            multiplier *= 128
        }
        return nil
    }
}

/// Generates fresh certificates so Apple's leaf-validity limit cannot expire the tests.
final class TLSLoopbackCertificateFixture {

    let rootCertificate: SecCertificate
    let untrustedRootCertificate: SecCertificate
    let serverIdentity: SecIdentity

    private let directory: URL

    init() throws {
        let fileManager = FileManager.default
        let fixtureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("cocoamqtt-tls-\(UUID().uuidString)", isDirectory: true)
        directory = fixtureDirectory
        try fileManager.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        var initializationSucceeded = false
        defer {
            if !initializationSucceeded {
                try? fileManager.removeItem(at: fixtureDirectory)
            }
        }

        let file: (String) -> URL = { fixtureDirectory.appendingPathComponent($0) }
        let rootKey = file("root.key")
        let rootPEM = file("root.pem")
        let untrustedRootKey = file("untrusted-root.key")
        let untrustedRootPEM = file("untrusted-root.pem")
        let intermediateKey = file("intermediate.key")
        let intermediateRequest = file("intermediate.csr")
        let intermediateExtensions = file("intermediate.ext")
        let intermediatePEM = file("intermediate.pem")
        let serverKey = file("server.key")
        let serverRequest = file("server.csr")
        let serverExtensions = file("server.ext")
        let serverPEM = file("server.pem")
        let serverChain = file("server-chain.pem")
        let serverPKCS12 = file("server.p12")

        try Data("""
        basicConstraints=critical,CA:TRUE,pathlen:0
        keyUsage=critical,keyCertSign,cRLSign
        subjectKeyIdentifier=hash
        authorityKeyIdentifier=keyid,issuer
        """.utf8).write(to: intermediateExtensions)
        try Data("""
        subjectAltName=DNS:broker.example.com,IP:127.0.0.1
        extendedKeyUsage=serverAuth
        basicConstraints=critical,CA:FALSE
        keyUsage=critical,digitalSignature,keyEncipherment
        """.utf8).write(to: serverExtensions)

        try Self.runOpenSSL([
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes",
            "-days", "3650", "-subj", "/CN=CocoaMQTT Loopback Root",
            "-keyout", rootKey.path, "-out", rootPEM.path
        ])
        try Self.runOpenSSL([
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes",
            "-days", "3650", "-subj", "/CN=CocoaMQTT Untrusted Root",
            "-keyout", untrustedRootKey.path, "-out", untrustedRootPEM.path
        ])
        try Self.runOpenSSL([
            "req", "-newkey", "rsa:2048", "-sha256", "-nodes",
            "-subj", "/CN=CocoaMQTT Loopback Intermediate",
            "-keyout", intermediateKey.path, "-out", intermediateRequest.path
        ])
        try Self.runOpenSSL([
            "x509", "-req", "-in", intermediateRequest.path,
            "-CA", rootPEM.path, "-CAkey", rootKey.path, "-CAcreateserial",
            "-days", "1825", "-sha256", "-extfile", intermediateExtensions.path,
            "-out", intermediatePEM.path
        ])
        try Self.runOpenSSL([
            "req", "-newkey", "rsa:2048", "-sha256", "-nodes",
            "-subj", "/CN=broker.example.com",
            "-keyout", serverKey.path, "-out", serverRequest.path
        ])
        try Self.runOpenSSL([
            "x509", "-req", "-in", serverRequest.path,
            "-CA", intermediatePEM.path, "-CAkey", intermediateKey.path, "-CAcreateserial",
            "-days", "365", "-sha256", "-extfile", serverExtensions.path,
            "-out", serverPEM.path
        ])
        var chainData = try Data(contentsOf: intermediatePEM)
        chainData.append(try Data(contentsOf: rootPEM))
        try chainData.write(to: serverChain)
        try Self.runOpenSSL([
            "pkcs12", "-export", "-out", serverPKCS12.path,
            "-inkey", serverKey.path, "-in", serverPEM.path,
            "-certfile", serverChain.path, "-passout", "pass:loopback"
        ])

        let rootData = try Data(contentsOf: rootPEM)
        guard let rootCertificate = CocoaMQTTSocket.serverCertificate(from: rootData) else {
            throw TLSLoopbackError.invalidRootCertificate
        }
        self.rootCertificate = rootCertificate
        let untrustedRootData = try Data(contentsOf: untrustedRootPEM)
        guard let untrustedRootCertificate = CocoaMQTTSocket.serverCertificate(
            from: untrustedRootData
        ) else {
            throw TLSLoopbackError.invalidRootCertificate
        }
        self.untrustedRootCertificate = untrustedRootCertificate

        let p12 = try Data(contentsOf: serverPKCS12)
        let options = [kSecImportExportPassphrase as String: "loopback"] as CFDictionary
        var importedItems: CFArray?
        guard SecPKCS12Import(p12 as CFData, options, &importedItems) == errSecSuccess,
              let items = importedItems as? [[String: Any]],
              let identity = items.first?[kSecImportItemIdentity as String] else {
            throw TLSLoopbackError.invalidIdentity
        }
        serverIdentity = identity as! SecIdentity
        initializationSucceeded = true
    }

    deinit {
        removeTemporaryFiles()
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func runOpenSSL(_ arguments: [String]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw TLSLoopbackError.openSSLFailed(message)
        }
    }
}

private enum TLSLoopbackError: Error {
    case invalidIdentity
    case invalidRootCertificate
    case openSSLFailed(String)
}
#endif
