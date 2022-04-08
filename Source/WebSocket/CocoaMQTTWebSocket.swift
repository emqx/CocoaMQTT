//
//  CocoaMQTTWebSocket.swift
//  CocoaMQTT
//
//  Created by Cyrus Ingraham on 12/13/19.
//

import Foundation
#if IS_SWIFT_PACKAGE
import CocoaMQTT
#endif

// MARK: - Interfaces

public protocol CocoaMQTTWebSocketConnectionDelegate: AnyObject {

    func connection(_ conn: CocoaMQTTWebSocketConnection, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void)

    func urlSessionConnection(_ conn: CocoaMQTTWebSocketConnection, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)

    func connectionOpened(_ conn: CocoaMQTTWebSocketConnection)

    func connectionClosed(_ conn: CocoaMQTTWebSocketConnection, withError error: Error?, withCode code: UInt16?)

    func connection(_ conn: CocoaMQTTWebSocketConnection, receivedString string: String)

    func connection(_ conn: CocoaMQTTWebSocketConnection, receivedData data: Data)
}

public protocol CocoaMQTTWebSocketConnection: NSObjectProtocol {

    var delegate: CocoaMQTTWebSocketConnectionDelegate? { get set }

    var queue: DispatchQueue { get set }

    func connect()

    func disconnect()

    func write(data: Data, handler: @escaping (Error?) -> Void)
}

public protocol CocoaMQTTWebSocketConnectionBuilder {

    func buildConnection(forURL url: URL, withHeaders headers: [String: String]) throws -> CocoaMQTTWebSocketConnection

}

private protocol CocoaMQTTWebSocketMessageSizeConfiguring: AnyObject {
    var maximumMessageSize: Int { get set }
}

// MARK: - CocoaMQTTWebSocket

public class CocoaMQTTWebSocket: CocoaMQTTDisconnectAfterWritingSocket,
    CocoaMQTTClientIdentityConfiguring,
    CocoaMQTTServerTrustConfiguring {

    private static let foundationDefaultMaximumMessageSize = 1_048_576

    public var enableSSL = false

    public var shouldConnectWithURIOnly = false

    public var headers: [String: String] = [:]

    /// Server name used for TLS identity verification. Defaults to the URL
    /// host, which continues to control routing and TLS SNI.
    public var tlsServerName: String?

    /// Additional CA certificates trusted by the Foundation transport.
    public var trustedServerCertificates = [SecCertificate]()

    /// Whether custom CA validation also accepts the system trust store.
    public var usesSystemTrustStore = true

    /// Gives the client trust callback first chance to decide. Configured
    /// custom CA certificates remain the fallback; without either, enabling
    /// this setting rejects the connection.
    public var manuallyEvaluateTrust = false

    /// Client identity sent during the TLS handshake by the built-in Apple
    /// `URLSessionWebSocketTask` transport, selected automatically on macOS
    /// 10.15, iOS 13, tvOS 13, visionOS 1, and later. The Starscream fallback
    /// used on older OS versions does not apply this identity. Custom
    /// connection builders may opt in by returning a
    /// `CocoaMQTTClientIdentityConfiguring` connection. Set this before
    /// connecting. The built-in transport sends it only to the original
    /// WebSocket host and port.
    public var clientIdentity: CocoaMQTTClientIdentity?

    /// Incoming WebSocket message buffering limit for the built-in Apple
    /// `URLSessionWebSocketTask` transport. A message must be smaller than this
    /// value. The default is 1 MiB, zero removes the limit, and negative values
    /// reset to the default. Set this before connecting; custom builders must
    /// configure their own transports. The older Starscream fallback does not
    /// use this setting.
    /// Use zero only when the peer and message sizes are otherwise controlled,
    /// because it permits unbounded message buffering.
    public var maximumMessageSize = CocoaMQTTWebSocket.foundationDefaultMaximumMessageSize {
        didSet {
            if maximumMessageSize < 0 {
                maximumMessageSize = CocoaMQTTWebSocket.foundationDefaultMaximumMessageSize
            }
        }
    }

    public typealias ConnectionBuilder = CocoaMQTTWebSocketConnectionBuilder

    public struct DefaultConnectionBuilder: ConnectionBuilder {

        public init() {}

        public func buildConnection(forURL url: URL, withHeaders headers: [String: String]) throws -> CocoaMQTTWebSocketConnection {
            let config = URLSessionConfiguration.default
            config.httpAdditionalHeaders = headers
            return CocoaMQTTWebSocket.FoundationConnection(url: url, config: config)
        }
    }

    public func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
        internalQueue.async {
            self.delegate = theDelegate
            self.delegateQueue = delegateQueue
        }
    }
    let uri: String
    let builder: ConnectionBuilder
    public init(uri: String = "", builder: ConnectionBuilder = CocoaMQTTWebSocket.DefaultConnectionBuilder()) {
        self.uri = uri
        self.builder = builder
    }

    public func connect(toHost host: String, onPort port: UInt16) throws {
        try connect(toHost: host, onPort: port, withTimeout: -1)
    }

    public func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {

        var urlStr = ""

        if shouldConnectWithURIOnly {
            urlStr = "\(uri)"
        } else {
            urlStr = "\(enableSSL ? "wss": "ws")://\(host):\(port)\(uri)"
        }

        guard let url = URL(string: urlStr) else { throw CocoaMQTTError.invalidURL }
        try internalQueue.sync {
            reset()
            disconnectAfterWrites = false
            let newConnection = try builder.buildConnection(forURL: url, withHeaders: self.headers)
            if let configurableConnection = newConnection as? CocoaMQTTWebSocketMessageSizeConfiguring {
                configurableConnection.maximumMessageSize = maximumMessageSize
            }
            if let configurableConnection = newConnection as? CocoaMQTTClientIdentityConfiguring {
                configurableConnection.clientIdentity = clientIdentity
            }
            connection = newConnection
            newConnection.delegate = self
            newConnection.queue = internalQueue
            newConnection.connect()
        }
    }

    public func disconnect() {
        internalQueue.async {
            // self.reset()
            self.disconnectAfterWrites = true
            self.closeConnection(withError: nil)
        }
    }

    public func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        internalQueue.async {
            let newRead = ReadItem(tag: tag, length: length, timeout: (timeout > 0.0) ? .now() + timeout : .distantFuture)
            self.scheduledReads.append(newRead)
            self.checkScheduledReads()
        }
    }

    public func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        internalQueue.async {
            guard !self.disconnectAfterWrites else { return }
            self.enqueueWrite(data, withTimeout: timeout, tag: tag)
        }
    }

    public func writeAndDisconnect(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        internalQueue.async {
            guard !self.disconnectAfterWrites else { return }
            self.disconnectAfterWrites = true
            self.enqueueWrite(data, withTimeout: timeout, tag: tag)
        }
    }

    @ConcurrentAtomic(wrappedValue: nil, label: "CocoaMQTTWebSocket.delegate")
    internal var delegate: CocoaMQTTSocketDelegate?
    internal var delegateQueue: DispatchQueue?
    internal var internalQueue = DispatchQueue(label: "CocoaMQTTWebSocket")

    private var connection: CocoaMQTTWebSocketConnection?

    private func reset() {
        connection?.delegate = nil
        connection?.disconnect()
        connection = nil

        readBuffer.removeAll()
        scheduledReads.removeAll()
        readTimeoutTimer.reset()

        scheduledWrites.removeAll()
        writeTimeoutTimer.reset()
    }

    private func closeConnection(withError error: Error?) {
        disconnectAfterWrites = true
        reset()
        __delegate_queue {
            self.delegate?.socketDidDisconnect(self, withError: error)
        }
    }

    private class ReusableTimer {
        let queue: DispatchQueue
        var timer: DispatchSourceTimer?

        init(queue: DispatchQueue) {
            self.queue = queue
        }

        func schedule(wallDeadline: DispatchWallTime, handler: @escaping () -> Void) {
            reset()
            let newTimer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            timer = newTimer
            newTimer.schedule(wallDeadline: wallDeadline)
            newTimer.setEventHandler(handler: handler)
            newTimer.resume()
        }

        func reset() {
            if timer != nil {
                timer?.cancel()
                timer = nil
            }
        }
    }

    private struct ReadItem {
        let tag: Int
        let length: UInt
        let timeout: DispatchWallTime
    }

    private var readBuffer = Data()
    private var scheduledReads: [ReadItem] = []
    private lazy var readTimeoutTimer = ReusableTimer(queue: internalQueue)
    private func checkScheduledReads() {
        guard let theDelegate = delegate else { return }
        guard let delegateQueue = delegateQueue else { return }

        readTimeoutTimer.reset()
        while (scheduledReads.first?.length ?? UInt.max) <= readBuffer.count {
            let nextRead = scheduledReads.removeFirst()
            let readRange = readBuffer.startIndex..<Data.Index(nextRead.length)
            let readData = readBuffer.subdata(in: readRange)
            readBuffer.removeSubrange(readRange)
            delegateQueue.async {
                theDelegate.socket(self, didRead: readData, withTag: nextRead.tag)
            }
        }

        guard let closestTimeout = scheduledReads.sorted(by: { a, b in a.timeout < b.timeout }).first?.timeout else { return }

        if closestTimeout < .now() {
            closeConnection(withError: CocoaMQTTError.readTimeout)
        } else {
            readTimeoutTimer.schedule(wallDeadline: closestTimeout) { [weak self] in
                self?.checkScheduledReads()
            }
        }
    }

    private struct WriteItem: Hashable {
        let uuid = UUID()
        let tag: Int
        let timeout: DispatchWallTime
        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
        }
    }
    private var scheduledWrites = Set<WriteItem>()
    private var disconnectAfterWrites = false
    private lazy var writeTimeoutTimer = ReusableTimer(queue: internalQueue)

    private func enqueueWrite(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        let newWrite = WriteItem(tag: tag, timeout: (timeout > 0.0) ? .now() + timeout : .distantFuture)
        scheduledWrites.insert(newWrite)
        checkScheduledWrites()
        connection?.write(data: data) { possibleError in
            guard self.scheduledWrites.remove(newWrite) != nil else { return }
            if let error = possibleError {
                self.closeConnection(withError: error)
                return
            }

            if let delegate = self.delegate {
                self.__delegate_queue {
                    delegate.socket(self, didWriteDataWithTag: tag)
                }
            }
            if self.disconnectAfterWrites && self.scheduledWrites.isEmpty {
                self.closeConnection(withError: nil)
            } else {
                self.checkScheduledWrites()
            }
        }
    }

    private func checkScheduledWrites() {
        writeTimeoutTimer.reset()
        guard let closestTimeout = scheduledWrites.sorted(by: { a, b in a.timeout < b.timeout }).first?.timeout else { return }
        if closestTimeout < .now() {
            closeConnection(withError: CocoaMQTTError.writeTimeout)
        } else {
            writeTimeoutTimer.schedule(wallDeadline: closestTimeout) { [weak self] in
                self?.checkScheduledWrites()
            }
        }
    }
}

extension CocoaMQTTWebSocket: CocoaMQTTWebSocketConnectionDelegate {
    public func urlSessionConnection(_ conn: CocoaMQTTWebSocketConnection, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let delegate = delegate else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let forwardChallenge = { [self] in
            delegate.socketUrlSession(
                self,
                didReceiveTrust: trust,
                didReceiveChallenge: challenge,
                completionHandler: completionHandler
            )
        }
        if let delegateQueue = delegateQueue {
            delegateQueue.async(execute: forwardChallenge)
        } else {
            forwardChallenge()
        }
    }

    public func connection(_ conn: CocoaMQTTWebSocketConnection, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        if let del = delegate {
            __delegate_queue {
                del.socket(self, didReceive: trust, completionHandler: completionHandler)
            }
        } else {
            completionHandler(false)
        }
    }

    public func connectionOpened(_ conn: CocoaMQTTWebSocketConnection) {
        guard conn.isEqual(connection) else { return }
        guard let delegate = delegate else { return }
        guard let delegateQueue = delegateQueue else { return }
        delegateQueue.async {
            delegate.socketConnected(self)
        }
    }

    public func connectionClosed(_ conn: CocoaMQTTWebSocketConnection, withError error: Error?, withCode code: UInt16?) {
        guard conn.isEqual(connection) else { return }
        closeConnection(withError: error)
    }

    public func connection(_ conn: CocoaMQTTWebSocketConnection, receivedString string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.connection(conn, receivedData: data)
    }

    public func connection(_ conn: CocoaMQTTWebSocketConnection, receivedData data: Data) {
        guard conn.isEqual(connection) else { return }
        readBuffer.append(data)
        checkScheduledReads()
    }
}

// MARK: - CocoaMQTTWebSocket.FoundationConnection

@available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension CocoaMQTTWebSocket {
    class FoundationConnection: NSObject, CocoaMQTTWebSocketConnection, CocoaMQTTClientIdentityConfiguring {

        public weak var delegate: CocoaMQTTWebSocketConnectionDelegate?
        public lazy var queue = DispatchQueue(label: "CocoaMQTTFoundationWebSocketConnection-\(self.hashValue)")
        public var clientIdentity: CocoaMQTTClientIdentity?
        private let endpointHost: String?
        private let endpointPort: Int?
        var maximumMessageSize: Int {
            get {
                task?.maximumMessageSize ?? CocoaMQTTWebSocket.foundationDefaultMaximumMessageSize
            }
            set {
                task?.maximumMessageSize = newValue < 0
                    ? CocoaMQTTWebSocket.foundationDefaultMaximumMessageSize
                    : newValue
            }
        }

        var session: URLSession?
        var task: URLSessionWebSocketTask?

        public init(url: URL, config: URLSessionConfiguration) {
            endpointHost = url.host
            endpointPort = url.port ?? (url.scheme?.lowercased() == "wss" ? 443 : 80)
            super.init()
            let theSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session = theSession
            task = theSession.webSocketTask(with: url, protocols: ["mqtt"])
        }

        public func connect() {
            task?.resume()
            scheduleRead()
        }

        public func disconnect() {
            task?.cancel()
            session = nil
            task = nil
            delegate = nil
        }

        public func write(data: Data, handler: @escaping (Error?) -> Void) {
            task?.send(.data(data)) { possibleError in
                self.queue.async {
                    handler(possibleError)
                }
            }
        }

        func scheduleRead() {
            queue.async {
                guard let task = self.task else { return }
                task.receive { result in
                    self.queue.async {
                        guard let delegate = self.delegate else { return }
                        switch result {
                        case .success(let message):
                            switch message {
                            case .data(let data):
                                delegate.connection(self, receivedData: data)
                            case .string(let string):
                                delegate.connection(self, receivedString: string)
                            @unknown default: break
                            }
                            self.scheduleRead()
                        case .failure(let error):
                            delegate.connectionClosed(self, withError: error, withCode: nil)
                        }
                    }
                }
            }
        }
    }
}

@available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension CocoaMQTTWebSocket.FoundationConnection: CocoaMQTTWebSocketMessageSizeConfiguring {}

@available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension CocoaMQTTWebSocket.FoundationConnection: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        queue.async {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
                let protectionSpace = challenge.protectionSpace
                guard let endpointHost = self.endpointHost,
                      let endpointPort = self.endpointPort,
                      !protectionSpace.isProxy(),
                      protectionSpace.host.caseInsensitiveCompare(endpointHost) == .orderedSame,
                      protectionSpace.port == endpointPort,
                      let clientIdentity = self.clientIdentity else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
                completionHandler(
                    .useCredential,
                    URLCredential(
                        identity: clientIdentity.identity,
                        certificates: clientIdentity.intermediateCertificates,
                        persistence: .forSession
                    )
                )
                return
            }
            if let trust = challenge.protectionSpace.serverTrust, let delegate = self.delegate {
                delegate.urlSessionConnection(self, didReceiveTrust: trust, didReceiveChallenge: challenge, completionHandler: completionHandler)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async {
            self.delegate?.connectionOpened(self)
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async {
            self.delegate?.connectionClosed(self, withError: CocoaMQTTError.FoundationConnection.closed(closeCode), withCode: nil)
        }
    }
}

// MARK: - Helper

extension CocoaMQTTWebSocket {

    func __delegate_queue(_ fun: @escaping () -> Void) {
        delegateQueue?.async { [weak self] in
            guard self != nil else { return }
            fun()
        }
    }
}
