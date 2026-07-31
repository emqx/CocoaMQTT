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

    /// Manually validate an SSL/TLS server certificate.
    ///
    /// Raw sockets call this when manual server trust evaluation is enabled.
    /// WebSockets use it when `mqttUrlSession` is not implemented. This delegate
    /// method takes precedence over the `didReceiveTrust` closure.
    @objc optional func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void)

    /// Handle a URLSession server-trust challenge.
    ///
    /// This method takes precedence over the legacy trust delegate and closure.
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

    /// Maximum time allowed for a socket write. Default is 5 seconds.
    ///
    /// Set this to zero or a negative value to disable the write deadline.
    /// This controls only the client transport deadline; broker packet-size
    /// limits still apply.
    @objc public var socketWriteTimeout: TimeInterval {
        get { configuredSocketWriteTimeout }
        set {
            configuredSocketWriteTimeout = CocoaMQTTSocketWriteTimeout.normalize(newValue)
        }
    }
    @ConcurrentAtomic(
        wrappedValue: CocoaMQTTSocketWriteTimeout.defaultValue,
        label: "CocoaMQTT.socketWriteTimeout"
    )
    private var configuredSocketWriteTimeout

    /// Delegate Executed queue. Default is `DispatchQueue.main`
    ///
    /// The delegate/closure callback function will be committed asynchronously to it.
    /// Changing the queue affects callbacks emitted after the assignment; callbacks
    /// already submitted remain on the queue captured when their event occurred.
    public var delegateQueue: DispatchQueue {
        get { core.delegateQueue }
        set { core.delegateQueue = newValue }
    }

    /// Owns ordered socket, reader, timer, and delivery events. Application code
    /// cannot replace this queue through `delegateQueue`.
    var eventLoopQueue: DispatchQueue { core.eventLoopQueue }
    private var core: MQTTClientCore!

    public var connState: CocoaMQTTConnState {
        get { core.state }
        set { core.state = newValue }
    }

    // deliver
    private var deliver: CocoaMQTTDeliver { core.deliver }

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

    /// Maximum duration in seconds for each Remaining Length byte and the complete payload read.
    /// Each deadline starts with its read and is not reset by partial data. Header reads remain unlimited.
    /// Nonpositive or nonfinite values disable these deadlines. Default is 30 seconds.
    /// Changes take effect on the next connection.
    public var packetReadTimeout: TimeInterval = CocoaMQTTReader.defaultPacketReadTimeout

    /// Enable auto-reconnect mechanism
    public var autoReconnect: Bool {
        get { core.autoReconnect }
        set { core.autoReconnect = newValue }
    }

    /// Reconnect time interval
    ///
    /// - note: This value will be increased with `autoReconnectTimeInterval *= 2`
    ///         if reconnect failed
    public var autoReconnectTimeInterval: UInt16 {
        get { core.autoReconnectTimeInterval }
        set { core.autoReconnectTimeInterval = newValue }
    }

    /// Maximum auto reconnect time interval
    ///
    /// The timer starts from `autoReconnectTimeInterval` second and grows exponentially until this value
    /// After that, it uses this value for subsequent requests.
    public var maxAutoReconnectTimeInterval: UInt16 {
        get { core.maxAutoReconnectTimeInterval }
        set { core.maxAutoReconnectTimeInterval = newValue }
    }

    /// Auto-reconnect backoff interval in seconds for the current reconnect cycle.
    ///
    /// This value is advanced for the next reconnect attempt while auto-reconnect is active,
    /// and resets to `0` when auto-reconnect is inactive.
    public var reconnectTimeInterval: UInt16 { core.reconnectTimeInterval }

    /// Number of reconnect attempts scheduled in the current auto-reconnect cycle.
    ///
    /// The value resets to `0` after a successful connection or expected disconnect.
    public var reconnectAttemptCount: UInt { core.reconnectAttemptCount }

    /// Whether auto-reconnect is currently paused by the application.
    public var isAutoReconnectPaused: Bool {
        core.isAutoReconnectPaused
    }

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
        get { core.enableSSL }
        set { core.enableSSL = newValue }
    }

    ///
    public var sslSettings: [String: NSObject]? {
        get { return (self.socket as? CocoaMQTTSocket)?.sslSettings ?? nil }
        set { (self.socket as? CocoaMQTTSocket)?.sslSettings = newValue }
    }

    /// Server name used for TLS identity verification. Defaults to `host`.
    @objc public var tlsServerName: String? {
        get { return (self.socket as? CocoaMQTTServerTrustConfiguring)?.tlsServerName }
        set { (self.socket as? CocoaMQTTServerTrustConfiguring)?.tlsServerName = newValue }
    }

    /// Additional CA certificates trusted by supported TLS transports.
    public var trustedServerCertificates: [SecCertificate] {
        get { return (self.socket as? CocoaMQTTServerTrustConfiguring)?.trustedServerCertificates ?? [] }
        set { (self.socket as? CocoaMQTTServerTrustConfiguring)?.trustedServerCertificates = newValue }
    }

    /// Client identity sent by transports that support mutual TLS.
    ///
    /// The built-in TCP socket and `URLSessionWebSocketTask` transport support
    /// this capability. Custom transports may opt in by conforming to
    /// `CocoaMQTTClientIdentityConfiguring`.
    public var clientIdentity: CocoaMQTTClientIdentity? {
        get { return (self.socket as? CocoaMQTTClientIdentityConfiguring)?.clientIdentity }
        set { (self.socket as? CocoaMQTTClientIdentityConfiguring)?.clientIdentity = newValue }
    }

    /// Whether custom CA validation also accepts the system trust store.
    @objc public var usesSystemTrustStore: Bool {
        get { return (self.socket as? CocoaMQTTServerTrustConfiguring)?.usesSystemTrustStore ?? true }
        set { (self.socket as? CocoaMQTTServerTrustConfiguring)?.usesSystemTrustStore = newValue }
    }

    /// Gives the trust delegate or `didReceiveTrust` closure first chance to
    /// decide. Configured custom CA certificates remain the fallback; without
    /// either, enabling this setting rejects the connection.
    @objc public var manuallyEvaluateTrust: Bool {
        get { return (self.socket as? CocoaMQTTServerTrustConfiguring)?.manuallyEvaluateTrust ?? false }
        set { (self.socket as? CocoaMQTTServerTrustConfiguring)?.manuallyEvaluateTrust = newValue }
    }

    /// Legacy name for enabling manual trust evaluation.
    ///
    /// Default is false. Setting this does not accept a certificate by itself.
    @available(*, deprecated, renamed: "manuallyEvaluateTrust")
    public var allowUntrustCACertificate: Bool {
        get { return manuallyEvaluateTrust }
        set { manuallyEvaluateTrust = newValue }
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

    private var packetIdentifiers: MQTTPacketIdentifierAllocator { core.packetIdentifiers }
    private var clientStateLock: NSRecursiveLock { core.lifecycleLock }
    private var activeClientID: String
    fileprivate var socket: CocoaMQTTSocketProtocol { core.socket }
    fileprivate var reader: CocoaMQTTReader? { core.reader }

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
    /// Trust fallback used when neither trust delegate method is implemented.
    public var didReceiveTrust: (CocoaMQTT, SecTrust, @escaping (Bool) -> Swift.Void) -> Void {
        get { customDidReceiveTrust ?? { _, _, _ in } }
        set { customDidReceiveTrust = newValue }
    }
    private var customDidReceiveTrust: ((CocoaMQTT, SecTrust, @escaping (Bool) -> Swift.Void) -> Void)?
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
        super.init()
        core = MQTTClientCore(
            socket: socket,
            protocolVersion: .v311,
            queueLabel: "io.emqx.CocoaMQTT.event-loop.\(UUID().uuidString)"
        )
        core.delegate = self
    }

    @discardableResult
    fileprivate func send(_ frame: Frame, tag: Int = 0, disconnectAfterWriting: Bool = false) -> Bool {
        core.send(
            frame,
            version: version,
            timeout: socketWriteTimeout,
            tag: tag,
            disconnectAfterWriting: disconnectAfterWriting
        )
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
        core.nextDeliveryToken()
    }

    fileprivate func discardStoredSession() {
        core.discardStoredSession(clientID: activeClientID, protocolVersion: .v311)
    }

    private func discardCurrentSession(preservingConnectionQueue: Bool = false) {
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        discardStoredSession()
        discardInMemorySession(preservingConnectionQueue: preservingConnectionQueue)
    }

    private func discardInMemorySession(preservingConnectionQueue: Bool = false) {
        core.discardInMemorySession(
            preservingConnectionQueue: preservingConnectionQueue,
            sendingMessages: sendingMessages,
            subscriptionsWaitingAck: subscriptionsWaitingAck,
            unsubscriptionsWaitingAck: unsubscriptionsWaitingAck
        ) {
            subscriptionsStorage.removeAll()
        }
    }

    private func markStoredPacketIdentifiersInUse() {
        core.markStoredPacketIdentifiersInUse(clientID: activeClientID, protocolVersion: .v311)
    }

    /// Callers must hold `clientStateLock`.
    private func clearPendingSubscriptionRequestsLocked() {
        core.clearPendingPacketIdentifiers(
            subscriptionsWaitingAck: subscriptionsWaitingAck,
            unsubscriptionsWaitingAck: unsubscriptionsWaitingAck
        )
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
        return core.connect(
            host: host,
            port: port,
            timeout: timeout,
            protocolVersion: .v311,
            packetReadTimeout: packetReadTimeout,
            readerDelegate: self
        ) {
            deliver.setTransportEnabled(false)
            if activeClientID != clientID {
                discardInMemorySession()
            }
            activeClientID = clientID
            markStoredPacketIdentifiersInUse()
            deliver.beginConnection()
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
        core.disconnectUnexpectedly()
    }

    /// Pause auto-reconnect attempts without disabling `autoReconnect`.
    ///
    /// Use this when the application knows reconnect attempts should not run yet,
    /// for example while waiting for network reachability to recover.
    public func pauseAutoReconnect() {
        core.pauseAutoReconnect()
    }

    /// Resume auto-reconnect attempts after `pauseAutoReconnect()`.
    ///
    /// If an auto-reconnect attempt is pending, this schedules the next reconnect
    /// attempt immediately.
    public func resumeAutoReconnect() {
        core.resumeAutoReconnect()
    }

    private func expected_disconnect() {
        core.disconnectExpectedly {
            send(FrameDisconnect(), tag: -0xE0, disconnectAfterWriting: true)
        }
    }

    /// Send a PING request to broker
    public func ping() {
        core.ping()
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

// MARK: Shared core delivery adapter
extension CocoaMQTT {

    func clientCore(_ core: MQTTClientCore, didReject frame: Frame) {
        guard let publish = frame as? FramePublish, !publish.isSessionRecovery else { return }
        clientStateLock.lock()
        sendingMessages.removeValue(forKey: publish.deliveryToken ?? UInt64(publish.msgid))
        packetIdentifiers.release(publish.msgid)
        clientStateLock.unlock()
    }

    func clientCore(_ core: MQTTClientCore, wantsToSend frame: Frame) {
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
        completionOnEventLoop: ((CocoaMQTT) -> Void)? = nil,
        onDeallocated: (() -> Void)? = nil
    ) {
        let coreCompletion = completionOnEventLoop.map { completion in
            { (delegate: MQTTClientCoreDelegate) in
                guard let mqtt = delegate as? CocoaMQTT else { return }
                completion(mqtt)
            }
        }
        core.dispatchCallback({ delegate in
            guard let mqtt = delegate as? CocoaMQTT else { return }
            fun(mqtt)
        }, completionOnEventLoop: coreCompletion, onDeallocated: onDeallocated)
    }
}

extension CocoaMQTT: MQTTClientCoreDelegate {
    func clientCoreDidConnectTransport(_ core: MQTTClientCore) {
        sendConnectFrame()
    }

    func clientCore(
        _ core: MQTTClientCore,
        didReceive trust: SecTrust,
        completionHandler: @escaping (Bool) -> Void
    ) {
        printDebug("Call the SSL/TLS manually validating function")
        CocoaMQTTTrustHandling.resolveManualTrust(handler: { completion in
            if delegate?.mqtt?(self, didReceive: trust, completionHandler: completion) != nil {
                return true
            }
            guard let handler = customDidReceiveTrust else { return false }
            handler(self, trust, completion)
            return true
        }, fallback: { completion in
            CocoaMQTTServerTrustEvaluator.evaluate(
                trust,
                socket: core.socket,
                defaultServerName: host,
                completionHandler: completion
            )
        }, completionHandler: completionHandler)
    }

    func clientCore(
        _ core: MQTTClientCore,
        didReceiveTrust trust: SecTrust,
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        printDebug("Call the SSL/TLS manually validating function - socketUrlSession")
        CocoaMQTTTrustHandling.resolveURLSessionChallenge(
            urlSessionHandler: { completion in
                delegate?.mqttUrlSession?(
                    self,
                    didReceiveTrust: trust,
                    didReceiveChallenge: challenge,
                    completionHandler: completion
                ) != nil
            },
            legacyHandler: { completion in
                if delegate?.mqtt?(self, didReceive: trust, completionHandler: completion) != nil {
                    return true
                }
                guard let handler = customDidReceiveTrust else { return false }
                handler(self, trust, completion)
                return true
            },
            fallback: { completion in
                CocoaMQTTServerTrustEvaluator.evaluate(
                    trust,
                    socket: core.socket,
                    defaultServerName: challenge.protectionSpace.host,
                    completionHandler: completion
                )
            },
            legacyCredential: URLCredential(trust: trust),
            completionHandler: completionHandler
        )
    }

    func clientCore(_ core: MQTTClientCore, willDisconnectWithError error: Error?) {
        clientStateLock.lock()
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
    }

    func clientCore(_ core: MQTTClientCore, didDisconnectWithError error: Error?) {
        delegate?.mqttDidDisconnect(self, withError: error)
        didDisconnect(self, error)
    }

    func clientCoreRequestsReconnect(_ core: MQTTClientCore) -> Bool {
        connect()
    }

    func clientCoreRequestsPing(_ core: MQTTClientCore) -> Bool {
        printDebug("ping")
        return send(FramePingReq(), tag: -0xC0)
    }

    func clientCoreDidSendPing(_ core: MQTTClientCore) {
        delegate?.mqttDidPing(self)
        didPing(self)
    }

    func clientCore(_ core: MQTTClientCore, didChangeStateTo state: CocoaMQTTConnState) {
        delegate?.mqtt?(self, didStateChangeTo: state)
        didChangeState(self, state)
    }

    func clientCore(
        _ core: MQTTClientCore,
        didScheduleReconnect schedule: CocoaMQTTAutoReconnectSchedule
    ) {
        delegate?.mqtt?(self, didScheduleReconnect: schedule.attemptCount, after: schedule.interval)
        didScheduleReconnect(self, schedule.attemptCount, schedule.interval)
    }
}

// Keep the historical public socket-delegate conformance source-compatible.
// The built-in transport is wired to `MQTTClientCore` directly.
extension CocoaMQTT: CocoaMQTTSocketDelegate {
    public func socketConnected(_ socket: CocoaMQTTSocketProtocol) {
        core.socketConnected(socket)
    }

    public func socket(
        _ socket: CocoaMQTTSocketProtocol,
        didReceive trust: SecTrust,
        completionHandler: @escaping (Bool) -> Void
    ) {
        core.socket(socket, didReceive: trust, completionHandler: completionHandler)
    }

    public func socketUrlSession(
        _ socket: CocoaMQTTSocketProtocol,
        didReceiveTrust trust: SecTrust,
        didReceiveChallenge challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        core.socketUrlSession(
            socket,
            didReceiveTrust: trust,
            didReceiveChallenge: challenge,
            completionHandler: completionHandler
        )
    }

    public func socketDidSecure(_ socket: MGCDAsyncSocket) {
        core.socketDidSecure(socket)
    }

    public func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {
        core.socket(socket, didWriteDataWithTag: tag)
    }

    public func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {
        core.socket(socket, didRead: data, withTag: tag)
    }

    public func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError error: Error?) {
        core.socketDidDisconnect(socket, withError: error)
    }
}

// MARK: - CocoaMQTTReaderDelegate
extension CocoaMQTT: CocoaMQTTReaderDelegate {

    func didReceive(_ reader: CocoaMQTTReader, connack: FrameConnAck) {
        printDebug("RECV: \(connack)")

        if connack.returnCode == .accept {

            // Disable auto-reconnect

            core.connectionSucceeded()

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
            // Start only after session recovery has completed and the client can send PINGREQ.
            core.startKeepAlive(interval: keepAlive)

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
        core.pingResponseReceived()

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

    func t_keepAliveInterval() -> TimeInterval? {
        core.keepAliveInterval
    }

    func t_waitUntilDeliverIdle() {
        deliver.t_waitUntilIdle()
        eventLoopQueue.sync {}
    }
}
