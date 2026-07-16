import Foundation
import XCTest
@testable import CocoaMQTT

final class CocoaMQTTReaderProtocolErrorTests: XCTestCase {

    private final class SocketSpy: CocoaMQTTSocketProtocol {
        var enableSSL: Bool = false
        private(set) var disconnectCount = 0

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() { disconnectCount += 1 }
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
    }

    private final class ReaderDelegateSpy: CocoaMQTTReaderDelegate {
        private(set) var publishCount = 0
        private(set) var publishes = [FramePublish]()
        private(set) var disconnectCount = 0
        private(set) var authCount = 0
        private(set) var subackCount = 0

        func didReceive(_ reader: CocoaMQTTReader, connack: FrameConnAck) {}
        func didReceive(_ reader: CocoaMQTTReader, publish: FramePublish) {
            publishCount += 1
            publishes.append(publish)
        }
        func didReceive(_ reader: CocoaMQTTReader, puback: FramePubAck) {}
        func didReceive(_ reader: CocoaMQTTReader, pubrec: FramePubRec) {}
        func didReceive(_ reader: CocoaMQTTReader, pubrel: FramePubRel) {}
        func didReceive(_ reader: CocoaMQTTReader, pubcomp: FramePubComp) {}
        func didReceive(_ reader: CocoaMQTTReader, suback: FrameSubAck) { subackCount += 1 }
        func didReceive(_ reader: CocoaMQTTReader, unsuback: FrameUnsubAck) {}
        func didReceive(_ reader: CocoaMQTTReader, pingresp: FramePingResp) {}
        func didReceive(_ reader: CocoaMQTTReader, disconnect: FrameDisconnect) { disconnectCount += 1 }
        func didReceive(_ reader: CocoaMQTTReader, auth: FrameAuth) { authCount += 1 }
    }

    func testMalformedPublishDisconnectsSocket() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.publish.rawValue)
        reader.lengthReady(0x06)
        reader.payloadReady(Data([0x00, 0x00, 0x41, 0x41, 0x41, 0x41]))

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(delegate.publishCount, 0)
    }

    func testUnknownFrameTypeDisconnectsSocket() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(0x00)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(delegate.publishCount, 0)
    }

    func testMQTT5DisconnectFrameDoesNotProtocolError() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate, protocolVersion: .v5)

        reader.headerReady(FrameType.disconnect.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 0)
        XCTAssertEqual(delegate.disconnectCount, 1)
    }

    func testMQTT5AuthFrameDoesNotProtocolError() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate, protocolVersion: .v5)

        reader.headerReady(FrameType.auth.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 0)
        XCTAssertEqual(delegate.authCount, 1)
    }

    func testMQTT5RejectedSubAckDoesNotProtocolError() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate, protocolVersion: .v5)

        reader.headerReady(FrameType.suback.rawValue)
        reader.lengthReady(0x04)
        reader.payloadReady(Data([0x01, 0x93, 0x00, 0x87]))

        XCTAssertEqual(socket.disconnectCount, 0)
        XCTAssertEqual(delegate.subackCount, 1)
    }

    func testMQTT311RejectsMQTT5OnlyDisconnectFrame() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.disconnect.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(delegate.disconnectCount, 0)
    }

    func testMQTT311RejectsMQTT5OnlyAuthFrame() {
        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.auth.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(delegate.authCount, 0)
    }

    func testReadersKeepProtocolVersionsIndependent() {
        let mqtt311Socket = SocketSpy()
        let mqtt311Delegate = ReaderDelegateSpy()
        let mqtt311Reader = CocoaMQTTReader(
            socket: mqtt311Socket,
            delegate: mqtt311Delegate,
            protocolVersion: .v311
        )
        let mqtt5Socket = SocketSpy()
        let mqtt5Delegate = ReaderDelegateSpy()
        let mqtt5Reader = CocoaMQTTReader(
            socket: mqtt5Socket,
            delegate: mqtt5Delegate,
            protocolVersion: .v5
        )

        setMqtt5Version()
        mqtt311Reader.headerReady(FrameType.auth.rawValue)
        mqtt311Reader.lengthReady(0x00)

        setMqtt3Version()
        mqtt5Reader.headerReady(FrameType.auth.rawValue)
        mqtt5Reader.lengthReady(0x00)

        XCTAssertEqual(mqtt311Socket.disconnectCount, 1)
        XCTAssertEqual(mqtt311Delegate.authCount, 0)
        XCTAssertEqual(mqtt5Socket.disconnectCount, 0)
        XCTAssertEqual(mqtt5Delegate.authCount, 1)
    }

    func testReadersDecodeMQTT311AndMQTT5PublishesIndependently() throws {
        let previousVersion = CocoaMQTTStorage()?.queryMQTTVersion()
        defer {
            if let previousVersion {
                CocoaMQTTStorage()?.setMQTTVersion(previousVersion)
            }
        }

        let mqtt311Socket = SocketSpy()
        let mqtt311Delegate = ReaderDelegateSpy()
        let mqtt311Reader = CocoaMQTTReader(
            socket: mqtt311Socket,
            delegate: mqtt311Delegate,
            protocolVersion: .v311
        )
        let mqtt5Socket = SocketSpy()
        let mqtt5Delegate = ReaderDelegateSpy()
        let mqtt5Reader = CocoaMQTTReader(
            socket: mqtt5Socket,
            delegate: mqtt5Delegate,
            protocolVersion: .v5
        )

        let mqtt311Topic = Array("v3/topic".utf8)
        let mqtt311Payload: [UInt8] = [0x31, 0x32]
        let mqtt311Body = UInt16(mqtt311Topic.count).hlBytes + mqtt311Topic + mqtt311Payload
        setMqtt5Version()
        mqtt311Reader.headerReady(FrameType.publish.rawValue)
        mqtt311Reader.lengthReady(UInt8(mqtt311Body.count))
        mqtt311Reader.payloadReady(Data(mqtt311Body))

        let mqtt5Topic = Array("v5/topic".utf8)
        let mqtt5Payload: [UInt8] = [0x35, 0x30]
        let mqtt5Body = UInt16(mqtt5Topic.count).hlBytes + mqtt5Topic + [0x00] + mqtt5Payload
        setMqtt3Version()
        mqtt5Reader.headerReady(FrameType.publish.rawValue)
        mqtt5Reader.lengthReady(UInt8(mqtt5Body.count))
        mqtt5Reader.payloadReady(Data(mqtt5Body))

        let mqtt311Publish = try XCTUnwrap(mqtt311Delegate.publishes.first)
        XCTAssertEqual(mqtt311Publish.topic, "v3/topic")
        XCTAssertEqual(mqtt311Publish.payload(), mqtt311Payload)
        XCTAssertEqual(mqtt311Socket.disconnectCount, 0)

        let mqtt5Publish = try XCTUnwrap(mqtt5Delegate.publishes.first)
        XCTAssertEqual(mqtt5Publish.mqtt5Topic, "v5/topic")
        XCTAssertEqual(mqtt5Publish.payload5(), mqtt5Payload)
        XCTAssertEqual(mqtt5Socket.disconnectCount, 0)
    }

    func testClientInitializationDoesNotChangeGlobalCompatibilityVersion() {
        setMqtt3Version()
        _ = CocoaMQTT5(clientID: "mqtt5-version-isolation")
        XCTAssertEqual(CocoaMQTTStorage()?.queryMQTTVersion(), "3.1.1")

        setMqtt5Version()
        _ = CocoaMQTT(clientID: "mqtt311-version-isolation")
        XCTAssertEqual(CocoaMQTTStorage()?.queryMQTTVersion(), "5.0")
    }
}
