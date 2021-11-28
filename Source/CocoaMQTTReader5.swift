//
//  CocoaMQTTReader5.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/21.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// Read tag for AsyncSocket
enum CocoaMQTTRead5Tag: Int {
    case header = 0
    case length
    case payload
}

///
protocol CocoaMQTTReader5Delegate: AnyObject {

    func didReceive(_ reader: CocoaMQTTReader5, connack: FrameConnAck)

    func didReceive(_ reader: CocoaMQTTReader5, publish: FramePublish)

    func didReceive(_ reader: CocoaMQTTReader5, puback: FramePubAck)

    func didReceive(_ reader: CocoaMQTTReader5, pubrec: FramePubRec)

    func didReceive(_ reader: CocoaMQTTReader5, pubrel: FramePubRel)

    func didReceive(_ reader: CocoaMQTTReader5, pubcomp: FramePubComp)

    func didReceive(_ reader: CocoaMQTTReader5, suback: FrameSubAck5)

    func didReceive(_ reader: CocoaMQTTReader5, unsuback: FrameUnsubAck)

    func didReceive(_ reader: CocoaMQTTReader5, pingresp: FramePingResp)

    func didReceive(_ reader: CocoaMQTTReader5, disconnect: FrameDisconnect)

    func didReceive(_ reader: CocoaMQTTReader5, auth: FrameAuth)
}

class CocoaMQTTReader5 {

    private var socket: CocoaMQTTSocketProtocol

    private weak var delegate: CocoaMQTTReader5Delegate?

    private let timeout: TimeInterval = 30_000

    /*  -- Reader states -- */
    private var header: UInt8 = 0
    private var length: UInt = 0
    private var data: [UInt8] = []
    private var multiply = 1
    /*  -- Reader states -- */

    init(socket: CocoaMQTTSocketProtocol, delegate: CocoaMQTTReader5Delegate?) {
        self.socket = socket
        self.delegate = delegate
    }

    func start() {
        readHeader()
    }

    func headerReady(_ header: UInt8) {
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
        socket.readData(toLength: 1, withTimeout: -1, tag: CocoaMQTTRead5Tag.header.rawValue)
    }

    private func readLength() {
        socket.readData(toLength: 1, withTimeout: timeout, tag: CocoaMQTTRead5Tag.length.rawValue)
    }

    private func readPayload() {
        socket.readData(toLength: length, withTimeout: timeout, tag: CocoaMQTTRead5Tag.payload.rawValue)
    }

    private func frameReady() {

        guard let frameType = FrameType(rawValue: UInt8(header & 0xF0)) else {
            printError("Received unknown frame type, header: \(header), data:\(data)")
            readHeader()
            return
        }

        // XXX: stupid implement

        switch frameType {
        case .connack:
            guard let connack = FrameConnAck(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }

            delegate?.didReceive(self, connack: connack)
        case .publish:
            guard let publish = FramePublish(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, publish: publish)
        case .puback:
            guard let puback = FramePubAck(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, puback: puback)
        case .pubrec:
            guard let pubrec = FramePubRec(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, pubrec: pubrec)
        case .pubrel:
            guard let pubrel = FramePubRel(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, pubrel: pubrel)
        case .pubcomp:
            guard let pubcomp = FramePubComp(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, pubcomp: pubcomp)
        case .suback:
            guard let frame = FrameSubAck5(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, suback: frame)
        case .unsuback:
            guard let frame = FrameUnsubAck(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, unsuback: frame)
        case .pingresp:
            guard let frame = FramePingResp(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, pingresp: frame)
        case .disconnect:
            guard let frame = FrameDisconnect(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, disconnect: frame)
        case .auth:
            guard let frame = FrameAuth(packetFixedHeaderType: header, bytes: data) else {
                printError("Reader parse \(frameType) failed, data: \(data)")
                break
            }
            delegate?.didReceive(self, auth: frame)
        default:
            break
        }

        readHeader()
    }

    private func reset() {
        length = 0
        multiply = 1
        header = 0
        data = []
    }
}
