//
//  CocoaMQTTSocket.swift
//  CocoaMQTT
//
//  Created by Cyrus Ingraham on 12/13/19.
//

import Foundation
import MqttCocoaAsyncSocket

/// Selects one trust callback and prevents competing callbacks from resolving
/// the same transport challenge more than once.
enum CocoaMQTTTrustHandling {
    typealias URLSessionCompletion = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    private final class CompletionOnce<Value> {
        private let lock = NSLock()
        private var completion: ((Value) -> Void)?

        init(_ completion: @escaping (Value) -> Void) {
            self.completion = completion
        }

        func callAsFunction(_ value: Value) {
            lock.lock()
            guard let completion = completion else {
                lock.unlock()
                return
            }
            self.completion = nil
            lock.unlock()
            completion(value)
        }
    }

    static func resolveManualTrust(
        handler: (@escaping (Bool) -> Void) -> Bool,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let completion = CompletionOnce(completionHandler)
        if !handler({ completion($0) }) {
            completion(false)
        }
    }

    static func resolveURLSessionChallenge(
        urlSessionHandler: (@escaping URLSessionCompletion) -> Bool,
        legacyHandler: (@escaping (Bool) -> Void) -> Bool,
        legacyCredential: URLCredential,
        completionHandler: @escaping URLSessionCompletion
    ) {
        let completion = CompletionOnce<(URLSession.AuthChallengeDisposition, URLCredential?)> {
            completionHandler($0.0, $0.1)
        }
        let urlSessionCompletion: URLSessionCompletion = {
            completion(($0, $1))
        }

        if urlSessionHandler(urlSessionCompletion) {
            return
        }
        if legacyHandler({ accepted in
            // A legacy `true` is an explicit trust decision, not a request to
            // repeat the system validation that may already have failed.
            completion(accepted
                ? (.useCredential, legacyCredential)
                : (.rejectProtectionSpace, nil))
        }) {
            return
        }
        completion((.performDefaultHandling, nil))
    }
}

// MARK: - Interfaces

public protocol CocoaMQTTSocketDelegate: AnyObject {
    func socketConnected(_ socket: CocoaMQTTSocketProtocol)
    func socket(_ socket: CocoaMQTTSocketProtocol, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void)
    func socketUrlSession(_ socket: CocoaMQTTSocketProtocol, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int)
    func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int)
    func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError err: Error?)
}

public protocol CocoaMQTTSocketProtocol {

    var enableSSL: Bool { get set }

    func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?)
    func connect(toHost host: String, onPort port: UInt16) throws
    func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws
    func disconnect()
    func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int)
    func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int)
}

/// Normalizes callbacks from built-in and custom transports onto the client's
/// private event loop. Custom transports are not required to honor the queue
/// passed to `setDelegate`; correctness is enforced at this boundary instead.
final class CocoaMQTTSocketDelegateProxy: CocoaMQTTSocketDelegate {
    weak var delegate: CocoaMQTTSocketDelegate?

    private let eventLoopQueue: DispatchQueue
    private let eventLoopQueueKey = DispatchSpecificKey<Void>()

    init(eventLoopQueue: DispatchQueue) {
        self.eventLoopQueue = eventLoopQueue
        eventLoopQueue.setSpecific(key: eventLoopQueueKey, value: ())
    }

    private func forward(_ callback: @escaping (CocoaMQTTSocketDelegate?) -> Void) {
        if DispatchQueue.getSpecific(key: eventLoopQueueKey) != nil {
            callback(delegate)
        } else {
            eventLoopQueue.async { [self] in callback(delegate) }
        }
    }

    func socketConnected(_ socket: CocoaMQTTSocketProtocol) {
        forward { $0?.socketConnected(socket) }
    }

    func socket(
        _ socket: CocoaMQTTSocketProtocol,
        didReceive trust: SecTrust,
        completionHandler: @escaping (Bool) -> Void
    ) {
        forward { delegate in
            guard let delegate = delegate else {
                completionHandler(false)
                return
            }
            delegate.socket(socket, didReceive: trust, completionHandler: completionHandler)
        }
    }

    func socketUrlSession(
        _ socket: CocoaMQTTSocketProtocol,
        didReceiveTrust trust: SecTrust,
        didReceiveChallenge challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        forward { delegate in
            guard let delegate = delegate else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            delegate.socketUrlSession(
                socket,
                didReceiveTrust: trust,
                didReceiveChallenge: challenge,
                completionHandler: completionHandler
            )
        }
    }

    func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {
        forward { $0?.socket(socket, didWriteDataWithTag: tag) }
    }

    func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {
        forward { $0?.socket(socket, didRead: data, withTag: tag) }
    }

    func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError err: Error?) {
        forward { $0?.socketDidDisconnect(socket, withError: err) }
    }
}

/// A socket transport that can close only after its final write has drained.
public protocol CocoaMQTTDisconnectAfterWritingSocket: CocoaMQTTSocketProtocol {
    func writeAndDisconnect(_ data: Data, withTimeout timeout: TimeInterval, tag: Int)
}

public extension CocoaMQTTSocketProtocol {
    /// Writes the final bytes for a connection and closes it afterwards.
    ///
    /// Custom transports can adopt `CocoaMQTTDisconnectAfterWritingSocket` to
    /// provide drain semantics. Other transports retain the legacy immediate close.
    func writeAndDisconnect(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        if let gracefulSocket = self as? CocoaMQTTDisconnectAfterWritingSocket {
            gracefulSocket.writeAndDisconnect(data, withTimeout: timeout, tag: tag)
            return
        }
        write(data, withTimeout: timeout, tag: tag)
        disconnect()
    }
}

// MARK: - CocoaMQTTSocket

public class CocoaMQTTSocket: NSObject {

    public var backgroundOnSocket = true

    public var enableSSL = false

    ///
    public var sslSettings: [String: NSObject]?

    /// Allow self-signed ca certificate.
    ///
    /// Default is false
    public var allowUntrustCACertificate = false

    fileprivate let reference = MGCDAsyncSocket()
    fileprivate weak var delegate: CocoaMQTTSocketDelegate?

    public override init() { super.init() }
}

extension CocoaMQTTSocket: CocoaMQTTDisconnectAfterWritingSocket {
    public func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
        delegate = theDelegate
        reference.setDelegate((delegate != nil ? self : nil), delegateQueue: delegateQueue)
    }

    public func connect(toHost host: String, onPort port: UInt16) throws {
        try connect(toHost: host, onPort: port, withTimeout: -1)
    }

    public func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {
        try reference.connect(toHost: host, onPort: port, withTimeout: timeout)
    }

    public func disconnect() {
        reference.disconnect()
    }

    public func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        reference.readData(toLength: length, withTimeout: timeout, tag: tag)
    }

    public func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        reference.write(data, withTimeout: timeout, tag: tag)
    }

    public func writeAndDisconnect(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        reference.write(data, withTimeout: timeout, tag: tag)
        reference.disconnectAfterWriting()
    }
}

extension CocoaMQTTSocket: MGCDAsyncSocketDelegate {
    public func socket(_ sock: MGCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        printInfo("Connected to \(host) : \(port)")

        #if os(iOS)
        if backgroundOnSocket {
            sock.perform {
                guard sock.enableBackgroundingOnSocket() else {
                    printWarning("Enable backgrounding socket failed, please check related permissions")
                    return
                }
                printInfo("Enable backgrounding socket successfully")
            }
        }
        #endif

        if enableSSL {
            var setting = sslSettings ?? [:]
            if allowUntrustCACertificate {
                setting[MGCDAsyncSocketManuallyEvaluateTrust as String] = NSNumber(value: true)
            }
            sock.startTLS(setting)
        } else {
            delegate?.socketConnected(self)
        }
    }

    public func socket(_ sock: MGCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        if let theDelegate = delegate {
            theDelegate.socket(self, didReceive: trust, completionHandler: completionHandler)
        } else {
            completionHandler(false)
        }
    }

    public func socketDidSecure(_ sock: MGCDAsyncSocket) {
        printDebug("socket did secure")
        delegate?.socketConnected(self)
    }

    public func socket(_ sock: MGCDAsyncSocket, didWriteDataWithTag tag: Int) {
        printDebug("socket wrote data \(tag)")
        delegate?.socket(self, didWriteDataWithTag: tag)
    }

    public func socket(_ sock: MGCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        delegate?.socket(self, didRead: data, withTag: tag)
    }

    public func socketDidDisconnect(_ sock: MGCDAsyncSocket, withError err: Error?) {
        printDebug("socket disconnected")
        delegate?.socketDidDisconnect(self, withError: err)
    }
}
