//
//  CocoaMQTTSocket.swift
//  CocoaMQTT
//
//  Created by Cyrus Ingraham on 12/13/19.
//

import Foundation
import Network

// MARK: - Interfaces

public protocol CocoaMQTTSocketDelegate: AnyObject {
    func socketConnected(_ socket: CocoaMQTTSocketProtocol)
    func socket(_ socket: CocoaMQTTSocketProtocol, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void)
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
    
    fileprivate var delegateQueue: DispatchQueue?
    fileprivate var connection: NWConnection?
    fileprivate weak var delegate: CocoaMQTTSocketDelegate?
    
    public override init() { super.init() }
}

extension CocoaMQTTSocket: CocoaMQTTSocketProtocol {
    public func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {
        delegate = theDelegate
        self.delegateQueue = delegateQueue
    }
    
    public func connect(toHost host: String, onPort port: UInt16) throws {
        try connect(toHost: host, onPort: port, withTimeout: -1)
    }
    
    private func getClientCertificate() -> SecIdentity? {
        if let array = sslSettings?["kCFStreamSSLCertificates"] {
            if let list = array as? NSArray {
                if list.count == 1 {
                    let clientIdentity = list[0]
                    return (clientIdentity as! SecIdentity)
                }
            }
        }
        return nil
    }
    
    private func createConnection(toHost host: String, onPort port: UInt16) -> NWConnection {
        let nwHost = NWEndpoint.Host(host)
        let endpoint = NWEndpoint.Port(rawValue: port) ?? 1883
        
        if enableSSL {
            // see https://developer.apple.com/forums/thread/113312
            
            let options = NWProtocolTLS.Options()
            let securityOptions = options.securityProtocolOptions
            
            if allowUntrustCACertificate {
                sec_protocol_options_set_verify_block(securityOptions, { (_, trust, completionHandler) in
                    completionHandler(true)
                }, .main)
            }
         
            if let clientIdentity = getClientCertificate() {
                printDebug("connect using clientIdentity \(clientIdentity)")
                sec_protocol_options_set_local_identity(
                   securityOptions,
                   sec_identity_create(clientIdentity)!
                )
            }
            
            
            let params = NWParameters(tls: options)
            return NWConnection(host: nwHost, port: endpoint, using: params)
        }
        
        return NWConnection(host: nwHost, port: endpoint, using: .tcp)
        
    }
    
    public func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {
        let conn = createConnection(toHost: host, onPort: port)
        conn.stateUpdateHandler = { (newState) in
            switch newState {
            case .ready:
                self.delegate?.socketConnected(self)
            case .waiting(let error):
                printError("Connect caused an error: \(error)")
                self.delegate?.socketDidDisconnect(self, withError: error)
                break
            case .failed(let error):
                printError("Connect failed with error: \(error)")
                self.delegate?.socketDidDisconnect(self, withError: error)
            case .cancelled:
                self.delegate?.socketDidDisconnect(self, withError: nil)
            default:
            break
            }
        }
            
        if let queue = self.delegateQueue {
            conn.start(queue: queue)
            self.connection = conn
        }
        else {
            printError("No dispatch queue")
        }
    }
    
    public func disconnect() {
        self.connection?.cancel()
    }
    
    public func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        let len = Int(length)
        
        connection?.receive(minimumIncompleteLength: len, maximumLength: len) { (content, contentContext, isComplete, error) in
            if let error = error {
                printError("Read data caused an error: \(error)")
            } else {
                if let data = content {
                    self.delegate?.socket(self, didRead: data, withTag: tag)
                }
            }
        }
        
    }
    
    public func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        connection?.send(content: data, completion: .contentProcessed { (sendError) in
            if let sendError = sendError {
                printError("Write data caused an error: \(sendError)")
            }
            else {
                self.delegate?.socket(self, didWriteDataWithTag: tag)
            }
        })
    }
}
