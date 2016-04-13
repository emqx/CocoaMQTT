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
 * MQTT Delegate
 */
public protocol CocoaMQTTDelegate : class {

    /**
     * MQTT connected with server
     */
    
    func mqtt(mqtt: CocoaMQTT, didConnect host: String, port: Int)

    func mqtt(mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)

    func mqtt(mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16)
    
    func mqtt(mqtt: CocoaMQTT, didPublishAck id: UInt16)

    func mqtt(mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 )

    func mqtt(mqtt: CocoaMQTT, didSubscribeTopic topic: String)

    func mqtt(mqtt: CocoaMQTT, didUnsubscribeTopic topic: String)
    
    func mqttDidPing(mqtt: CocoaMQTT)

    func mqttDidReceivePong(mqtt: CocoaMQTT)

    func mqttDidDisconnect(mqtt: CocoaMQTT, withError err: NSError?)

}

/**
 * Blueprint of the MQTT client
 */
public protocol CocoaMQTTClient {

    var host: String { get set }

    var port: UInt16 { get set }

    var clientId: String { get }

    var username: String? {get set}

    var password: String? {get set}
    
    var secureMQTT: Bool {get set}

    var cleanSess: Bool {get set}

    var keepAlive: UInt16 {get set}

    var willMessage: CocoaMQTTWill? {get set}

    func connect() -> Bool

    func publish(topic: String, withString string: String, qos: CocoaMQTTQOS, retained: Bool, dup: Bool) -> UInt16

    func publish(message: CocoaMQTTMessage) -> UInt16

    func subscribe(topic: String, qos: CocoaMQTTQOS) -> UInt16

    func unsubscribe(topic: String) -> UInt16

    func ping()

    func disconnect()

}


/**
 * QOS
 */
public enum CocoaMQTTQOS: UInt8 {

    case QOS0 = 0

    case QOS1

    case QOS2
}

/**
 * Connection State
 */
public enum CocoaMQTTConnState: UInt8 {

    case INIT = 0

    case CONNECTING

    case CONNECTED

    case DISCONNECTED
}


/**
 * Conn Ack
 */
public enum CocoaMQTTConnAck: UInt8 {

    case ACCEPT  = 0

    case PROTO_VER

    case INVALID_ID

    case SERVER

    case CREDENTIALS

    case AUTH

}

/**
 * asyncsocket read tag
 */
enum CocoaMQTTReadTag: Int {

    case TAG_HEADER = 0

    case TAG_LENGTH

    case TAG_PAYLOAD

}

/**
 * Main CocoaMQTT Class
 *
 * Notice: GCDAsyncSocket need delegate to extend NSObject
 */
public class CocoaMQTT: NSObject, CocoaMQTTClient, GCDAsyncSocketDelegate, CocoaMQTTReaderDelegate {

    //client variables

    public var host = "localhost"

    public var port: UInt16 = 1883

    public var clientId: String

    public var username: String?

    public var password: String?
    
    public var secureMQTT: Bool = false
    
    public var backgroundOnSocket: Bool = false

    public var cleanSess: Bool = true

    //keep alive

    public var keepAlive: UInt16 = 60

    var aliveTimer: MSWeakTimer?

    //will message

    public var willMessage: CocoaMQTTWill?

    //delegate weak??

    public weak var delegate: CocoaMQTTDelegate?

    //socket and connection

    public var connState = CocoaMQTTConnState.INIT

    var socket: GCDAsyncSocket?

    var reader: CocoaMQTTReader?

    //global message id
    
    var gmid: UInt16 = 1

    //subscribed topics
    
    var subscriptions = Dictionary<UInt16, String>()

    //published messages
    
    public var messages = Dictionary<UInt16, CocoaMQTTMessage>()

    public init(clientId: String, host: String = "localhost", port: UInt16 = 1883) {
        self.clientId = clientId
        self.host = host
        self.port = port
    }

    //API Functions

    public func connect() -> Bool {
        socket = GCDAsyncSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
        reader = CocoaMQTTReader(socket: socket!, delegate: self)
        do {
            try socket!.connectToHost(self.host, onPort: self.port)
            connState = CocoaMQTTConnState.CONNECTING
            return true
        } catch let error as NSError {
            #if DEBUG
            NSLog("CocoaMQTT: socket connect error: \(error.description)")
            #endif
            return false
        }
    }

    public func publish(topic: String, withString string: String, qos: CocoaMQTTQOS = .QOS1, retained: Bool = false, dup: Bool = false) -> UInt16 {
        let message = CocoaMQTTMessage(topic: topic, string: string, qos: qos, retained: retained, dup: dup)
        return publish(message)
    }

    public func publish(message: CocoaMQTTMessage) -> UInt16 {
        let msgId: UInt16 = _nextMessageId()
        let frame = CocoaMQTTFramePublish(msgid: msgId, topic: message.topic, payload: message.payload)
        frame.qos = message.qos.rawValue
        frame.retained = message.retained
        frame.dup = message.dup
        send(frame, tag: Int(msgId))
        if message.qos != CocoaMQTTQOS.QOS0 {
            messages[msgId] = message //cache
        }
        
        delegate?.mqtt(self, didPublishMessage: message, id: msgId)
        
        return msgId
    }

    public func subscribe(topic: String, qos: CocoaMQTTQOS = .QOS1) -> UInt16 {
        let msgId = _nextMessageId()
        let frame = CocoaMQTTFrameSubscribe(msgid: msgId, topic: topic, reqos: qos.rawValue)
        send(frame, tag: Int(msgId))
        subscriptions[msgId] = topic //cache?
        return msgId
    }

    public func unsubscribe(topic: String) -> UInt16 {
        let msgId = _nextMessageId()
        let frame = CocoaMQTTFrameUnsubscribe(msgid: msgId, topic: topic)
        subscriptions[msgId] = topic //cache
        send(frame, tag: Int(msgId))
        return msgId
    }

    public func ping() {
        send(CocoaMQTTFrame(type: CocoaMQTTFrameType.PINGREQ), tag: -0xC0)
        self.delegate?.mqttDidPing(self)
    }

    public func disconnect() {
        send(CocoaMQTTFrame(type: CocoaMQTTFrameType.DISCONNECT), tag: -0xE0)
        socket!.disconnect()
    }

    func send(frame: CocoaMQTTFrame, tag: Int = 0) {
        let data = frame.data()
        socket!.writeData(NSData(bytes: data, length: data.count), withTimeout: -1, tag: tag)
    }

    //AsyncSocket Delegate

    public func socket(sock: GCDAsyncSocket!, didConnectToHost host: String!, port: UInt16) {
        #if DEBUG
            NSLog("CocoaMQTT: connected to \(host) : \(port)")
        #endif
        connState = CocoaMQTTConnState.CONNECTED
        
        #if TARGET_OS_IPHONE
        if backgroundOnSocket {
            sock.performBlock { sock.enableBackgroundingOnSocket() }
        }
        #endif
        
        if secureMQTT {
            #if DEBUG
                sock.startTLS(["GCDAsyncSocketManuallyEvaluateTrust": true, kCFStreamSSLPeerName: self.host])
            #else
                sock.startTLS([kCFStreamSSLPeerName: self.host])
            #endif
        } else {
            let frame = CocoaMQTTFrameConnect(client: self)
            send(frame)
            reader!.start()
        }
        
        delegate?.mqtt(self, didConnect: host, port: Int(port))
    }
    
    public func socket(sock: GCDAsyncSocket!, didReceiveTrust trust: SecTrust!, completionHandler: ((Bool) -> Void)!) {
        #if DEBUG
            NSLog("CocoaMQTT: didReceiveTrust")
        #endif
        completionHandler(true)
    }
    
    public func socketDidSecure(sock: GCDAsyncSocket!) {
        #if DEBUG
            NSLog("CocoaMQTT: socketDidSecure")
        #endif
        let frame = CocoaMQTTFrameConnect(client: self)
        send(frame)
        reader!.start()
    }

    public func socket(sock: GCDAsyncSocket!, didWriteDataWithTag tag: Int) {
        #if DEBUG
        NSLog("CocoaMQTT: Socket write message with tag: \(tag)")
        #endif
    }

    public func socket(sock: GCDAsyncSocket!, didReadData data: NSData!, withTag tag: Int) {
        let etag: CocoaMQTTReadTag = CocoaMQTTReadTag(rawValue: tag)!
        var bytes = [UInt8]([0])
        switch etag {
        case CocoaMQTTReadTag.TAG_HEADER:
            data.getBytes(&bytes, length: 1)
            reader!.headerReady(bytes[0])
        case CocoaMQTTReadTag.TAG_LENGTH:
            data.getBytes(&bytes, length: 1)
            reader!.lengthReady(bytes[0])
        case CocoaMQTTReadTag.TAG_PAYLOAD:
            reader!.payloadReady(data)
        }
    }

    public func socketDidDisconnect(sock: GCDAsyncSocket!, withError err: NSError!) {
        connState = CocoaMQTTConnState.DISCONNECTED
        delegate?.mqttDidDisconnect(self, withError: err)
    }

    //CocoaMQTTReader Delegate

    public func didReceiveConnAck(reader: CocoaMQTTReader, connack: UInt8) {
        connState = CocoaMQTTConnState.CONNECTED
        #if DEBUG
        NSLog("CocoaMQTT: CONNACK Received: \(connack)")
        #endif
 
        let ack = CocoaMQTTConnAck(rawValue: connack)!
        delegate?.mqtt(self, didConnectAck: ack)
        
        //keep alive
        if ack == CocoaMQTTConnAck.ACCEPT && keepAlive > 0 {
            aliveTimer = MSWeakTimer.scheduledTimerWithTimeInterval(
                NSTimeInterval(keepAlive),
                target: self,
                selector: #selector(CocoaMQTT._aliveTimerFired),
                userInfo: nil,
                repeats: true,
                dispatchQueue: dispatch_get_main_queue())
        }
    }

    func _aliveTimerFired() {
        if connState == CocoaMQTTConnState.CONNECTED {
            ping()
        } else {
            aliveTimer?.invalidate()
        }
    }

    func didReceivePublish(reader: CocoaMQTTReader, message: CocoaMQTTMessage, id: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: PUBLISH Received from \(message.topic)")
        #endif
        delegate?.mqtt(self, didReceiveMessage: message, id: id)
        if message.qos == CocoaMQTTQOS.QOS1 {
            _puback(CocoaMQTTFrameType.PUBACK, msgid: id)
        } else if message.qos == CocoaMQTTQOS.QOS2 {
            _puback(CocoaMQTTFrameType.PUBREC, msgid: id)
        }
    }

    func _puback(type: CocoaMQTTFrameType, msgid: UInt16) {
        var descr: String?
        switch type {
        case .PUBACK: descr = "PUBACK"
        case .PUBREC: descr = "PUBREC"
        case .PUBREL: descr = "PUBREL"
        case .PUBCOMP: descr = "PUBCOMP"
        default: assert(false)
        }
        #if DEBUG
        if descr != nil {
            NSLog("CocoaMQTT: Send \(descr!), msgid: \(msgid)")
        }
        #endif
        send(CocoaMQTTFramePubAck(type: type, msgid: msgid))
    }

    func didReceivePubAck(reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: PUBACK Received: \(msgid)")
        #endif
        messages.removeValueForKey(msgid)
        delegate?.mqtt(self, didPublishAck: msgid)
    }

    func didReceivePubRec(reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: PUBREC Received: \(msgid)")
        #endif
        _puback(CocoaMQTTFrameType.PUBREL, msgid: msgid)
    }

    func didReceivePubRel(reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: PUBREL Received: \(msgid)")
        #endif
        if let message = messages[msgid] {
            messages.removeValueForKey(msgid)
            delegate?.mqtt(self, didPublishMessage: message, id: msgid)
        }
        _puback(CocoaMQTTFrameType.PUBCOMP, msgid: msgid)
    }

    func didReceivePubComp(reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: PUBCOMP Received: \(msgid)")
        #endif
    }

    func didReceiveSubAck(reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: SUBACK Received: \(msgid)")
        #endif
        if let topic = subscriptions.removeValueForKey(msgid) {
            delegate?.mqtt(self, didSubscribeTopic: topic)
        }
    }

    func didReceiveUnsubAck(reader: CocoaMQTTReader, msgid: UInt16) {
        #if DEBUG
        NSLog("CocoaMQTT: UNSUBACK Received: \(msgid)")
        #endif
        if let topic = subscriptions.removeValueForKey(msgid) {
            delegate?.mqtt(self, didUnsubscribeTopic: topic)
        }
    }

    func didReceivePong(reader: CocoaMQTTReader) {
        #if DEBUG
        NSLog("CocoaMQTT: PONG Received")
        #endif
        delegate?.mqttDidReceivePong(self)
    }

    func _nextMessageId() -> UInt16 {
        let id = self.gmid++
        if id >= UInt16.max { gmid = 1 }
        return id
    }

}

/**
 * MQTT Reader Delegate
 */
protocol CocoaMQTTReaderDelegate {

    func didReceiveConnAck(reader: CocoaMQTTReader, connack: UInt8)

    func didReceivePublish(reader: CocoaMQTTReader, message: CocoaMQTTMessage, id: UInt16)

    func didReceivePubAck(reader: CocoaMQTTReader, msgid: UInt16)

    func didReceivePubRec(reader: CocoaMQTTReader, msgid: UInt16)

    func didReceivePubRel(reader: CocoaMQTTReader, msgid: UInt16)

    func didReceivePubComp(reader: CocoaMQTTReader, msgid: UInt16)

    func didReceiveSubAck(reader: CocoaMQTTReader, msgid: UInt16)

    func didReceiveUnsubAck(reader: CocoaMQTTReader, msgid: UInt16)

    func didReceivePong(reader: CocoaMQTTReader)

}

public class CocoaMQTTReader {

    var socket: GCDAsyncSocket

    var header: UInt8 = 0

    var data: [UInt8] = []

    var length: UInt = 0

    var multiply: Int = 1

    var delegate: CocoaMQTTReaderDelegate

    var timeout: Int = 30000

    init(socket: GCDAsyncSocket, delegate: CocoaMQTTReaderDelegate) {
        self.socket = socket
        self.delegate = delegate
    }

    func start() { readHeader() }

    func readHeader() {
        _reset(); socket.readDataToLength(1, withTimeout: -1, tag: CocoaMQTTReadTag.TAG_HEADER.rawValue)
    }

    func headerReady(header: UInt8) {
        #if DEBUG
        NSLog("CocoaMQTTReader: header ready: \(header) ")
        #endif
        self.header = header
        readLength()
    }

    func readLength() {
        socket.readDataToLength(1, withTimeout: NSTimeInterval(timeout), tag: CocoaMQTTReadTag.TAG_LENGTH.rawValue)
    }

    func lengthReady(byte: UInt8) {
        length += (UInt)((Int)(byte & 127) * multiply)
         if byte & 0x80 == 0 { //done
            if length == 0 {
                frameReady()
            } else {
                readPayload()
            }
         } else { //more
            multiply *= 128
            readLength()
        }
    }

    func readPayload() {
        socket.readDataToLength(length, withTimeout: NSTimeInterval(timeout), tag: CocoaMQTTReadTag.TAG_PAYLOAD.rawValue)
    }

    func payloadReady(data: NSData) {
        self.data = [UInt8](count: data.length, repeatedValue: 0)
        data.getBytes(&(self.data), length: data.length)
        frameReady()
    }

    func frameReady() {
        //handle frame
        let frameType = CocoaMQTTFrameType(rawValue: UInt8(header & 0xF0))!
        switch frameType {
        case .CONNACK:
           delegate.didReceiveConnAck(self, connack: data[1])
        case .PUBLISH:
            let (msgId, message) = unpackPublish()
            delegate.didReceivePublish(self, message: message, id: msgId)
        case .PUBACK:
            delegate.didReceivePubAck(self, msgid: _msgid(data))
        case .PUBREC:
            delegate.didReceivePubRec(self, msgid: _msgid(data))
        case .PUBREL:
            delegate.didReceivePubRel(self, msgid: _msgid(data))
        case .PUBCOMP:
            delegate.didReceivePubComp(self, msgid: _msgid(data))
        case .SUBACK:
            delegate.didReceiveSubAck(self, msgid: _msgid(data))
        case .UNSUBACK:
            delegate.didReceiveUnsubAck(self, msgid: _msgid(data))
        case .PINGRESP:
            delegate.didReceivePong(self)
        default:
            assert(false)
        }
        readHeader()
    }

    func unpackPublish() -> (UInt16, CocoaMQTTMessage) {
        let frame = CocoaMQTTFramePublish(header: header, data: data)
        frame.unpack()
        let msgId = frame.msgid!
        let qos = CocoaMQTTQOS(rawValue: frame.qos)!
        let message = CocoaMQTTMessage(topic: frame.topic!, payload: frame.payload, qos: qos, retained: frame.retained, dup: frame.dup)
        return (msgId, message)
    }

    func _msgid(bytes: [UInt8]) -> UInt16 {
        if bytes.count < 2 { return 0 }
        return UInt16(bytes[0]) << 8 + UInt16(bytes[1])
    }

    func _reset() {
        length = 0; multiply = 1; header = 0; data = []
    }

}
