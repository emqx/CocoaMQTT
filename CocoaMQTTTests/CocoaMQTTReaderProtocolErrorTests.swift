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
        private(set) var disconnectCount = 0
        private(set) var authCount = 0

        func didReceive(_ reader: CocoaMQTTReader, connack: FrameConnAck) {}
        func didReceive(_ reader: CocoaMQTTReader, publish: FramePublish) { publishCount += 1 }
        func didReceive(_ reader: CocoaMQTTReader, puback: FramePubAck) {}
        func didReceive(_ reader: CocoaMQTTReader, pubrec: FramePubRec) {}
        func didReceive(_ reader: CocoaMQTTReader, pubrel: FramePubRel) {}
        func didReceive(_ reader: CocoaMQTTReader, pubcomp: FramePubComp) {}
        func didReceive(_ reader: CocoaMQTTReader, suback: FrameSubAck) {}
        func didReceive(_ reader: CocoaMQTTReader, unsuback: FrameUnsubAck) {}
        func didReceive(_ reader: CocoaMQTTReader, pingresp: FramePingResp) {}
        func didReceive(_ reader: CocoaMQTTReader, disconnect: FrameDisconnect) { disconnectCount += 1 }
        func didReceive(_ reader: CocoaMQTTReader, auth: FrameAuth) { authCount += 1 }
    }

    func testMalformedPublishDisconnectsSocket() {
        CocoaMQTTStorage()?.setMQTTVersion("3.1.1")

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
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.disconnect.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 0)
        XCTAssertEqual(delegate.disconnectCount, 1)
    }

    func testMQTT5AuthFrameDoesNotProtocolError() {
        CocoaMQTTStorage()?.setMQTTVersion("5.0")
        defer { CocoaMQTTStorage()?.setMQTTVersion("3.1.1") }

        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.auth.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 0)
        XCTAssertEqual(delegate.authCount, 1)
    }

    func testMQTT311RejectsMQTT5OnlyDisconnectFrame() {
        CocoaMQTTStorage()?.setMQTTVersion("3.1.1")

        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.disconnect.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(delegate.disconnectCount, 0)
    }

    func testMQTT311RejectsMQTT5OnlyAuthFrame() {
        CocoaMQTTStorage()?.setMQTTVersion("3.1.1")

        let socket = SocketSpy()
        let delegate = ReaderDelegateSpy()
        let reader = CocoaMQTTReader(socket: socket, delegate: delegate)

        reader.headerReady(FrameType.auth.rawValue)
        reader.lengthReady(0x00)

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(delegate.authCount, 0)
    }
}
