//
//  CocoaMQTTReader.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/21.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

/// Read tag for AsyncSocket
enum CocoaMQTTReadTag: Int {
    case header = 0
    case length
    case payload
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
            return assert(false)
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
