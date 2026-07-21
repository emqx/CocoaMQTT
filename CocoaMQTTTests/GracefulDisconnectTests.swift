import Foundation
import XCTest
@testable import CocoaMQTT
#if os(macOS)
import Network
#endif
#if IS_SWIFT_PACKAGE
@testable import CocoaMQTTWebSocket
#endif

final class GracefulDisconnectTests: XCTestCase {
    private final class DeferredDisconnectSocket: CocoaMQTTDisconnectAfterWritingSocket {
        var enableSSL = false
        private(set) var disconnectCount = 0
        private(set) var writeAndDisconnectCount = 0
        private(set) var finalWrites = [Data]()

        func setDelegate(_ theDelegate: CocoaMQTTSocketDelegate?, delegateQueue: DispatchQueue?) {}
        func connect(toHost host: String, onPort port: UInt16) throws {}
        func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {}
        func disconnect() {
            disconnectCount += 1
        }
        func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {}
        func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {}
        func writeAndDisconnect(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
            writeAndDisconnectCount += 1
            finalWrites.append(data)
        }

        func completeFinalWrite() {
            disconnect()
        }
    }

    func testMQTT311WaitsForDisconnectWriteAndCoalescesRepeatedRequests() {
        let socket = DeferredDisconnectSocket()
        let mqtt = CocoaMQTT(clientID: "graceful-disconnect-311", socket: socket)

        mqtt.disconnect()
        mqtt.disconnect()

        XCTAssertEqual(socket.writeAndDisconnectCount, 1)
        XCTAssertEqual(socket.finalWrites, [Data([FrameType.disconnect.rawValue, 0])])
        XCTAssertEqual(socket.disconnectCount, 0)

        socket.completeFinalWrite()
        XCTAssertEqual(socket.disconnectCount, 1)
    }

    func testMQTT5WaitsForDisconnectWriteAndPreservesReasonProperties() throws {
        let socket = DeferredDisconnectSocket()
        let mqtt = CocoaMQTT5(clientID: "graceful-disconnect-5", socket: socket)

        mqtt.disconnect(
            reasonCode: .disconnectWithWillMessage,
            userProperties: ["reason": "manual"]
        )
        mqtt.disconnect()

        XCTAssertEqual(socket.writeAndDisconnectCount, 1)
        XCTAssertEqual(socket.disconnectCount, 0)

        let bytes = try XCTUnwrap(socket.finalWrites.first).map { $0 }
        XCTAssertEqual(bytes.first, FrameType.disconnect.rawValue)
        XCTAssertEqual(Int(bytes[1]), bytes.count - 2)
        let frame = try XCTUnwrap(FrameDisconnect(
            packetFixedHeaderType: bytes[0],
            bytes: Array(bytes.dropFirst(2)),
            protocolVersion: .v5
        ))
        XCTAssertEqual(frame.receiveReasonCode, .disconnectWithWillMessage)
        XCTAssertEqual(frame.userProperties, ["reason": "manual"])

        socket.completeFinalWrite()
        XCTAssertEqual(socket.disconnectCount, 1)
    }

    #if IS_SWIFT_PACKAGE
    private final class WebSocketConnection: NSObject, CocoaMQTTWebSocketConnection {
        weak var delegate: CocoaMQTTWebSocketConnectionDelegate?
        var queue = DispatchQueue(label: "tests.graceful-disconnect.websocket")
        var onWrite: (() -> Void)?
        var onDisconnect: (() -> Void)?
        private var completions = [(Error?) -> Void]()
        private var events = [String]()

        func connect() {}

        func disconnect() {
            events.append("disconnect")
            onDisconnect?()
        }

        func write(data: Data, handler: @escaping (Error?) -> Void) {
            events.append("write:\(data.first ?? 0)")
            completions.append(handler)
            onWrite?()
        }

        func completeWrite(at index: Int, with error: Error? = nil) {
            queue.async {
                let completion = self.completions.remove(at: index)
                self.events.append("complete")
                completion(error)
            }
        }

        func receive(_ data: Data) {
            queue.async {
                self.delegate?.connection(self, receivedData: data)
            }
        }

        func snapshot() -> [String] {
            queue.sync { events }
        }
    }

    private final class WebSocketBuilder: CocoaMQTTWebSocketConnectionBuilder {
        let connection: WebSocketConnection

        init(connection: WebSocketConnection) {
            self.connection = connection
        }

        func buildConnection(forURL url: URL, withHeaders headers: [String: String]) throws -> CocoaMQTTWebSocketConnection {
            connection
        }
    }

    private final class SocketDelegate: CocoaMQTTSocketDelegate {
        var onConnect: (() -> Void)?
        var onWrite: ((Int) -> Void)?
        var onRead: ((Data, Int) -> Void)?
        var onDisconnect: ((Error?) -> Void)?

        func socketConnected(_ socket: CocoaMQTTSocketProtocol) {
            onConnect?()
        }
        func socket(_ socket: CocoaMQTTSocketProtocol,
                    didReceive trust: SecTrust,
                    completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
        func socketUrlSession(_ socket: CocoaMQTTSocketProtocol,
                              didReceiveTrust trust: SecTrust,
                              didReceiveChallenge challenge: URLAuthenticationChallenge,
                              completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }
        func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {
            onWrite?(tag)
        }
        func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {
            onRead?(data, tag)
        }
        func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError err: Error?) {
            onDisconnect?(err)
        }
    }

    func testWebSocketClosesOnlyAfterAllPendingWritesComplete() throws {
        let connection = WebSocketConnection()
        let websocket = CocoaMQTTWebSocket(
            uri: "/mqtt",
            builder: WebSocketBuilder(connection: connection)
        )
        let delegate = SocketDelegate()
        let callbackQueue = DispatchQueue(label: "tests.graceful-disconnect.callbacks")
        let callbackQueueKey = DispatchSpecificKey<Void>()
        callbackQueue.setSpecific(key: callbackQueueKey, value: ())
        let writesQueued = expectation(description: "writes queued")
        writesQueued.expectedFulfillmentCount = 2
        let writeCallbacks = expectation(description: "write callbacks")
        writeCallbacks.expectedFulfillmentCount = 2
        let disconnected = expectation(description: "disconnected")
        connection.onWrite = { writesQueued.fulfill() }
        delegate.onWrite = { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: callbackQueueKey))
            writeCallbacks.fulfill()
        }
        delegate.onDisconnect = { error in
            XCTAssertNil(error)
            disconnected.fulfill()
        }
        websocket.setDelegate(delegate, delegateQueue: callbackQueue)
        try websocket.connect(toHost: "localhost", onPort: 8083)

        websocket.write(Data([1]), withTimeout: 1, tag: 1)
        websocket.writeAndDisconnect(Data([2]), withTimeout: 1, tag: 2)
        wait(for: [writesQueued], timeout: 1)

        connection.completeWrite(at: 1)
        connection.queue.sync {}
        XCTAssertFalse(connection.snapshot().contains("disconnect"))

        connection.completeWrite(at: 0)
        wait(for: [writeCallbacks, disconnected], timeout: 1)
        XCTAssertEqual(connection.snapshot(), ["write:1", "write:2", "complete", "complete", "disconnect"])

        websocket.write(Data([3]), withTimeout: 0.01, tag: 3)
        connection.queue.sync {}
        XCTAssertEqual(connection.snapshot(), ["write:1", "write:2", "complete", "complete", "disconnect"])

        let reconnectWrite = expectation(description: "write after reconnect")
        let reconnectCallback = expectation(description: "write callback after reconnect")
        connection.onWrite = { reconnectWrite.fulfill() }
        delegate.onWrite = { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: callbackQueueKey))
            reconnectCallback.fulfill()
        }
        try websocket.connect(toHost: "localhost", onPort: 8083)
        websocket.write(Data([3]), withTimeout: 1, tag: 3)
        wait(for: [reconnectWrite], timeout: 1)
        XCTAssertEqual(connection.snapshot().last, "write:3")
        connection.completeWrite(at: 0)
        wait(for: [reconnectCallback], timeout: 1)
    }

    func testWebSocketRejectsWritesAfterGracefulCloseStarts() throws {
        let connection = WebSocketConnection()
        let websocket = CocoaMQTTWebSocket(
            uri: "/mqtt",
            builder: WebSocketBuilder(connection: connection)
        )
        let writeQueued = expectation(description: "final write queued")
        connection.onWrite = { writeQueued.fulfill() }
        try websocket.connect(toHost: "localhost", onPort: 8083)

        websocket.writeAndDisconnect(Data([2]), withTimeout: 1, tag: 2)
        websocket.write(Data([3]), withTimeout: 1, tag: 3)
        wait(for: [writeQueued], timeout: 1)
        connection.queue.sync {}

        XCTAssertEqual(connection.snapshot(), ["write:2"])
        connection.completeWrite(at: 0)
    }

    func testWebSocketWriteFailureClosesWithError() throws {
        let connection = WebSocketConnection()
        let websocket = CocoaMQTTWebSocket(
            uri: "/mqtt",
            builder: WebSocketBuilder(connection: connection)
        )
        let delegate = SocketDelegate()
        let callbackQueue = DispatchQueue(label: "tests.graceful-disconnect.failure-callbacks")
        let writeQueued = expectation(description: "final write queued")
        let disconnected = expectation(description: "failed disconnect")
        connection.onWrite = { writeQueued.fulfill() }
        delegate.onDisconnect = { error in
            XCTAssertNotNil(error)
            disconnected.fulfill()
        }
        websocket.setDelegate(delegate, delegateQueue: callbackQueue)
        try websocket.connect(toHost: "localhost", onPort: 8083)

        websocket.writeAndDisconnect(Data([2]), withTimeout: 1, tag: 2)
        wait(for: [writeQueued], timeout: 1)
        connection.completeWrite(
            at: 0,
            with: NSError(domain: "GracefulDisconnectTests", code: 1)
        )

        wait(for: [disconnected], timeout: 1)
        XCTAssertEqual(connection.snapshot().last, "disconnect")
    }

    func testWebSocketWriteTimeoutClosesConnection() throws {
        let connection = WebSocketConnection()
        let websocket = CocoaMQTTWebSocket(
            uri: "/mqtt",
            builder: WebSocketBuilder(connection: connection)
        )
        let delegate = SocketDelegate()
        let callbackQueue = DispatchQueue(label: "tests.graceful-disconnect.timeout-callbacks")
        let writeQueued = expectation(description: "final write queued")
        let disconnected = expectation(description: "timed out disconnect")
        connection.onWrite = { writeQueued.fulfill() }
        delegate.onDisconnect = { error in
            XCTAssertNotNil(error)
            disconnected.fulfill()
        }
        websocket.setDelegate(delegate, delegateQueue: callbackQueue)
        try websocket.connect(toHost: "localhost", onPort: 8083)

        websocket.writeAndDisconnect(Data([2]), withTimeout: 0.01, tag: 2)

        wait(for: [writeQueued, disconnected], timeout: 1)
        XCTAssertEqual(connection.snapshot().last, "disconnect")
    }

    func testWebSocketIncompletePayloadTriggersReadTimeout() throws {
        let connection = WebSocketConnection()
        let websocket = CocoaMQTTWebSocket(
            uri: "/mqtt",
            builder: WebSocketBuilder(connection: connection)
        )
        let delegate = SocketDelegate()
        let callbackQueue = DispatchQueue(label: "tests.graceful-disconnect.read-timeout-callbacks")
        let headerRead = expectation(description: "header read")
        let lengthRead = expectation(description: "Remaining Length read")
        let disconnected = expectation(description: "incomplete payload timed out")

        delegate.onRead = { data, tag in
            switch CocoaMQTTReadTag(rawValue: tag) {
            case .header:
                XCTAssertEqual(data, Data([FrameType.publish.rawValue]))
                headerRead.fulfill()
                websocket.readData(
                    toLength: 1,
                    withTimeout: 0.05,
                    tag: CocoaMQTTReadTag.length.rawValue
                )
            case .length:
                XCTAssertEqual(data, Data([2]))
                lengthRead.fulfill()
                websocket.readData(
                    toLength: 2,
                    withTimeout: 0.05,
                    tag: CocoaMQTTReadTag.payload.rawValue
                )
            case .payload, .none:
                XCTFail("Incomplete payload should not be delivered")
            }
        }
        delegate.onDisconnect = { error in
            guard let mqttError = error as? CocoaMQTTError,
                  case .readTimeout = mqttError else {
                return XCTFail("Expected readTimeout, got \(String(describing: error))")
            }
            disconnected.fulfill()
        }
        websocket.setDelegate(delegate, delegateQueue: callbackQueue)
        try websocket.connect(toHost: "localhost", onPort: 8083)
        websocket.readData(
            toLength: 1,
            withTimeout: -1,
            tag: CocoaMQTTReadTag.header.rawValue
        )

        connection.receive(Data([FrameType.publish.rawValue, 2, 0x01]))

        wait(for: [headerRead, lengthRead, disconnected], timeout: 1)
        XCTAssertEqual(connection.snapshot().last, "disconnect")
    }

    #if os(macOS)
    private static func extractMQTTPacket(from buffer: inout Data) -> (header: UInt8, body: [UInt8])? {
        guard buffer.count >= 2 else { return nil }
        var remainingLength = 0
        var multiplier = 1
        var index = 1
        var lengthByteCount = 0

        while index < buffer.count && lengthByteCount < 4 {
            let byte = buffer[index]
            remainingLength += Int(byte & 0x7f) * multiplier
            multiplier *= 128
            index += 1
            lengthByteCount += 1
            if byte & 0x80 == 0 {
                guard buffer.count >= index + remainingLength else { return nil }
                let header = buffer[0]
                let body = Array(buffer[index..<(index + remainingLength)])
                buffer = Data(buffer.dropFirst(index + remainingLength))
                return (header, body)
            }
        }
        return nil
    }

    func testMQTT5BrokerReceivesDisconnectReasonAndProperties() throws {
        let listenerQueue = DispatchQueue(label: "tests.graceful-disconnect.mqtt5-broker")
        let listener = try NWListener(using: .tcp, on: .any)
        let listenerReady = expectation(description: "MQTT 5 broker ready")
        let brokerReceivedDisconnect = expectation(description: "broker received MQTT 5 DISCONNECT")
        let clientDisconnected = expectation(description: "MQTT 5 client disconnected")
        let observedFrameLock = NSLock()
        var observedFrame: FrameDisconnect?
        var receiveBuffer = Data()

        func receivePackets(from connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data {
                    receiveBuffer.append(data)
                    while let packet = Self.extractMQTTPacket(from: &receiveBuffer) {
                        switch packet.header & 0xf0 {
                        case FrameType.connect.rawValue:
                            connection.send(content: Data([FrameType.connack.rawValue, 3, 0, 0, 0]), completion: .contentProcessed { _ in })
                        case FrameType.disconnect.rawValue:
                            observedFrameLock.lock()
                            observedFrame = FrameDisconnect(
                                packetFixedHeaderType: packet.header,
                                bytes: packet.body,
                                protocolVersion: .v5
                            )
                            observedFrameLock.unlock()
                            brokerReceivedDisconnect.fulfill()
                        default:
                            break
                        }
                    }
                }
                if !isComplete && error == nil {
                    receivePackets(from: connection)
                }
            }
        }

        listener.stateUpdateHandler = { state in
            if case .ready = state {
                listenerReady.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: listenerQueue)
            receivePackets(from: connection)
        }
        listener.start(queue: listenerQueue)
        wait(for: [listenerReady], timeout: 2)

        let mqtt5 = CocoaMQTT5(
            clientID: "graceful-disconnect-broker",
            host: "127.0.0.1",
            port: try XCTUnwrap(listener.port?.rawValue)
        )
        mqtt5.delegateQueue = DispatchQueue(label: "tests.graceful-disconnect.mqtt5-callbacks")
        mqtt5.didConnectAck = { client, reasonCode, _ in
            XCTAssertEqual(reasonCode, .success)
            client.disconnect(
                reasonCode: .disconnectWithWillMessage,
                userProperties: ["reason": "integration"]
            )
        }
        mqtt5.didDisconnect = { _, error in
            XCTAssertNil(error)
            clientDisconnected.fulfill()
        }

        XCTAssertTrue(mqtt5.connect(timeout: 1))
        wait(for: [brokerReceivedDisconnect, clientDisconnected], timeout: 2)
        listener.cancel()

        observedFrameLock.lock()
        let frame = observedFrame
        observedFrameLock.unlock()
        XCTAssertEqual(frame?.receiveReasonCode, .disconnectWithWillMessage)
        XCTAssertEqual(frame?.userProperties, ["reason": "integration"])
    }

    func testTCPSendsFinalBytesBeforeClosing() throws {
        let listenerQueue = DispatchQueue(label: "tests.graceful-disconnect.tcp-listener")
        let listener = try NWListener(using: .tcp, on: .any)
        let listenerReady = expectation(description: "listener ready")
        let receivedEOF = expectation(description: "received final bytes before EOF")
        let socketDisconnected = expectation(description: "socket disconnected")
        let expectedData = Data([FrameType.disconnect.rawValue, 0])
        let receivedLock = NSLock()
        var receivedData = Data()

        func receiveUntilEOF(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                if let data {
                    receivedLock.lock()
                    receivedData.append(data)
                    receivedLock.unlock()
                }
                if isComplete || error != nil {
                    receivedEOF.fulfill()
                } else {
                    receiveUntilEOF(connection)
                }
            }
        }

        listener.stateUpdateHandler = { state in
            if case .ready = state {
                listenerReady.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: listenerQueue)
            receiveUntilEOF(connection)
        }
        listener.start(queue: listenerQueue)
        wait(for: [listenerReady], timeout: 2)
        let port = try XCTUnwrap(listener.port?.rawValue)

        let socket = CocoaMQTTSocket()
        let delegate = SocketDelegate()
        delegate.onConnect = {
            socket.writeAndDisconnect(expectedData, withTimeout: 1, tag: 1)
        }
        delegate.onDisconnect = { error in
            XCTAssertNil(error)
            socketDisconnected.fulfill()
        }
        socket.setDelegate(delegate, delegateQueue: DispatchQueue(label: "tests.graceful-disconnect.tcp-callbacks"))
        try socket.connect(toHost: "127.0.0.1", onPort: port, withTimeout: 1)

        wait(for: [receivedEOF, socketDisconnected], timeout: 2)
        listener.cancel()
        receivedLock.lock()
        let finalData = receivedData
        receivedLock.unlock()
        XCTAssertEqual(finalData, expectedData)
    }
    #endif
    #endif
}
