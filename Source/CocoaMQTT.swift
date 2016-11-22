//
//  CocoaMQTT.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import MSWeakTimer


/**
 * QOS
 */
public enum CocoaMQTTQOS: UInt8 {
    case qos0 = 0
    case qos1
    case qos2
}

/**
 * Connection State
 */
public enum CocoaMQTTConnState: UInt8 {
    case initial = 0
    case connecting
    case connected
    case disconnected
}

/**
 * Conn Ack
 */
@objc public enum CocoaMQTTConnAck: UInt8 {
    case accept  = 0
    case unacceptableProtocolVersion
    case identifierRejected
    case serverUnavailable
    case badUsernameOrPassword
    case notAuthorized
    case reserved
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
    func mqtt(_ mqtt: CocoaMQTT, didConnect host: String, port: Int)
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16)
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16)
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 )
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String)
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String)
    func mqttDidPing(_ mqtt: CocoaMQTT)
    func mqttDidReceivePong(_ mqtt: CocoaMQTT)
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?)
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void)
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
    func publish(_ topic: String, withString string: String, qos: CocoaMQTTQOS, retained: Bool, dup: Bool) -> UInt16
    func publish(_ message: CocoaMQTTMessage) -> UInt16
    func subscribe(_ topic: String, qos: CocoaMQTTQOS) -> UInt16
    func unsubscribe(_ topic: String) -> UInt16
    func ping()
    func disconnect()
}

/**
 * MQTT Reader Delegate
 */
protocol CocoaMQTTReaderDelegate {
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

/**
 * Main CocoaMQTT Class
 *
 * Notice: GCDAsyncSocket need delegate to extend NSObject
 */
open class CocoaMQTT: NSObject, CocoaMQTTClient {
    open var host = "localhost"
    open var port: UInt16 = 1883
    open var clientID: String
    open var username: String?
    open var password: String?
    open var secureMQTT = false
    open var cleanSession = true
    open var keepAlive: UInt16 = 60
    open var willMessage: CocoaMQTTWill?
    open weak var delegate: CocoaMQTTDelegate?
    open var backgroundOnSocket = false
    open var connState = CocoaMQTTConnState.initial
    
    // ssl
    open var enableSSL = false
    open var sslSettings: [String: NSObject]?
    
    // published messages
    open var messages: [UInt16: CocoaMQTTMessage] = [:]
    // subscribed topics
    open var subscriptions: [UInt16: String] = [:]

    // global message id
    var gmid: UInt16 = 1
    var aliveTimer: MSWeakTimer?
    var socket: GCDAsyncSocket?
    var reader: CocoaMQTTReader?

    public init(clientID: String, host: String = "localhost", port: UInt16 = 1883) {
        self.clientID = clientID
        self.host = host
        self.port = port
    }

    fileprivate func send(_ frame: CocoaMQTTFrame, tag: Int = 0) {
        let data = frame.data()
        socket!.write(Data(bytes: data, count: data.count), withTimeout: -1, tag: tag)
    }

    fileprivate func sendConnectFrame() {
        let frame = CocoaMQTTFrameConnect(client: self)
        send(frame)
        reader!.start()
        delegate?.mqtt(self, didConnect: host, port: Int(port))
    }

    @objc fileprivate func aliveTimerFired() {
        if connState == .connected {
            ping()
        } else {
            aliveTimer?.invalidate()
        }
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

        #if DEBUG
            if descr != nil {
                NSLog("CocoaMQTT: Send \(descr!), msgid: \(msgid)")
            }
        #endif

        send(CocoaMQTTFramePubAck(type: type, msgid: msgid))
    }

    @discardableResult
    open func connect() -> Bool {
        socket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
        reader = CocoaMQTTReader(socket: socket!, delegate: self)
        do {
            try socket!.connect(toHost: self.host, onPort: self.port)
            connState = .connecting
            return true
        } catch let error as NSError {
            #if DEBUG
                NSLog("CocoaMQTT: socket connect error: \(error.description)")
            #endif
            return false
        }
    }

    @discardableResult
    open func publish(_ topic: String, withString string: String, qos: CocoaMQTTQOS = .qos1, retained: Bool = false, dup: Bool = false) -> UInt16 {
        let message = CocoaMQTTMessage(topic: topic, string: string, qos: qos, retained: retained, dup: dup)
        return publish(message)
    }

    @discardableResult
    open func publish(_ message: CocoaMQTTMessage) -> UInt16 {
        let msgid: UInt16 = nextMessageID()
        let frame = CocoaMQTTFramePublish(msgid: msgid, topic: message.topic, payload: message.payload)
        frame.qos = message.qos.rawValue
        frame.retained = message.retained
        frame.dup = message.dup
        send(frame, tag: Int(msgid))

        if message.qos != CocoaMQTTQOS.qos0 {
            messages[msgid] = message //cache
        }

        delegate?.mqtt(self, didPublishMessage: message, id: msgid)

        return msgid
    }

    @discardableResult
    open func subscribe(_ topic: String, qos: CocoaMQTTQOS = .qos1) -> UInt16 {
        let msgid = nextMessageID()
        let frame = CocoaMQTTFrameSubscribe(msgid: msgid, topic: topic, reqos: qos.rawValue)
        send(frame, tag: Int(msgid))
        subscriptions[msgid] = topic
        return msgid
    }

    @discardableResult
    open func unsubscribe(_ topic: String) -> UInt16 {
        let msgid = nextMessageID()
        let frame = CocoaMQTTFrameUnsubscribe(msgid: msgid, topic: topic)
        subscriptions[msgid] = topic
        send(frame, tag: Int(msgid))
        return msgid
    }

    open func ping() {
        send(CocoaMQTTFrame(type: CocoaMQTTFrameType.pingreq), tag: -0xC0)
        self.delegate?.mqttDidPing(self)
    }

    open func disconnect() {
        send(CocoaMQTTFrame(type: CocoaMQTTFrameType.disconnect), tag: -0xE0)
        socket!.disconnect()
    }
}

// MARK: - GCDAsyncSocketDelegate
extension CocoaMQTT: GCDAsyncSocketDelegate {
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: connected to \(host) : \(port)")
        #endif
        
        #if TARGET_OS_IPHONE
            if backgroundOnSocket {
                sock.performBlock { sock.enableBackgroundingOnSocket() }
            }
        #endif
        
        if enableSSL {
            if sslSettings == nil {
                sock.startTLS(nil)
            } else {
                sslSettings![GCDAsyncSocketManuallyEvaluateTrust as String] = NSNumber(value: true)
                sock.startTLS(sslSettings!)
            }
        } else {
            sendConnectFrame()
        }
    }

    public func socket(_ sock: GCDAsyncSocket, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Swift.Void) {
        #if DEBUG
            NSLog("CocoaMQTT: didReceiveTrust")
        #endif
        
        delegate?.mqtt!(self, didReceive: trust, completionHandler: completionHandler)
    }

    public func socketDidSecure(_ sock: GCDAsyncSocket) {
        #if DEBUG
            NSLog("CocoaMQTT: socketDidSecure")
        #endif
        sendConnectFrame()
    }

    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        #if DEBUG
            NSLog("CocoaMQTT: Socket write message with tag: \(tag)")
        #endif
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
        connState = .disconnected
        delegate?.mqttDidDisconnect(self, withError: err)
    }
}

// MARK: - CocoaMQTTReaderDelegate
extension CocoaMQTT: CocoaMQTTReaderDelegate {
    func didReceiveConnAck(_ reader: CocoaMQTTReader, connack: UInt8) {
        #if DEBUG
            NSLog("CocoaMQTT: CONNACK Received: \(connack)")
        #endif

        let ack: CocoaMQTTConnAck
        switch connack {
        case 0:
            ack = .accept
            connState = .connected
        case 1...5:
            ack = CocoaMQTTConnAck(rawValue: connack)!
            disconnect()
        case _ where connack > 5:
            ack = .reserved
            disconnect()
        default:
            disconnect()
            return
        }

        delegate?.mqtt(self, didConnectAck: ack)

        // keep alive
        if ack == CocoaMQTTConnAck.accept && keepAlive > 0 {
            aliveTimer = MSWeakTimer.scheduledTimer(
                withTimeInterval: TimeInterval(keepAlive),
                target: self,
                selector: #selector(CocoaMQTT.aliveTimerFired),
                userInfo: nil,
                repeats: true,
                dispatchQueue: DispatchQueue.main)
        }
    }

    func didReceivePublish(_ reader: CocoaMQTTReader, message: CocoaMQTTMessage, id: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: PUBLISH Received from \(message.topic)")
        #endif
        delegate?.mqtt(self, didReceiveMessage: message, id: id)
        if message.qos == CocoaMQTTQOS.qos1 {
            puback(CocoaMQTTFrameType.puback, msgid: id)
        } else if message.qos == CocoaMQTTQOS.qos2 {
            puback(CocoaMQTTFrameType.pubrec, msgid: id)
        }
    }

    func didReceivePubAck(_ reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: PUBACK Received: \(msgid)")
        #endif

        messages.removeValue(forKey: msgid)
        delegate?.mqtt(self, didPublishAck: msgid)
    }

    func didReceivePubRec(_ reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: PUBREC Received: \(msgid)")
        #endif

        puback(CocoaMQTTFrameType.pubrel, msgid: msgid)
    }

    func didReceivePubRel(_ reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: PUBREL Received: \(msgid)")
        #endif

        puback(CocoaMQTTFrameType.pubcomp, msgid: msgid)
    }

    func didReceivePubComp(_ reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: PUBCOMP Received: \(msgid)")
        #endif

        messages.removeValue(forKey: msgid)
    }

    func didReceiveSubAck(_ reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: SUBACK Received: \(msgid)")
        #endif

        if let topic = subscriptions.removeValue(forKey: msgid) {
            delegate?.mqtt(self, didSubscribeTopic: topic)
        }
    }

    func didReceiveUnsubAck(_ reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: UNSUBACK Received: \(msgid)")
        #endif

        if let topic = subscriptions.removeValue(forKey: msgid) {
            delegate?.mqtt(self, didUnsubscribeTopic: topic)
        }
    }

    func didReceivePong(_ reader: CocoaMQTTReader) {
        #if DEBUG
            NSLog("CocoaMQTT: PONG Received")
        #endif

        delegate?.mqttDidReceivePong(self)
    }
}

class CocoaMQTTReader {
    private var socket: GCDAsyncSocket
    private var header: UInt8 = 0
    private var length: UInt = 0
    private var data: [UInt8] = []
    private var multiply = 1
    private var delegate: CocoaMQTTReaderDelegate
    private var timeout = 30000

    init(socket: GCDAsyncSocket, delegate: CocoaMQTTReaderDelegate) {
        self.socket = socket
        self.delegate = delegate
    }

    func start() {
        readHeader()
    }

    func headerReady(_ header: UInt8) {
        #if DEBUG
        NSLog("CocoaMQTTReader: header ready: \(header) ")
        #endif

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
        let frameType = CocoaMQTTFrameType(rawValue: UInt8(header & 0xF0))!
        switch frameType {
        case .connack:
            delegate.didReceiveConnAck(self, connack: data[1])
        case .publish:
            let (msgid, message) = unpackPublish()
            delegate.didReceivePublish(self, message: message, id: msgid)
        case .puback:
            delegate.didReceivePubAck(self, msgid: msgid(data))
        case .pubrec:
            delegate.didReceivePubRec(self, msgid: msgid(data))
        case .pubrel:
            delegate.didReceivePubRel(self, msgid: msgid(data))
        case .pubcomp:
            delegate.didReceivePubComp(self, msgid: msgid(data))
        case .suback:
            delegate.didReceiveSubAck(self, msgid: msgid(data))
        case .unsuback:
            delegate.didReceiveUnsubAck(self, msgid: msgid(data))
        case .pingresp:
            delegate.didReceivePong(self)
        default:
            break
        }

        readHeader()
    }

    private func unpackPublish() -> (UInt16, CocoaMQTTMessage) {
        let frame = CocoaMQTTFramePublish(header: header, data: data)
        frame.unpack()
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
