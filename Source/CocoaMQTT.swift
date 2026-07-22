//
//  CocoaMQTT.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqx.io. All rights reserved.
//

import Foundation
import MqttCocoaAsyncSocket

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

    public init(byte: UInt8) {
        switch byte {
        case CocoaMQTTConnAck.accept.rawValue..<CocoaMQTTConnAck.reserved.rawValue:
            self.init(rawValue: byte)!
        default:
            self = .reserved
        }
    }

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

/// CocoaMQTT Delegate
@objc public protocol CocoaMQTTDelegate {

    ///
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)

    ///
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16)

    ///
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16)

    ///
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 )

    ///
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String])

    ///
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String])

    ///
    func mqttDidPing(_ mqtt: CocoaMQTT)

    ///
    func mqttDidReceivePong(_ mqtt: CocoaMQTT)

    ///
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?)

    /// Manually validate SSL/TLS server certificate.
    ///
    /// This method will be called if enable  `allowUntrustCACertificate`
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void)

    @objc optional func mqttUrlSession(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)

    ///
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16)

    ///
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState)

    /// Called when auto-reconnect schedules a reconnect attempt after an unexpected disconnect.
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didScheduleReconnect attemptCount: UInt, after interval: UInt16)
}

/// set mqtt version to 3.1.1
public func setMqtt3Version() {
    if let storage = CocoaMQTTStorage() {
        storage.setMQTTVersion("3.1.1")
    }
}

/**
 * Blueprint of the MQTT Client
 */
protocol CocoaMQTTClient {

    /* Basic Properties */

    var host: String { get set }
    var port: UInt16 { get set }
    var clientID: String { get }
    var username: String? {get set}
    var password: String? {get set}
    var cleanSession: Bool {get set}
    var keepAlive: UInt16 {get set}
    var willMessage: CocoaMQTTMessage? {get set}

    /* Basic Properties */

    /* CONNNEC/DISCONNECT */

    func connect() -> Bool
    func connect(timeout: TimeInterval) -> Bool
    func disconnect()
    func ping()

    /* CONNNEC/DISCONNECT */

    /* PUBLISH/SUBSCRIBE */

    func subscribe(_ topic: String, qos: CocoaMQTTQoS)
    func subscribe(_ topics: [(String, CocoaMQTTQoS)])

    func unsubscribe(_ topic: String)
    func unsubscribe(_ topics: [String])

    func publish(_ topic: String, withString string: String, qos: CocoaMQTTQoS, retained: Bool) -> Int
    func publish(_ message: CocoaMQTTMessage) -> Int

    /* PUBLISH/SUBSCRIBE */
}

/// MQTT Client
///
/// - Note: MGCDAsyncSocket need delegate to extend NSObject
public class CocoaMQTT: NSObject, CocoaMQTTClient {

    public weak var delegate: CocoaMQTTDelegate?

    private var version = "3.1.1"

    public var host = "localhost"

    public var port: UInt16 = 1883

    public var clientID: String

    public var username: String?

    public var password: String?

    /// Clean Session flag. Default is true
    ///
    /// - TODO: What's behavior each Clean Session flags???
    public var cleanSession = true

    /// Setup a **Last Will Message** to client before connecting to broker
    public var willMessage: CocoaMQTTMessage?

    /// Enable backgounding socket if running on iOS platform. Default is true
    ///
    /// - Note:
    public var backgroundOnSocket: Bool {
        get { return (self.socket as? CocoaMQTTSocket)?.backgroundOnSocket ?? true }
        set { (self.socket as? CocoaMQTTSocket)?.backgroundOnSocket = newValue }
    }

    /// Delegate Executed queue. Default is `DispatchQueue.main`
    ///
    /// The delegate/closure callback function will be committed asynchronously to it.
    /// Changing the queue affects callbacks emitted after the assignment; callbacks
    /// already submitted remain on the queue captured when their event occurred.
    public var delegateQueue: DispatchQueue {
        get {
            delegateQueueLock.lock()
            defer { delegateQueueLock.unlock() }
            return _delegateQueue
        }
        set {
            delegateQueueLock.lock()
            _delegateQueue = newValue
            delegateQueueLock.unlock()
        }
    }
    private let delegateQueueLock = NSLock()
    private var _delegateQueue = DispatchQueue.main

    /// Owns ordered socket, reader, timer, and delivery events. Application code
    /// cannot replace this queue through `delegateQueue`.
    let eventLoopQueue: DispatchQueue
    private var socketDelegateProxy: CocoaMQTTSocketDelegateProxy!

    public var connState: CocoaMQTTConnState {
        get {
            connStateLock.lock()
            defer { connStateLock.unlock() }
            return _connState
        }
        set {
            connStateLock.lock()
            _connState = newValue
            connStateLock.unlock()
            __delegate_queue { mqtt in
                mqtt.delegate?.mqtt?(mqtt, didStateChangeTo: newValue)
                mqtt.didChangeState(mqtt, newValue)
            }
        }
    }
    private let connStateLock = NSLock()
    private var _connState = CocoaMQTTConnState.disconnected

    // deliver
    private var deliver = CocoaMQTTDeliver()

    /// Re-deliver the un-acked messages
    public var deliverTimeout: Double {
        get { return deliver.retryTimeInterval }
        set { deliver.retryTimeInterval = newValue }
    }

    /// Message queue size. default 1000
    ///
    /// The new publishing messages of Qos1/Qos2 will be drop, if the queue is full
    public var messageQueueSize: UInt {
        get { return deliver.mqueueSize }
        set { deliver.mqueueSize = newValue }
    }

    /// In-flight window size. default 10
    public var inflightWindowSize: UInt {
        get { return deliver.inflightWindowSize }
        set { deliver.inflightWindowSize = newValue }
    }

    /// Keep alive time interval
    public var keepAlive: UInt16 = 60
    private var aliveTimer: CocoaMQTTTimer?

    /// Maximum duration in seconds for each Remaining Length byte and the complete payload read.
    /// Each deadline starts with its read and is not reset by partial data. Header reads remain unlimited.
    /// Nonpositive or nonfinite values disable these deadlines. Default is 30 seconds.
    /// Changes take effect on the next connection.
    public var packetReadTimeout: TimeInterval = CocoaMQTTReader.defaultPacketReadTimeout

    /// Enable auto-reconnect mechanism
    public var autoReconnect: Bool {
        get {
            autoReconnectLock.lock()
            defer { autoReconnectLock.unlock() }
            return _autoReconnect
        }
        set {
            autoReconnectLock.lock()
            _autoReconnect = newValue
            autoReconnectLock.unlock()
            if !newValue { resetAutoReconnectState() }
        }
    }
    private var _autoReconnect = false

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

    /// Auto-reconnect backoff interval in seconds for the current reconnect cycle.
    ///
    /// This value is advanced for the next reconnect attempt while auto-reconnect is active,
    /// and resets to `0` when auto-reconnect is inactive.
    public private(set) var reconnectTimeInterval: UInt16 {
        get {
            autoReconnectLock.lock()
            defer { autoReconnectLock.unlock() }
            return _reconnectTimeInterval
        }
        set {
            autoReconnectLock.lock()
            _reconnectTimeInterval = newValue
            autoReconnectLock.unlock()
        }
    }
    private var _reconnectTimeInterval: UInt16 = 0

    /// Number of reconnect attempts scheduled in the current auto-reconnect cycle.
    ///
    /// The value resets to `0` after a successful connection or expected disconnect.
    public private(set) var reconnectAttemptCount: UInt {
        get {
            autoReconnectLock.lock()
            defer { autoReconnectLock.unlock() }
            return _reconnectAttemptCount
        }
        set {
            autoReconnectLock.lock()
            _reconnectAttemptCount = newValue
            autoReconnectLock.unlock()
        }
    }
    private var _reconnectAttemptCount: UInt = 0

    /// Whether auto-reconnect is currently paused by the application.
    public var isAutoReconnectPaused: Bool {
        autoReconnectLock.lock()
        defer { autoReconnectLock.unlock() }
        return _isAutoReconnectPaused
    }

    private let autoReconnectLock = NSRecursiveLock()
    private var _isAutoReconnectPaused = false
    private var autoReconnTimer: CocoaMQTTTimer?
    private var isAutoReconnectAttemptScheduled = false
    private var hasPausedAutoReconnectAttempt = false
    private var hasPendingAutoReconnectAttempt = false
    private var autoReconnectGeneration: UInt64 = 0
    // Tracks the window after requesting an unexpected socket close and before socketDidDisconnect cleans it up.
    private var pendingSocketDisconnectReconnectAttemptCount: UInt?
    private var shouldResumeAutoReconnectAfterPendingDisconnect = false
    private var is_internal_disconnected = false
    private var isExpectedDisconnectPending = false

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
    public var enableSSL: Bool {
        get { return self.socket.enableSSL }
        set { socket.enableSSL = newValue }
    }

    ///
    public var sslSettings: [String: NSObject]? {
        get { return (self.socket as? CocoaMQTTSocket)?.sslSettings ?? nil }
        set { (self.socket as? CocoaMQTTSocket)?.sslSettings = newValue }
    }

    /// Allow self-signed ca certificate.
    ///
    /// Default is false
    public var allowUntrustCACertificate: Bool {
        get { return (self.socket as? CocoaMQTTSocket)?.allowUntrustCACertificate ?? false }
        set { (self.socket as? CocoaMQTTSocket)?.allowUntrustCACertificate = newValue }
    }

    /// The subscribed topics in current communication
    ///
    /// Keeping this dictionary-typed preserves the public API while the backing store remains thread-safe.
    public var subscriptions: [String: CocoaMQTTQoS] {
        get { subscriptionsStorage.snapshot() }
        set { subscriptionsStorage.replace(with: newValue) }
    }
    private var subscriptionsStorage = ThreadSafeDictionary<String, CocoaMQTTQoS>(label: "subscriptions")

    fileprivate var subscriptionsWaitingAck = ThreadSafeDictionary<UInt16, [(String, CocoaMQTTQoS)]>(label: "subscriptionsWaitingAck")
    fileprivate var unsubscriptionsWaitingAck = ThreadSafeDictionary<UInt16, [String]>(label: "unsubscriptionsWaitingAck")

    /// Sending messages
    fileprivate var sendingMessages = ThreadSafeDictionary<UInt64, CocoaMQTTMessage>(label: "sendingMessages")

    private let packetIdentifiers = MQTTPacketIdentifierAllocator()
    private var _deliveryToken = UInt64(UInt16.max)
    private let messageIdentifierLock = NSLock()
    private let clientStateLock = NSRecursiveLock()
    private var activeClientID: String
    fileprivate var socket: CocoaMQTTSocketProtocol
    fileprivate var reader: CocoaMQTTReader?

    // Closures
    public var didConnectAck: (CocoaMQTT, CocoaMQTTConnAck) -> Void = { _, _ in }
    public var didPublishMessage: (CocoaMQTT, CocoaMQTTMessage, UInt16) -> Void = { _, _, _ in }
    public var didPublishAck: (CocoaMQTT, UInt16) -> Void = { _, _ in }
    public var didReceiveMessage: (CocoaMQTT, CocoaMQTTMessage, UInt16) -> Void = { _, _, _ in }
    public var didSubscribeTopics: (CocoaMQTT, NSDictionary, [String]) -> Void = { _, _, _  in }
    public var didUnsubscribeTopics: (CocoaMQTT, [String]) -> Void = { _, _ in }
    public var didPing: (CocoaMQTT) -> Void = { _ in }
    public var didReceivePong: (CocoaMQTT) -> Void = { _ in }
    public var didDisconnect: (CocoaMQTT, Error?) -> Void = { _, _ in }
    public var didReceiveTrust: (CocoaMQTT, SecTrust, @escaping (Bool) -> Swift.Void) -> Void = { _, _, _ in }
    public var didCompletePublish: (CocoaMQTT, UInt16) -> Void = { _, _ in }
    public var didChangeState: (CocoaMQTT, CocoaMQTTConnState) -> Void = { _, _ in }
    public var didScheduleReconnect: (CocoaMQTT, UInt, UInt16) -> Void = { _, _, _ in }

    /// Initial client object
    ///
    /// - Parameters:
    ///   - clientID: Client Identifier
    ///   - host: The MQTT broker host domain or IP address. Default is "localhost"
    ///   - port: The MQTT service port of host. Default is 1883
    public init(clientID: String, host: String = "localhost", port: UInt16 = 1883, socket: CocoaMQTTSocketProtocol = CocoaMQTTSocket()) {
        self.clientID = clientID
        self.activeClientID = clientID
        self.host = host
        self.port = port
        self.socket = socket
        self.eventLoopQueue = DispatchQueue(label: "io.emqx.CocoaMQTT.event-loop.\(UUID().uuidString)")
        super.init()
        socketDelegateProxy = CocoaMQTTSocketDelegateProxy(eventLoopQueue: eventLoopQueue)
        socketDelegateProxy.delegate = self
        deliver.delegate = self
    }

    deinit {
        aliveTimer?.suspend()
        autoReconnTimer?.suspend()

        socket.setDelegate(nil, delegateQueue: nil)
        socket.disconnect()
    }

    fileprivate func send(_ frame: Frame, tag: Int = 0, disconnectAfterWriting: Bool = false) {
        printDebug("SEND: \(frame)")
        let data = frame.bytes(version: version)
        let packet = Data(bytes: data, count: data.count)
        if disconnectAfterWriting {
            socket.writeAndDisconnect(packet, withTimeout: 5, tag: tag)
        } else {
            socket.write(packet, withTimeout: 5, tag: tag)
        }
    }

    fileprivate func sendConnectFrame() {

        var connect = FrameConnect(clientID: activeClientID)
        connect.keepAlive = keepAlive
        connect.username = username
        connect.password = password
        connect.willMsg = willMessage
        connect.cleansess = cleanSession

        send(connect)
        reader!.start()
    }

    fileprivate func nextDeliveryToken() -> UInt64 {
        messageIdentifierLock.lock()
        defer { messageIdentifierLock.unlock() }
        if _deliveryToken >= UInt64(Int.max) {
            _deliveryToken = UInt64(UInt16.max) + 1
        } else {
            _deliveryToken += 1
        }
        return _deliveryToken
    }

    fileprivate func discardStoredSession() {
        CocoaMQTTStorage(by: activeClientID, protocolVersion: .v311)?.removeAll()
    }

    private func discardCurrentSession(preservingConnectionQueue: Bool = false) {
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        discardStoredSession()
        discardInMemorySession(preservingConnectionQueue: preservingConnectionQueue)
    }

    private func discardInMemorySession(preservingConnectionQueue: Bool = false) {
        let pendingPublishes = preservingConnectionQueue
            ? deliver.connectionPendingFrames().compactMap { $0 as? FramePublish }
            : []
        deliver.cleanAll(
            detachStorage: true,
            preserveConnectionQueue: preservingConnectionQueue
        )
        if preservingConnectionQueue {
            let pendingTokens = Set(pendingPublishes.map { $0.deliveryToken ?? UInt64($0.msgid) })
            sendingMessages.replace(with: sendingMessages.snapshot().filter { pendingTokens.contains($0.key) })
        } else {
            sendingMessages.removeAll()
        }
        subscriptionsWaitingAck.removeAll()
        unsubscriptionsWaitingAck.removeAll()
        subscriptionsStorage.removeAll()
        packetIdentifiers.reset()
        for publish in pendingPublishes where publish.qos > .qos0 {
            packetIdentifiers.markInUse(publish.msgid)
        }
    }

    private func markStoredPacketIdentifiersInUse() {
        guard let frames = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v311)?.readAll() else {
            return
        }
        for frame in frames {
            if let publish = frame as? FramePublish {
                packetIdentifiers.markInUse(publish.msgid)
            } else if let pubrel = frame as? FramePubRel {
                packetIdentifiers.markInUse(pubrel.msgid)
            }
        }
    }

    /// Callers must hold `clientStateLock`.
    private func clearPendingSubscriptionRequestsLocked() {
        for identifier in subscriptionsWaitingAck.removeAllValues().keys {
            packetIdentifiers.release(identifier)
        }
        for identifier in unsubscriptionsWaitingAck.removeAllValues().keys {
            packetIdentifiers.release(identifier)
        }
    }

    fileprivate func puback(_ type: FrameType, msgid: UInt16) {
        switch type {
        case .puback:
            send(FramePubAck(msgid: msgid))
        case .pubrec:
            send(FramePubRec(msgid: msgid))
        case .pubcomp:
            send(FramePubComp(msgid: msgid))
        default: return
        }
    }

    /// Connect to MQTT broker
    ///
    /// - Returns:
    ///   - Bool: It indicates whether successfully calling socket connect function.
    ///           Not yet established correct MQTT session
    public func connect() -> Bool {
        return connect(timeout: -1)
    }

    /// Connect to MQTT broker
    /// - Parameters:
    ///   - timeout: Connect timeout
    /// - Returns:
    ///   - Bool: It indicates whether successfully calling socket connect function.
    ///           Not yet established correct MQTT session
    public func connect(timeout: TimeInterval) -> Bool {
        guard hasValidMQTTUTF8Length(clientID, allowEmpty: cleanSession),
              !clientID.isEmpty || cleanSession,
              username.map({ hasValidMQTTUTF8Length($0, allowEmpty: true) }) ?? true,
              hasValidMQTTPasswordLength(password),
              willMessage.map({
                hasValidMQTTTopicName($0.topic)
                    && $0.qos <= .qos2
                    && hasValidMQTTBinaryLength($0.payload)
              }) ?? true else {
            printError("Invalid MQTT CONNECT fields.")
            return false
        }
        // Publish uses the same lock, so pausing transport and starting the
        // connection queue are atomic relative to queue admission.
        clientStateLock.lock()
        deliver.setTransportEnabled(false)
        if activeClientID != clientID {
            discardInMemorySession()
        }
        activeClientID = clientID
        markStoredPacketIdentifiersInUse()
        deliver.beginConnection()
        clientStateLock.unlock()
        socket.setDelegate(socketDelegateProxy, delegateQueue: eventLoopQueue)
        reader = CocoaMQTTReader(
            socket: socket,
            delegate: self,
            protocolVersion: .v311,
            packetReadTimeout: packetReadTimeout
        )
        do {
            if timeout > 0 {
                try socket.connect(toHost: self.host, onPort: self.port, withTimeout: timeout)
            } else {
                try socket.connect(toHost: self.host, onPort: self.port)
            }

            eventLoopQueue.async { [weak self] in
                guard let self = self else { return }
                self.connState = .connecting
            }

            return true
        } catch let error as NSError {
            printError("socket connect error: \(error.description)")
            return false
        }
    }

    /// Send a DISCONNECT packet to the broker then close the connection
    ///
    /// - Note: Only can be called from outside.
    ///         This closes the connection expectedly, so auto-reconnect will not run.
    public func disconnect() {
        expected_disconnect()
    }

    /// Disconnect unexpectedly.
    /// This keeps auto-reconnect behavior enabled.
    func internal_disconnect() {
        autoReconnectLock.lock()
        pendingSocketDisconnectReconnectAttemptCount = reconnectAttemptCount
        autoReconnectLock.unlock()

        is_internal_disconnected = false
        socket.disconnect()
    }

    /// Pause auto-reconnect attempts without disabling `autoReconnect`.
    ///
    /// Use this when the application knows reconnect attempts should not run yet,
    /// for example while waiting for network reachability to recover.
    public func pauseAutoReconnect() {
        autoReconnectLock.lock()
        _isAutoReconnectPaused = true
        if isAutoReconnectAttemptScheduled {
            hasPausedAutoReconnectAttempt = true
            isAutoReconnectAttemptScheduled = false
        }
        shouldResumeAutoReconnectAfterPendingDisconnect = false
        autoReconnTimer = nil
        autoReconnectGeneration &+= 1
        autoReconnectLock.unlock()
    }

    /// Resume auto-reconnect attempts after `pauseAutoReconnect()`.
    ///
    /// If an auto-reconnect attempt is pending, this schedules the next reconnect
    /// attempt immediately.
    public func resumeAutoReconnect() {
        autoReconnectLock.lock()
        guard _isAutoReconnectPaused else {
            autoReconnectLock.unlock()
            return
        }

        _isAutoReconnectPaused = false

        guard _autoReconnect, connState == .disconnected else {
            hasPausedAutoReconnectAttempt = false
            hasPendingAutoReconnectAttempt = false
            shouldResumeAutoReconnectAfterPendingDisconnect = false
            autoReconnectLock.unlock()
            return
        }

        if pendingSocketDisconnectReconnectAttemptCount != nil {
            // Avoid reconnecting before socketDidDisconnect clears the old socket delegate.
            shouldResumeAutoReconnectAfterPendingDisconnect = true
            autoReconnectLock.unlock()
            return
        }

        guard hasPausedAutoReconnectAttempt || hasPendingAutoReconnectAttempt else {
            autoReconnectLock.unlock()
            return
        }

        if !hasPausedAutoReconnectAttempt {
            prepareAutoReconnectAttempt()
        }
        hasPausedAutoReconnectAttempt = false
        hasPendingAutoReconnectAttempt = false
        let schedule = scheduleAutoReconnectAttemptLocked(after: 0)
        autoReconnectLock.unlock()

        notifyAutoReconnectScheduled(schedule)
    }

    private func expected_disconnect() {
        clientStateLock.lock()
        guard !isExpectedDisconnectPending else {
            clientStateLock.unlock()
            return
        }
        isExpectedDisconnectPending = true
        is_internal_disconnected = true
        clientStateLock.unlock()
        send(FrameDisconnect(), tag: -0xE0, disconnectAfterWriting: true)
    }

    /// Send a PING request to broker
    public func ping() {
        printDebug("ping")
        send(FramePingReq(), tag: -0xC0)

        __delegate_queue { mqtt in
            mqtt.delegate?.mqttDidPing(mqtt)
            mqtt.didPing(mqtt)
        }
    }

    /// Publish a message to broker
    ///
    /// - Parameters:
    ///    - topic: Topic Name. It can not contain '#', '+' wildcards
    ///    - string: Payload string
    ///    - qos: Qos. Default is Qos1
    ///    - retained: Retained flag. Mark this message is a retained message. default is false
    /// - Returns:
    ///     - 0 will be returned, if the message's qos is qos0
    ///     - 1-65535 will be returned, if the messages's qos is qos1/qos2
    ///     - -1 will be returned, if the messages queue is full
    @discardableResult
    public func publish(_ topic: String, withString string: String, qos: CocoaMQTTQoS = .qos1, retained: Bool = false) -> Int {
        let message = CocoaMQTTMessage(topic: topic, string: string, qos: qos, retained: retained)
        return publish(message)
    }

    /// Publish a message to broker
    ///
    /// - Parameters:
    ///   - message: Message
    @discardableResult
    public func publish(_ message: CocoaMQTTMessage) -> Int {
        guard hasValidMQTTTopicName(message.topic),
              message.qos <= .qos2 else {
            printError("Invalid MQTT PUBLISH topic or QoS.")
            return -1
        }
        clientStateLock.lock()
        defer { clientStateLock.unlock() }

        let msgid: UInt16
        let deliveryToken: UInt64

        if message.qos == .qos0 {
            msgid = 0
            deliveryToken = nextDeliveryToken()
        } else {
            guard let identifier = packetIdentifiers.reserve() else {
                printError("No MQTT Packet Identifier is available for PUBLISH.")
                return -1
            }
            msgid = identifier
            deliveryToken = UInt64(msgid)
        }

        var frame = FramePublish(topic: message.topic,
                                 payload: message.payload,
                                 qos: message.qos,
                                 msgid: msgid)

        frame.retained = message.retained
        frame.deliveryToken = deliveryToken

        sendingMessages[deliveryToken] = message

        // Push frame to deliver message queue
        guard deliver.add(frame) else {
            sendingMessages.removeValue(forKey: deliveryToken)
            packetIdentifiers.release(msgid)
            return -1
        }

        return Int(msgid)
    }

    /// Subscribe a `<Topic Name>/<Topic Filter>`
    ///
    /// - Parameters:
    ///   - topic: Topic Name or Topic Filter
    ///   - qos: Qos. Default is qos1
    public func subscribe(_ topic: String, qos: CocoaMQTTQoS = .qos1) {
        return subscribe([(topic, qos)])
    }

    /// Subscribe a lists of topics
    ///
    /// - Parameters:
    ///   - topics: A list of tuples presented by `(<Topic Names>/<Topic Filters>, Qos)`
    public func subscribe(_ topics: [(String, CocoaMQTTQoS)]) {
        guard !topics.isEmpty,
              topics.allSatisfy({ hasValidMQTTTopicFilter($0.0) && $0.1 <= .qos2 }) else {
            printError("Invalid MQTT SUBSCRIBE topic filter or QoS.")
            return
        }
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        guard let msgid = packetIdentifiers.reserve() else {
            printError("No MQTT Packet Identifier is available for SUBSCRIBE.")
            return
        }
        let frame = FrameSubscribe(msgid: msgid, topics: topics)
        subscriptionsWaitingAck[msgid] = topics
        send(frame, tag: Int(msgid))
    }

    /// Unsubscribe a Topic
    ///
    /// - Parameters:
    ///   - topic: A Topic Name or Topic Filter
    public func unsubscribe(_ topic: String) {
        return unsubscribe([topic])
    }

    /// Unsubscribe a list of topics
    ///
    /// - Parameters:
    ///   - topics: A list of `<Topic Names>/<Topic Filters>`
    public func unsubscribe(_ topics: [String]) {
        guard !topics.isEmpty,
              topics.allSatisfy(hasValidMQTTTopicFilter) else {
            printError("Invalid MQTT UNSUBSCRIBE topic filter.")
            return
        }
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        guard let msgid = packetIdentifiers.reserve() else {
            printError("No MQTT Packet Identifier is available for UNSUBSCRIBE.")
            return
        }
        let frame = FrameUnsubscribe(msgid: msgid, topics: topics)
        unsubscriptionsWaitingAck[msgid] = topics
        send(frame, tag: Int(msgid))
    }
}

// MARK: CocoaMQTTDeliverProtocol
extension CocoaMQTT: CocoaMQTTDeliverProtocol {

    func deliver(_ deliver: CocoaMQTTDeliver, didReject frame: Frame) {
        guard let publish = frame as? FramePublish, !publish.isSessionRecovery else { return }
        clientStateLock.lock()
        sendingMessages.removeValue(forKey: publish.deliveryToken ?? UInt64(publish.msgid))
        packetIdentifiers.release(publish.msgid)
        clientStateLock.unlock()
    }

    func deliver(_ deliver: CocoaMQTTDeliver, wantToSend frame: Frame) {
        if let publish = frame as? FramePublish {
            let msgid = publish.msgid
            let deliveryToken = publish.deliveryToken ?? UInt64(msgid)

            var message: CocoaMQTTMessage?

            if let sendingMessage = sendingMessages[deliveryToken] {
                message = sendingMessage
                // printError("Want send \(frame), but not found in CocoaMQTT cache")

            } else {
                message = CocoaMQTTMessage(
                    topic: publish.topic,
                    payload: publish.payload(),
                    qos: publish.qos,
                    retained: publish.retained
                )
            }

            send(publish, tag: Int(msgid))

            if let message = message {
                __delegate_queue { mqtt in
                    mqtt.delegate?.mqtt(mqtt, didPublishMessage: message, id: msgid)
                    mqtt.didPublishMessage(mqtt, message, msgid)
                }
            }
            if publish.qos == .qos0 {
                sendingMessages.removeValue(forKey: deliveryToken)
            }
        } else if let pubrel = frame as? FramePubRel {
            // -- Send PUBREL
            send(pubrel, tag: Int(pubrel.msgid))
        }
    }
}

extension CocoaMQTT {

    func __delegate_queue(
        _ fun: @escaping (CocoaMQTT) -> Void,
        completionOnEventLoop: ((CocoaMQTT) -> Void)? = nil
    ) {
        let callbackQueue = delegateQueue
        callbackQueue.async { [weak self] in
            guard let self = self else { return }
            fun(self)
            guard let completionOnEventLoop = completionOnEventLoop else { return }
            self.eventLoopQueue.async { [weak self] in
                guard let self = self else { return }
                completionOnEventLoop(self)
            }
        }
    }

    private func prepareAutoReconnectAttempt() {
        if reconnectTimeInterval == 0 {
            reconnectTimeInterval = min(autoReconnectTimeInterval, maxAutoReconnectTimeInterval)
        }
        reconnectAttemptCount += 1
    }

    private func updateAutoReconnectIntervalForNextAttempt() {
        let doubledInterval = UInt32(reconnectTimeInterval) * 2
        reconnectTimeInterval = UInt16(min(doubledInterval, UInt32(maxAutoReconnectTimeInterval)))
    }

    private func resetAutoReconnectState() {
        autoReconnectLock.lock()
        reconnectTimeInterval = 0
        reconnectAttemptCount = 0
        _isAutoReconnectPaused = false
        autoReconnTimer = nil
        isAutoReconnectAttemptScheduled = false
        hasPausedAutoReconnectAttempt = false
        hasPendingAutoReconnectAttempt = false
        pendingSocketDisconnectReconnectAttemptCount = nil
        shouldResumeAutoReconnectAfterPendingDisconnect = false
        autoReconnectGeneration &+= 1
        autoReconnectLock.unlock()
    }

    private func notifyAutoReconnectScheduled(_ schedule: CocoaMQTTAutoReconnectSchedule) {
        __delegate_queue { mqtt in
            mqtt.autoReconnectLock.lock()
            let isCurrent = mqtt._autoReconnect && mqtt.autoReconnectGeneration == schedule.generation
            mqtt.autoReconnectLock.unlock()
            guard isCurrent else { return }
            mqtt.delegate?.mqtt?(mqtt, didScheduleReconnect: schedule.attemptCount, after: schedule.interval)
            mqtt.didScheduleReconnect(mqtt, schedule.attemptCount, schedule.interval)
        }
    }

    private func scheduleAutoReconnectAttemptLocked(after interval: UInt16? = nil) -> CocoaMQTTAutoReconnectSchedule {
        let delay = interval ?? reconnectTimeInterval

        printInfo("Try reconnect to server after \(delay)s")
        isAutoReconnectAttemptScheduled = true
        autoReconnectGeneration &+= 1
        let generation = autoReconnectGeneration
        autoReconnTimer = CocoaMQTTTimer.after(Double(delay), name: "autoReconnTimer", { [weak self] in
            self?.eventLoopQueue.async { [weak self] in
                guard let self = self,
                      self.prepareScheduledAutoReconnectFire(generation: generation) else { return }
                _ = self.connect()
            }
        })

        return CocoaMQTTAutoReconnectSchedule(
            attemptCount: reconnectAttemptCount,
            interval: delay,
            generation: generation
        )
    }

    private func prepareScheduledAutoReconnectFire(generation: UInt64) -> Bool {
        autoReconnectLock.lock()
        defer { autoReconnectLock.unlock() }

        guard autoReconnectGeneration == generation else { return false }
        guard _autoReconnect, !_isAutoReconnectPaused else {
            isAutoReconnectAttemptScheduled = false
            return false
        }

        isAutoReconnectAttemptScheduled = false
        updateAutoReconnectIntervalForNextAttempt()
        return true
    }
}

// MARK: - CocoaMQTTSocketDelegate
extension CocoaMQTT: CocoaMQTTSocketDelegate {

    public func socketConnected(_ socket: CocoaMQTTSocketProtocol) {
        clientStateLock.lock()
        isExpectedDisconnectPending = false
        clientStateLock.unlock()
        sendConnectFrame()
    }

    public func socket(_ socket: CocoaMQTTSocketProtocol,
                       didReceive trust: SecTrust,
                       completionHandler: @escaping (Bool) -> Swift.Void) {

        printDebug("Call the SSL/TLS manually validating function")

        __delegate_queue { mqtt in
            mqtt.delegate?.mqtt?(mqtt, didReceive: trust, completionHandler: completionHandler)
            mqtt.didReceiveTrust(mqtt, trust, completionHandler)
        }
    }

    public func socketUrlSession(_ socket: CocoaMQTTSocketProtocol, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        printDebug("Call the SSL/TLS manually validating function - socketUrlSession")

        __delegate_queue { mqtt in
            mqtt.delegate?.mqttUrlSession?(mqtt, didReceiveTrust: trust, didReceiveChallenge: challenge, completionHandler: completionHandler)
        }
    }

    // ?
    public func socketDidSecure(_ sock: MGCDAsyncSocket) {
        printDebug("Socket has successfully completed SSL/TLS negotiation")
        sendConnectFrame()
    }

    public func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {}

    public func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {
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

    public func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError err: Error?) {
        // Clean up
        socket.setDelegate(nil, delegateQueue: nil)
        clientStateLock.lock()
        isExpectedDisconnectPending = false
        // Publish uses the same lock, so queue admission cannot race with the
        // transition from the disconnected session to the next connection.
        deliver.beginConnection()
        clearPendingSubscriptionRequestsLocked()
        let pendingDeliveryTokens = Set(deliver.connectionPendingFrames().compactMap {
            ($0 as? FramePublish)?.deliveryToken
        })
        sendingMessages.removeValues { key, _ in
            key > UInt64(UInt16.max) && !pendingDeliveryTokens.contains(key)
        }
        if cleanSession {
            discardStoredSession()
            discardInMemorySession(preservingConnectionQueue: true)
        }
        clientStateLock.unlock()
        if is_internal_disconnected || !autoReconnect {
            resetAutoReconnectState()
        }

        connState = .disconnected
        autoReconnectLock.lock()
        let reconnectAttemptCountBeforeCallbacks = pendingSocketDisconnectReconnectAttemptCount ?? reconnectAttemptCount
        if !is_internal_disconnected && _autoReconnect {
            pendingSocketDisconnectReconnectAttemptCount = reconnectAttemptCountBeforeCallbacks
        }
        autoReconnectLock.unlock()
        __delegate_queue({ mqtt in
            mqtt.delegate?.mqttDidDisconnect(mqtt, withError: err)
            mqtt.didDisconnect(mqtt, err)
        }, completionOnEventLoop: { mqtt in
            mqtt.continueAfterDisconnectCallbacks(reconnectAttemptCountBeforeCallbacks)
        })
    }

    private func continueAfterDisconnectCallbacks(_ reconnectAttemptCountBeforeCallbacks: UInt) {
        guard !is_internal_disconnected else {
            is_internal_disconnected = false
            return
        }

        guard autoReconnect else {
            resetAutoReconnectState()
            return
        }

        autoReconnectLock.lock()
        pendingSocketDisconnectReconnectAttemptCount = nil
        guard !_isAutoReconnectPaused,
              !isAutoReconnectAttemptScheduled,
              reconnectAttemptCount == reconnectAttemptCountBeforeCallbacks else {
            if _isAutoReconnectPaused,
               !isAutoReconnectAttemptScheduled,
               reconnectAttemptCount == reconnectAttemptCountBeforeCallbacks {
                hasPendingAutoReconnectAttempt = true
            }
            shouldResumeAutoReconnectAfterPendingDisconnect = false
            autoReconnectLock.unlock()
            return
        }

        let shouldResumeAfterPendingDisconnect = shouldResumeAutoReconnectAfterPendingDisconnect
        shouldResumeAutoReconnectAfterPendingDisconnect = false
        if !hasPausedAutoReconnectAttempt {
            prepareAutoReconnectAttempt()
        }
        hasPausedAutoReconnectAttempt = false
        hasPendingAutoReconnectAttempt = false
        let schedule = scheduleAutoReconnectAttemptLocked(after: shouldResumeAfterPendingDisconnect ? 0 : nil)
        autoReconnectLock.unlock()

        notifyAutoReconnectScheduled(schedule)
    }
}

// MARK: - CocoaMQTTReaderDelegate
extension CocoaMQTT: CocoaMQTTReaderDelegate {

    func didReceive(_ reader: CocoaMQTTReader, connack: FrameConnAck) {
        printDebug("RECV: \(connack)")

        if connack.returnCode == .accept {

            // Disable auto-reconnect

            resetAutoReconnectState()
            is_internal_disconnected = false

            // Start keepalive timer

            let interval = Double(keepAlive <= 0 ? 60: keepAlive)

            aliveTimer = CocoaMQTTTimer.every(interval, name: "aliveTimer") { [weak self] in
                guard let self = self else { return }
                self.eventLoopQueue.async {
                    guard self.connState == .connected else {
                        self.aliveTimer = nil
                        return
                    }
                    self.ping()
                }
            }

            // recover session if enable

            if cleanSession || !connack.sessPresent {
                discardCurrentSession(preservingConnectionQueue: true)
                if !cleanSession,
                   let storage = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v311) {
                    deliver.recoverSessionBy(storage)
                }
            } else {
                if let storage = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v311) {
                    deliver.cleanAll(preserveConnectionQueue: true)
                    deliver.recoverSessionBy(storage) { [weak self] frames in
                        guard let self = self else { return }
                        self.clientStateLock.lock()
                        defer { self.clientStateLock.unlock() }
                        for frame in frames {
                            if let publish = frame as? FramePublish {
                                self.packetIdentifiers.markInUse(publish.msgid)
                            } else if let pubrel = frame as? FramePubRel {
                                self.packetIdentifiers.markInUse(pubrel.msgid)
                            }
                        }
                    }
                } else {
                    printWarning("Localstorage initial failed for key: \(clientID)")
                }
            }

            deliver.completeConnection()
            connState = .connected

        } else {
            connState = .disconnected
            internal_disconnect()
        }

        let returnCode = connack.returnCode ?? CocoaMQTTConnAck.serverUnavailable
        __delegate_queue { mqtt in
            mqtt.delegate?.mqtt(mqtt, didConnectAck: returnCode)
            mqtt.didConnectAck(mqtt, returnCode)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, publish: FramePublish) {
        printDebug("RECV: \(publish)")

        let message = CocoaMQTTMessage(topic: publish.topic, payload: publish.payload(), qos: publish.qos, retained: publish.retained)

        message.duplicated = publish.dup

        var shouldDeliver = true
        if message.qos == .qos2 {
            clientStateLock.lock()
            shouldDeliver = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v311)?
                .markReceivedQoS2(publish.msgid) ?? true
            clientStateLock.unlock()
        }

        if shouldDeliver {
            printInfo("Received message: \(message)")
            let messageID = publish.msgid
            __delegate_queue { mqtt in
                mqtt.delegate?.mqtt(mqtt, didReceiveMessage: message, id: messageID)
                mqtt.didReceiveMessage(mqtt, message, messageID)
            }
        }

        if message.qos == .qos1 {
            puback(FrameType.puback, msgid: publish.msgid)
        } else if message.qos == .qos2 {
            puback(FrameType.pubrec, msgid: publish.msgid)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, puback: FramePubAck) {
        printDebug("RECV: \(puback)")

        clientStateLock.lock()
        if deliver.ack(by: puback) {
            sendingMessages.removeValue(forKey: UInt64(puback.msgid))
            packetIdentifiers.release(puback.msgid)
        }
        clientStateLock.unlock()

        let messageID = puback.msgid
        __delegate_queue { mqtt in
            mqtt.delegate?.mqtt(mqtt, didPublishAck: messageID)
            mqtt.didPublishAck(mqtt, messageID)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, pubrec: FramePubRec) {
        printDebug("RECV: \(pubrec)")

        clientStateLock.lock()
        deliver.ack(by: pubrec)
        clientStateLock.unlock()
    }

    func didReceive(_ reader: CocoaMQTTReader, pubrel: FramePubRel) {
        printDebug("RECV: \(pubrel)")

        clientStateLock.lock()
        _ = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v311)?
            .completeReceivedQoS2(pubrel.msgid)
        clientStateLock.unlock()
        puback(FrameType.pubcomp, msgid: pubrel.msgid)
    }

    func didReceive(_ reader: CocoaMQTTReader, pubcomp: FramePubComp) {
        printDebug("RECV: \(pubcomp)")

        clientStateLock.lock()
        if deliver.ack(by: pubcomp) {
            sendingMessages.removeValue(forKey: UInt64(pubcomp.msgid))
            packetIdentifiers.release(pubcomp.msgid)
        }
        clientStateLock.unlock()

        let messageID = pubcomp.msgid
        __delegate_queue { mqtt in
            mqtt.delegate?.mqtt?(mqtt, didPublishComplete: messageID)
            mqtt.didCompletePublish(mqtt, messageID)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, suback: FrameSubAck) {
        printDebug("RECV: \(suback)")
        clientStateLock.lock()
        guard let topicsAndQos = subscriptionsWaitingAck.removeValue(forKey: suback.msgid) else {
            clientStateLock.unlock()
            printWarning("UNEXPECT SUBACK Received: \(suback)")
            return
        }
        packetIdentifiers.release(suback.msgid)
        clientStateLock.unlock()

        guard topicsAndQos.count == suback.grantedQos.count else {
            printError("SUBACK return-code count does not match the SUBSCRIBE request.")
            internal_disconnect()
            return
        }

        let success: NSMutableDictionary = NSMutableDictionary()
        var failed = [String]()
        for (idx, (topic, _)) in topicsAndQos.enumerated() {
            if suback.grantedQos[idx] != .FAILURE {
                subscriptionsStorage[topic] = suback.grantedQos[idx]
                success[topic] = suback.grantedQos[idx].rawValue
            } else {
                failed.append(topic)
            }
        }

        __delegate_queue { mqtt in
            mqtt.delegate?.mqtt(mqtt, didSubscribeTopics: success, failed: failed)
            mqtt.didSubscribeTopics(mqtt, success, failed)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, unsuback: FrameUnsubAck) {
        printDebug("RECV: \(unsuback)")

        clientStateLock.lock()
        guard let topics = unsubscriptionsWaitingAck.removeValue(forKey: unsuback.msgid) else {
            clientStateLock.unlock()
            printWarning("UNEXPECT UNSUBACK Received: \(unsuback.msgid)")
            return
        }
        packetIdentifiers.release(unsuback.msgid)
        clientStateLock.unlock()
        // Remove local subscription
        for t in topics {
            subscriptionsStorage.removeValue(forKey: t)
        }
        __delegate_queue { mqtt in
            mqtt.delegate?.mqtt(mqtt, didUnsubscribeTopics: topics)
            mqtt.didUnsubscribeTopics(mqtt, topics)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, pingresp: FramePingResp) {
        printDebug("RECV: \(pingresp)")

        __delegate_queue { mqtt in
            mqtt.delegate?.mqttDidReceivePong(mqtt)
            mqtt.didReceivePong(mqtt)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, disconnect: FrameDisconnect) {
        printWarning("Received DISCONNECT in MQTT 3.1.1 mode, closing socket")
        internal_disconnect()
    }

    func didReceive(_ reader: CocoaMQTTReader, auth: FrameAuth) {
        printWarning("Received AUTH in MQTT 3.1.1 mode, closing socket")
        internal_disconnect()
    }
}

// For tests
extension CocoaMQTT {
    func t_sendingMessagesCount() -> Int {
        sendingMessages.snapshot().count
    }

    func t_reservedPacketIdentifierCount() -> Int {
        packetIdentifiers.reservedCount
    }

    func t_waitUntilDeliverIdle() {
        deliver.t_waitUntilIdle()
        eventLoopQueue.sync {}
    }
}
