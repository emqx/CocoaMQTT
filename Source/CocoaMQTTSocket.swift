//
//  CocoaMQTTSocket.swift
//  CocoaMQTT
//
//  Created by Cyrus Ingraham on 12/13/19.
//

import Foundation
import CocoaAsyncSocket
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
        
        //reference.setDelegate((delegate != nil ? self : nil), delegateQueue: delegateQueue)
    }
    
    public func connect(toHost host: String, onPort port: UInt16) throws {
        try connect(toHost: host, onPort: port, withTimeout: -1)
    }
    
    public func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {
        // try reference.connect(toHost: host, onPort: port, withTimeout: timeout)
        
        
        let conn = NWConnection(host: "cocoamqtt.rnd7.de", port: 8883, using: .tls)
        
        conn.stateUpdateHandler = { (newState) in
            //print(newState)
            
            switch newState {
            case .ready:
                self.delegate?.socketConnected(self)
            case .waiting(let error):
                print(error)
                break
            case .failed(let error):
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
            print("ERROR: No dispatch queue")
        }
    }
    
    public func disconnect() {
        self.connection?.cancel()
    }
    
    public func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        // reference.readData(toLength: length, withTimeout: timeout, tag: tag)
        
        let len = Int(length)
        
        connection?.receive(minimumIncompleteLength: len, maximumLength: len) { (content, contentContext, isComplete, error) in
            if let error = error {
                print("ERROR READ DATA \(error)")
            // Handle error in reading
            } else {
                if let data = content {
                    self.delegate?.socket(self, didRead: data, withTag: tag)
                }
            }
        }
        
    }
    
    public func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        // self.connection?.send(content: data, completion: () => {})
        // reference.write(data, withTimeout: timeout, tag: tag)
        connection?.send(content: data, completion: .contentProcessed { (sendError) in
            if let sendError = sendError {
             // Handle error in sending
                print("SEND ERROR \(sendError)")
            }
            else {
                self.delegate?.socket(self, didWriteDataWithTag: tag)
            }
        })
    }
}

extension CocoaMQTTSocket: GCDAsyncSocketDelegate {
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
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
                 setting[GCDAsyncSocketManuallyEvaluateTrust as String] = NSNumber(value: true)
             }
             sock.startTLS(setting)
         } else {
            delegate?.socketConnected(self)
         }
    }

    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        if let theDelegate = delegate {
            theDelegate.socket(self, didReceive: trust, completionHandler: completionHandler)
        } else {
            completionHandler(false)
        }
    }

    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        printDebug("socket did secure")
        delegate?.socketConnected(self)
    }

    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        printDebug("socket wrote data \(tag)")
        delegate?.socket(self, didWriteDataWithTag: tag)
    }

    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        delegate?.socket(self, didRead: data, withTag: tag)
    }

    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        printDebug("socket disconnected")
        delegate?.socketDidDisconnect(self, withError: err)
    }
}
