//
//  CocoaMQTT.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation
import CocoaAsyncSocket


/**
 * QOS
 */
@objc public enum CocoaMQTTQOS: UInt8, CustomStringConvertible {
    case qos0 = 0
    case qos1
    case qos2
    
    public var description: String {
        switch self {
            case .qos0: return "qos0"
            case .qos1: return "qos1"
            case .qos2: return "qos2"
        }
    }
}

/**
 * Connection State
 */
@objc public enum CocoaMQTTConnState: UInt8, CustomStringConvertible {
    case initial = 0
    case connecting
    case connected
    case disconnected
    
    public var description: String {
        switch self {
            case .initial:      return "initial"
            case .connecting:   return "connecting"
            case .connected:    return "connected"
            case .disconnected: return "disconnected"
        }
    }
}

/**
 * Conn Ack
 */
@objc public enum CocoaMQTTConnAck: UInt8, CustomStringConvertible {
    case accept  = 0
    case unacceptableProtocolVersion
    case identifierRejected
    case serverUnavailable
    case badUsernameOrPassword
    case notAuthorized
    case reserved
    
    public var description: String {
        switch self {
            case .accept:                       return "accept"
            case .unacceptableProtocolVersion:  return "unacceptableProtocolVersion"
            case .identifierRejected:           return "identifierRejected"
            case .serverUnavailable:            return "serverUnavailable"
            case .badUsernameOrPassword:        return "badUsernameOrPassword"
            case .notAuthorized:                return "notAuthorized"
            case .reserved:                     return "reserved"
        }
    }
}

/**
 * asyncsocket read tag
 */
fileprivate enum CocoaMQTTReadTag: Int {
    case header = 0
    case length
    case payload
}

/**
 * MQTT Delegate
 */
@objc public protocol CocoaMQTTDelegate {
    /// MQTT connected with server
    // deprecated: instead of `mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)`
    // func mqtt(_ mqtt: CocoaMQTT, didConnect host: String, port: Int)
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16)
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16)
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 )
    // deprecated!!! instead of `func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topics: [String])`
    //func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String)
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topics: [String])
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String)
    func mqttDidPing(_ mqtt: CocoaMQTT)
    func mqttDidReceivePong(_ mqtt: CocoaMQTT)
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?)
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void)
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16)
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState)
}

/**
 * Blueprint of the MQTT client
 */
protocol CocoaMQTTClient {
    var host: String { get set }
    var port: UInt16 { get set }
    var clientID: String { get }
    var username: String? {get set}
    var password: String? {get set}
    var cleanSession: Bool {get set}
    var keepAlive: UInt16 {get set}
    var willMessage: CocoaMQTTWill? {get set}

    func connect() -> Bool
    func connect(timeout:TimeInterval) -> Bool
    func disconnect()
    func ping()
    
    func subscribe(_ topic: String, qos: CocoaMQTTQOS) -> UInt16
    func subscribe(_ topics: [(String, CocoaMQTTQOS)]) -> UInt16
    
    func unsubscribe(_ topic: String) -> UInt16
    func publish(_ topic: String, withString string: String, qos: CocoaMQTTQOS, retained: Bool, dup: Bool) -> UInt16
    func publish(_ message: CocoaMQTTMessage) -> UInt16
    
}

/**
 * MQTT Reader Delegate
 */
protocol CocoaMQTTReaderDelegate: class {
    func didReceiveConnAck(_ reader: CocoaMQTTReader, connack: UInt8)
    func didReceivePublish(_ reader: CocoaMQTTReader, message: CocoaMQTTMessage, id: UInt16)
    func didReceivePubAck(_ reader: CocoaMQTTReader, msgid: UInt16)
    func didReceivePubRec(_ reader: CocoaMQTTReader, msgid: UInt16)
    func didReceivePubRel(_ reader: CocoaMQTTReader, msgid: UInt16)
    func didReceivePubComp(_ reader: CocoaMQTTReader, msgid: UInt16)
    func didReceiveSubAck(_ reader: CocoaMQTTReader, msgid: UInt16)
    func didReceiveUnsubAck(_ reader: CocoaMQTTReader, msgid: UInt16)
    func didReceivePong(_ reader: CocoaMQTTReader)
}

extension Int {
    var MB: Int {
        return self * 1024 * 1024
    }
}

/**
 * Main CocoaMQTT Class
 *
 * - Note: GCDAsyncSocket need delegate to extend NSObject
 */
public class CocoaMQTT: NSObject, CocoaMQTTClient, CocoaMQTTDeliverProtocol {
    
    public weak var delegate: CocoaMQTTDelegate?
    
    public var host = "localhost"
    public var port: UInt16 = 1883
    public var clientID: String
    public var username: String?
    public var password: String?
    public var cleanSession = true
    public var willMessage: CocoaMQTTWill?
    public var backgroundOnSocket = true
    public var dispatchQueue = DispatchQueue.main
    
    public var connState = CocoaMQTTConnState.initial {
        didSet {
            delegate?.mqtt?(self, didStateChangeTo: connState)
            didChangeState(self, connState)
        }
    }
    
    // deliver
    private var deliver = CocoaMQTTDeliver()
    
    /// Re-deliver the un-acked messages
    public var deliverTimeout: Double {
        get { return deliver.retryTimeInterval }
        set { deliver.retryTimeInterval = newValue }
    }
    
    /// Message queue size. default 1000
    ///
    /// The new publishing messages of Qos1/Qos2 will be drop, if the quene is full
    public var messageQueueSize: UInt {
        get { return deliver.mqueueSize }
        set { deliver.mqueueSize = newValue }
    }
    
    /// In-flight window size. default 10
    public var inflightWindowSize: UInt {
        get { return deliver.inflightWindowSize }
        set { deliver.inflightWindowSize = newValue }
    }
    
    /// Keep alive time inerval
    public var keepAlive: UInt16 = 60
	private var aliveTimer: CocoaMQTTTimer?
    
    /// Enable auto-reconnect mechanism
    public var autoReconnect = false
    
    /// Reconnect time interval
    ///
    /// - note: This value will be increased with `autoReconnectTimeInterval *= 2`
    ///         if reconnect failed
    public var autoReconnectTimeInterval: UInt16 = 1 // starts from 1 second
    
    /// Maximum auto reconnect time interval
    ///
    /// The timer starts from `autoReconnectTimeInterval` second and grows exponentially until this value
    /// After that, it uses this value for subsequent requests.
    public var maxAutoReconnectTimeInterval: UInt16 = 128 // 128 seconds
    
    private var reconectTimeInterval: UInt16 = 0
    
    private var autoReconnTimer: CocoaMQTTTimer?
    private var disconnectExpectedly = false
    
    /// Console log level
    public var logLevel: CocoaMQTTLoggerLevel {
        get {
            return CocoaMQTTLogger.logger.minLevel
        }
        set {
            CocoaMQTTLogger.logger.minLevel = newValue
        }
    }
    
    /// Enable SSL connection
    public var enableSSL = false
    
    ///
    public var sslSettings: [String: NSObject]?
    
    /// Allow self-signed ca certificate.
    ///
    /// Default is false
    public var allowUntrustCACertificate = false
    
    /// The subscribed topics in current communication
    public var subscriptions: [String: CocoaMQTTQOS] = [:]
    
    fileprivate var subscriptionsWaitingAck: [UInt16: [(String, CocoaMQTTQOS)]] = [:]
    fileprivate var unsubscriptionsWaitingAck: [UInt16: String] = [:]
    
    /// Sending messages
    fileprivate var sendingMessages: [UInt16: CocoaMQTTMessage] = [:]

    /// Global message id
    fileprivate var gmid: UInt16 = 1
    fileprivate var socket = GCDAsyncSocket()
    fileprivate var reader: CocoaMQTTReader?
    
    // Closures
    public var didConnectAck: (CocoaMQTT, CocoaMQTTConnAck) -> Void = { _, _ in }
    public var didPublishMessage: (CocoaMQTT, CocoaMQTTMessage, UInt16) -> Void = { _, _, _ in }
    public var didPublishAck: (CocoaMQTT, UInt16) -> Void = { _, _ in }
    public var didReceiveMessage: (CocoaMQTT, CocoaMQTTMessage, UInt16) -> Void = { _, _, _ in }
    public var didSubscribeTopic: (CocoaMQTT, [String]) -> Void = { _, _ in }
    public var didUnsubscribeTopic: (CocoaMQTT, String) -> Void = { _, _ in }
    public var didPing: (CocoaMQTT) -> Void = { _ in }
    public var didReceivePong: (CocoaMQTT) -> Void = { _ in }
    public var didDisconnect: (CocoaMQTT, Error?) -> Void = { _, _ in }
    public var didReceiveTrust: (CocoaMQTT, SecTrust, @escaping (Bool) -> Swift.Void) -> Void = { _, _, _ in }
    public var didCompletePublish: (CocoaMQTT, UInt16) -> Void = { _, _ in }
    public var didChangeState: (CocoaMQTT, CocoaMQTTConnState) -> Void = { _, _ in }
    
    /// Initial client object
    ///
    /// - Parameters:
    ///   - clientID: Client Identifier
    ///   - host: The MQTT broker host domain or IP address. Default is "localhost"
    ///   - port: The MQTT service port of host. Default is 1883
    public init(clientID: String, host: String = "localhost", port: UInt16 = 1883) {
        self.clientID = clientID
        self.host = host
        self.port = port
        super.init()
        deliver.delegate = self
    }
    
    deinit {
		aliveTimer?.suspend()
        autoReconnTimer?.suspend()
        
        socket.delegate = nil
        socket.disconnect()
    }
    
    // MARK: CocoaMQTTDeliverProtocol
    func deliver(_ deliver: CocoaMQTTDeliver, wantToSend frame: CocoaMQTTFramePublish) {
        let msgid = frame.msgid!
        guard let message = sendingMessages[msgid] else {
            return
        }
        
        send(frame, tag: Int(msgid))
        
        delegate?.mqtt(self, didPublishMessage: message, id: msgid)
        didPublishMessage(self, message, msgid)
    }

    fileprivate func send(_ frame: CocoaMQTTFrame, tag: Int = 0) {
        var f = frame
        let data = f.data()
        socket.write(Data(bytes: data, count: data.count), withTimeout: -1, tag: tag)
    }

    fileprivate func sendConnectFrame() {
        let frame = CocoaMQTTFrameConnect(client: self)
        send(frame)
        reader!.start()
    }

    fileprivate func nextMessageID() -> UInt16 {
        if gmid == UInt16.max {
            gmid = 0
        }
        gmid += 1
        return gmid
    }

    fileprivate func puback(_ type: CocoaMQTTFrameType, msgid: UInt16) {
        var descr: String?
        switch type {
        case .puback:
            descr = "PUBACK"
        case .pubrec:
            descr = "PUBREC"
        case .pubrel:
            descr = "PUBREL"
        case .pubcomp:
            descr = "PUBCOMP"
        default: break
        }

        if descr != nil {
            printDebug("Send \(descr!), msgid: \(msgid)")
        }

        send(CocoaMQTTFramePubAck(type: type, msgid: msgid))
    }

    /// Connect to MQTT broker
    public func connect() -> Bool {
        return connect(timeout: -1)
    }
    
    /// Connect to MQTT broker
    public func connect(timeout: TimeInterval) -> Bool {
        socket.setDelegate(self, delegateQueue: dispatchQueue)
        reader = CocoaMQTTReader(socket: socket, delegate: self)
        do {
            if timeout > 0 {
                try socket.connect(toHost: self.host, onPort: self.port, withTimeout: timeout)
            } else {
                try socket.connect(toHost: self.host, onPort: self.port)
            }
            connState = .connecting
            return true
        } catch let error as NSError {
            printError("socket connect error: \(error.description)")
            return false
        }
    }
    
    /// Send a DISCONNECT packet to the broker then close the connection
    ///
    /// - Note: Only can be called from outside.
    ///         If you want to disconnect from inside framwork, call internal_disconnect()
    ///         disconnect expectedly
    public func disconnect() {
        disconnectExpectedly = true
        internal_disconnect()
    }
    
    /// Disconnect unexpectedly
    func internal_disconnect() {
        send(CocoaMQTTFrameDisconnect(), tag: -0xE0)
        socket.disconnect()
    }
    
    /// Send ping request to broker
    public func ping() {
        printDebug("ping")
        send(CocoaMQTTFramePing(), tag: -0xC0)
        self.delegate?.mqttDidPing(self)
        didPing(self)
    }

    @discardableResult
    public func publish(_ topic: String, withString string: String, qos: CocoaMQTTQOS = .qos1, retained: Bool = false, dup: Bool = false) -> UInt16 {
        // TODO: The duplicated flag must hidden for caller
        let message = CocoaMQTTMessage(topic: topic, string: string, qos: qos, retained: retained, dup: dup)
        return publish(message)
    }

    @discardableResult
    public func publish(_ message: CocoaMQTTMessage) -> UInt16 {
        let msgid: UInt16 = nextMessageID()
        // XXX: qos0 should not take msgid
        var frame = CocoaMQTTFramePublish(msgid: msgid, topic: message.topic, payload: message.payload)
        frame.qos = message.qos.rawValue
        frame.retained = message.retained
        frame.dup = message.dup
        
        // Push frame to deliver message queue
        _ = deliver.add(frame)
        
        // XXX: For process safety
        dispatchQueue.async {
            self.sendingMessages[msgid] = message
        }
        
        return msgid
    }

    @discardableResult
    public func subscribe(_ topic: String, qos: CocoaMQTTQOS = .qos1) -> UInt16 {
        return subscribe([(topic, qos)])
    }
    
    @discardableResult
    public func subscribe(_ topics: [(String, CocoaMQTTQOS)]) -> UInt16 {
        let msgid = nextMessageID()
        let frame = CocoaMQTTFrameSubscribe(msgid: msgid, topics: topics)
        send(frame, tag: Int(msgid))
        subscriptionsWaitingAck[msgid] = topics
        return msgid
    }

    @discardableResult
    public func unsubscribe(_ topic: String) -> UInt16 {
        let msgid = nextMessageID()
        let frame = CocoaMQTTFrameUnsubscribe(msgid: msgid, topic: topic)
        unsubscriptionsWaitingAck[msgid] = topic
        send(frame, tag: Int(msgid))
        return msgid
    }
}

// MARK: - GCDAsyncSocketDelegate
extension CocoaMQTT: GCDAsyncSocketDelegate {
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        printInfo("Connected to \(host) : \(port)")
        
        #if os(iOS)
            if backgroundOnSocket {
                sock.perform { sock.enableBackgroundingOnSocket() }
            }
        #endif
        
        if enableSSL {
            var setting = sslSettings ?? [:]
            if allowUntrustCACertificate {
                setting[GCDAsyncSocketManuallyEvaluateTrust as String] = NSNumber(value: true)
            }
            sock.startTLS(setting)
        } else {
            sendConnectFrame()
        }
    }

    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        printDebug("didReceiveTrust")
        
        delegate?.mqtt?(self, didReceive: trust, completionHandler: completionHandler)
        didReceiveTrust(self, trust, completionHandler)
    }

    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        printDebug("socketDidSecure")
        sendConnectFrame()
    }

    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        printDebug("Socket write message with tag: \(tag)")
    }

    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        let etag = CocoaMQTTReadTag(rawValue: tag)!
        var bytes = [UInt8]([0])
        switch etag {
        case CocoaMQTTReadTag.header:
            data.copyBytes(to: &bytes, count: 1)
            reader!.headerReady(bytes[0])
        case CocoaMQTTReadTag.length:
            data.copyBytes(to: &bytes, count: 1)
            reader!.lengthReady(bytes[0])
        case CocoaMQTTReadTag.payload:
            reader!.payloadReady(data)
        }
    }

    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        // Clean up
        socket.delegate = nil
        connState = .disconnected
        delegate?.mqttDidDisconnect(self, withError: err)
        didDisconnect(self, err)
        
        if disconnectExpectedly {
            connState = .initial
        } else if autoReconnect {
            if reconectTimeInterval == 0 {
                reconectTimeInterval = autoReconnectTimeInterval
            }
            
            // Start reconnector once socket error occuried
            printInfo("Try reconnect to server after \(reconectTimeInterval)s")
            autoReconnTimer = CocoaMQTTTimer.after(Double(reconectTimeInterval), { [weak self] in
                guard let self = self else { return }
                if self.reconectTimeInterval < self.maxAutoReconnectTimeInterval {
                    self.reconectTimeInterval *= 2
                } else {
                    self.reconectTimeInterval = self.maxAutoReconnectTimeInterval
                }
                _ = self.connect()
            })
        }
    }
}

// MARK: - CocoaMQTTReaderDelegate
extension CocoaMQTT: CocoaMQTTReaderDelegate {
    func didReceiveConnAck(_ reader: CocoaMQTTReader, connack: UInt8) {
        printDebug("CONNACK Received: \(connack)")

        let ack: CocoaMQTTConnAck
        switch connack {
        case 0:
            ack = .accept
            connState = .connected
        case 1...5:
            ack = CocoaMQTTConnAck(rawValue: connack)!
            internal_disconnect()
        case _ where connack > 5:
            ack = .reserved
            internal_disconnect()
        default:
            internal_disconnect()
            return
        }

        // TODO: how to handle the cleanSession = false & auto-reconnect
        if cleanSession {
            deliver.cleanAll()
        }

        delegate?.mqtt(self, didConnectAck: ack)
        didConnectAck(self, ack)
        
        // reset auto-reconnect state
        if ack == CocoaMQTTConnAck.accept {
            reconectTimeInterval = 0
            autoReconnTimer = nil
            disconnectExpectedly = false
        }
        
        // keep alive
        if ack == CocoaMQTTConnAck.accept {
            let interval = Double(keepAlive <= 0 ? 60: keepAlive)
            self.aliveTimer = CocoaMQTTTimer.every(interval) { [weak self] in
                guard let weakSelf = self else {return}
                if weakSelf.connState == .connected {
                    weakSelf.ping()
                } else {
                    weakSelf.aliveTimer = nil
                }
            }
        }
    }

    func didReceivePublish(_ reader: CocoaMQTTReader, message: CocoaMQTTMessage, id: UInt16) {
        printInfo("PUBLISH Received from \(message.topic)")
        
        delegate?.mqtt(self, didReceiveMessage: message, id: id)
        didReceiveMessage(self, message, id)
        
        if message.qos == CocoaMQTTQOS.qos1 {
            puback(CocoaMQTTFrameType.puback, msgid: id)
        } else if message.qos == CocoaMQTTQOS.qos2 {
            puback(CocoaMQTTFrameType.pubrec, msgid: id)
        }
    }

    func didReceivePubAck(_ reader: CocoaMQTTReader, msgid: UInt16) {
        printDebug("PUBACK Received: \(msgid)")
        
        deliver.sendSuccess(withMsgid: msgid)
        delegate?.mqtt(self, didPublishAck: msgid)
        didPublishAck(self, msgid)
    }
    
    func didReceivePubRec(_ reader: CocoaMQTTReader, msgid: UInt16) {
        printDebug("PUBREC Received: \(msgid)")

        puback(CocoaMQTTFrameType.pubrel, msgid: msgid)
    }

    func didReceivePubRel(_ reader: CocoaMQTTReader, msgid: UInt16) {
        printDebug("PUBREL Received: \(msgid)")

        puback(CocoaMQTTFrameType.pubcomp, msgid: msgid)
    }

    func didReceivePubComp(_ reader: CocoaMQTTReader, msgid: UInt16) {
        printDebug("PUBCOMP Received: \(msgid)")

        deliver.sendSuccess(withMsgid: msgid)
        delegate?.mqtt?(self, didPublishComplete: msgid)
        didCompletePublish(self, msgid)
    }

    func didReceiveSubAck(_ reader: CocoaMQTTReader, msgid: UInt16) {
        printDebug("SUBACK Received: \(msgid)")
        
        guard let topicsAndQos = subscriptionsWaitingAck.removeValue(forKey: msgid) else {
            printWarning("UNEXPECT SUBACK Received: \(msgid)")
            return
        }
        
        var topics: [String] = []
        for (topic, qos) in topicsAndQos {
            // FIXME: should update qos with server granted
            subscriptions[topic] = qos
            topics.append(topic)
        }
        
        delegate?.mqtt(self, didSubscribeTopic: topics)
        didSubscribeTopic(self, topics)
    }

    func didReceiveUnsubAck(_ reader: CocoaMQTTReader, msgid: UInt16) {
        printDebug("UNSUBACK Received: \(msgid)")
        
        guard let topic = unsubscriptionsWaitingAck.removeValue(forKey: msgid) else {
            printWarning("UNEXPECT UNSUBACK Received: \(msgid)")
            return
        }
        
        for (t, _) in subscriptions {
            if t == topic {
                subscriptions.removeValue(forKey: t)
                break
            }
        }
        delegate?.mqtt(self, didUnsubscribeTopic: topic)
        didUnsubscribeTopic(self, topic)
    }

    func didReceivePong(_ reader: CocoaMQTTReader) {
        printDebug("PONG Received")

        delegate?.mqttDidReceivePong(self)
        didReceivePong(self)
    }
}

class CocoaMQTTReader {
    private var socket: GCDAsyncSocket
    private var header: UInt8 = 0
    private var length: UInt = 0
    private var data: [UInt8] = []
    private var multiply = 1
    private weak var delegate: CocoaMQTTReaderDelegate?
    private var timeout = 30000

    init(socket: GCDAsyncSocket, delegate: CocoaMQTTReaderDelegate?) {
        self.socket = socket
        self.delegate = delegate
    }

    func start() {
        readHeader()
    }

    func headerReady(_ header: UInt8) {
        printDebug("reader header ready: \(header) ")

        self.header = header
        readLength()
    }

    func lengthReady(_ byte: UInt8) {
        length += (UInt)((Int)(byte & 127) * multiply)
        // done
        if byte & 0x80 == 0 {
            if length == 0 {
                frameReady()
            } else {
                readPayload()
            }
        // more
        } else {
            multiply *= 128
            readLength()
        }
    }

    func payloadReady(_ data: Data) {
        self.data = [UInt8](repeating: 0, count: data.count)
        data.copyBytes(to: &(self.data), count: data.count)
        frameReady()
    }

    private func readHeader() {
        reset()
        socket.readData(toLength: 1, withTimeout: -1, tag: CocoaMQTTReadTag.header.rawValue)
    }

    private func readLength() {
        socket.readData(toLength: 1, withTimeout: TimeInterval(timeout), tag: CocoaMQTTReadTag.length.rawValue)
    }

    private func readPayload() {
        socket.readData(toLength: length, withTimeout: TimeInterval(timeout), tag: CocoaMQTTReadTag.payload.rawValue)
    }

    private func frameReady() {
        // handle frame
        guard let frameType = CocoaMQTTFrameType(rawValue: UInt8(header & 0xF0)) else {
            printError("Abort! Received unknown frame type!")
            return
        }
        
        switch frameType {
        case .connack:
            delegate?.didReceiveConnAck(self, connack: data[1])
        case .publish:
            let (msgid, message) = unpackPublish()
            if message != nil {
                delegate?.didReceivePublish(self, message: message!, id: msgid)
            }
        case .puback:
            delegate?.didReceivePubAck(self, msgid: msgid(data))
        case .pubrec:
            delegate?.didReceivePubRec(self, msgid: msgid(data))
        case .pubrel:
            delegate?.didReceivePubRel(self, msgid: msgid(data))
        case .pubcomp:
            delegate?.didReceivePubComp(self, msgid: msgid(data))
        case .suback:
            // TODO: We should parse the suback to ge granted qos level
            delegate?.didReceiveSubAck(self, msgid: msgid(data))
        case .unsuback:
            delegate?.didReceiveUnsubAck(self, msgid: msgid(data))
        case .pingresp:
            delegate?.didReceivePong(self)
        default:
            break
        }

        readHeader()
    }

    private func unpackPublish() -> (UInt16, CocoaMQTTMessage?) {
        var frame = CocoaMQTTFramePublish(header: header, data: data)
        frame.unpack()
        // if unpack fail
        if frame.msgid == nil {
            return (0, nil)
        }
        let msgid = frame.msgid!
        let qos = CocoaMQTTQOS(rawValue: frame.qos)!
        let message = CocoaMQTTMessage(topic: frame.topic!, payload: frame.payload, qos: qos, retained: frame.retained, dup: frame.dup)
        return (msgid, message)
    }

    private func msgid(_ bytes: [UInt8]) -> UInt16 {
        if bytes.count < 2 { return 0 }
        return UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }

    private func reset() {
        length = 0
        multiply = 1
        header = 0
        data = []
    }
}
