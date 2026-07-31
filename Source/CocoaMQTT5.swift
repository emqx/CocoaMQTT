//
//  CocoaMQTT5.swift
//  CocoaMQTT5
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqx.io. All rights reserved.
//

import Foundation
import MqttCocoaAsyncSocket

/**
 * Connection State
 */
@objc public enum CocoaMQTTConnState: UInt8, CustomStringConvertible {
    case disconnected = 0
    case connecting
    case connected

    public var description: String {
        switch self {
        case .connecting:   return "connecting"
        case .connected:    return "connected"
        case .disconnected: return "disconnected"
        }
    }
}

@objc public enum CocoaMQTT5DisconnectReasonSource: UInt8 {
    case local = 1
    case remote = 2
}

@objcMembers public final class CocoaMQTT5DisconnectReason: NSObject {
    public let source: CocoaMQTT5DisconnectReasonSource
    public let reasonCode: CocoaMQTTDISCONNECTReasonCode

    public init(source: CocoaMQTT5DisconnectReasonSource, reasonCode: CocoaMQTTDISCONNECTReasonCode) {
        self.source = source
        self.reasonCode = reasonCode
    }
}

/// CocoaMQTT5 Delegate
@objc public protocol CocoaMQTT5Delegate {

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode)

    ///
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode)

    ///
    func mqtt5DidPing(_ mqtt5: CocoaMQTT5)

    ///
    func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5)

    ///
    func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?)

    /// Manually validate an SSL/TLS server certificate.
    ///
    /// Raw sockets call this when manual server trust evaluation is enabled.
    /// WebSockets use it when `mqtt5UrlSession` is not implemented. This delegate
    /// method takes precedence over the `didReceiveTrust` closure.
    @objc optional func mqtt5(_ mqtt5: CocoaMQTT5, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void)

    /// Handle a URLSession server-trust challenge.
    ///
    /// This method takes precedence over the legacy trust delegate and closure.
    @objc optional func mqtt5UrlSession(_ mqtt: CocoaMQTT5, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)

    ///
    @objc optional func mqtt5(_ mqtt5: CocoaMQTT5, didPublishComplete id: UInt16, pubCompData: MqttDecodePubComp?)

    ///
    @objc optional func mqtt5(_ mqtt5: CocoaMQTT5, didStateChangeTo state: CocoaMQTTConnState)

    /// Called when auto-reconnect schedules a reconnect attempt after an unexpected disconnect.
    @objc optional func mqtt5(_ mqtt5: CocoaMQTT5, didScheduleReconnect attemptCount: UInt, after interval: UInt16)
}

/// set mqtt version to 5.0
public func setMqtt5Version() {
    if let storage = CocoaMQTTStorage() {
        storage.setMQTTVersion("5.0")
    }
}

/**
 * Blueprint of the MQTT Client
 */
protocol CocoaMQTT5Client {

    /* Basic Properties */

    var host: String { get set }
    var port: UInt16 { get set }
    var clientID: String { get }
    var username: String? {get set}
    var password: String? {get set}
    var cleanSession: Bool {get set}
    var keepAlive: UInt16 {get set}
    var willMessage: CocoaMQTT5Message? {get set}
    var connectProperties: MqttConnectProperties? {get set}
    var authProperties: MqttAuthProperties? {get set}

    /* Basic Properties */

    /* CONNNEC/DISCONNECT */

    func connect() -> Bool
    func connect(timeout: TimeInterval) -> Bool
    func disconnect()
    func ping()

    /* CONNNEC/DISCONNECT */

    /* PUBLISH/SUBSCRIBE */

    func subscribe(_ topic: String, qos: CocoaMQTTQoS)
    func subscribe(_ topics: [MqttSubscription])

    func unsubscribe(_ topic: String)
    func unsubscribe(_ topics: [MqttSubscription])

    func publish(_ topic: String, withString string: String, qos: CocoaMQTTQoS, DUP: Bool, retained: Bool, properties: MqttPublishProperties) -> Int
    func publish(_ message: CocoaMQTT5Message, DUP: Bool, retained: Bool, properties: MqttPublishProperties) -> Int

    /* PUBLISH/SUBSCRIBE */
}

/// MQTT Client
///
/// - Note: MGCDAsyncSocket need delegate to extend NSObject
public class CocoaMQTT5: NSObject, CocoaMQTT5Client {

    public weak var delegate: CocoaMQTT5Delegate?

    private var version = "5.0"

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
    public var willMessage: CocoaMQTT5Message?

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
    /// This controls only the client transport deadline; the server Maximum
    /// Packet Size and other broker limits still apply.
    @objc public var socketWriteTimeout: TimeInterval {
        get { configuredSocketWriteTimeout }
        set {
            configuredSocketWriteTimeout = CocoaMQTTSocketWriteTimeout.normalize(newValue)
        }
    }
    @ConcurrentAtomic(
        wrappedValue: CocoaMQTTSocketWriteTimeout.defaultValue,
        label: "CocoaMQTT5.socketWriteTimeout"
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

    @ConcurrentAtomic(wrappedValue: CocoaMQTTConnState.disconnected, label: "CocoaMQTT5.connState")
    public var connState

    // deliver
    private var deliver: CocoaMQTTDeliver { core.deliver }

    /// Retained for source compatibility. MQTT 5 retransmits unacknowledged
    /// messages only when a persistent session is resumed, so this value does
    /// not schedule retries while a connection remains open.
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

    /// 3.1.2.11 CONNECT Properties
    public var connectProperties: MqttConnectProperties?

    /// 3.15.2.2 AUTH Properties
    public var authProperties: MqttAuthProperties?

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
    private let disconnectReasonLock = NSLock()
    private var pendingLocalDisconnectReasonCode: CocoaMQTTDISCONNECTReasonCode?
    private var _lastDisconnectReason: CocoaMQTT5DisconnectReason?
    private var connectSessionExpiryInterval: UInt32 = 0
    private var connectTopicAliasMaximum: UInt16 = 0
    private var connectReceiveMaximum: UInt16 = UInt16.max
    private var connectAuthenticationMethod: String?
    /// QoS 2 PUBLISH exchanges received on the current Network Connection and
    /// still awaiting PUBCOMP. This is intentionally separate from the persisted
    /// QoS 2 identifiers used to de-duplicate messages across Session resumes.
    private var connectionReceivedQoS2Identifiers = Set<UInt16>()
    private let topicAliases = MQTT5TopicAliasStore()
    private var sessionExpiryController: MQTT5SessionExpiryController?
    private var sessionExpiryControllerClientID: String?
    private var sessionExpiryControllers = [String: MQTT5SessionExpiryController]()
    private var activeClientID: String
    private var clientStateLock: NSRecursiveLock { core.lifecycleLock }
    private var serverMaximumQoS = CocoaMQTTQoS.qos2
    private var serverRetainAvailable = true
    private var serverMaximumPacketSize = UInt32.max
    private var serverWildcardSubscriptionAvailable = true
    private var serverSubscriptionIdentifiersAvailable = true
    private var serverSharedSubscriptionAvailable = true

    /// The last MQTT 5 DISCONNECT reason observed for the current connection lifecycle.
    ///
    /// This is set before `mqtt5DidDisconnect(_:withError:)` / `didDisconnect` callbacks run.
    /// It is `nil` for transport errors or clean socket closes without an MQTT DISCONNECT reason.
    @objc public var lastDisconnectReason: CocoaMQTT5DisconnectReason? {
        disconnectReasonLock.lock()
        defer { disconnectReasonLock.unlock() }
        return _lastDisconnectReason
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
    public var subscriptions = ThreadSafeDictionary<String, CocoaMQTTQoS>(label: "subscriptions")

    fileprivate var subscriptionsWaitingAck = ThreadSafeDictionary<UInt16, [MqttSubscription]>(label: "subscriptionsWaitingAck")
    fileprivate var unsubscriptionsWaitingAck = ThreadSafeDictionary<UInt16, [MqttSubscription]>(label: "unsubscriptionsWaitingAck")

    /// Sending messages
    fileprivate var sendingMessages = ThreadSafeDictionary<UInt64, CocoaMQTT5Message>(label: "sendingMessages5")

    private var packetIdentifiers: MQTTPacketIdentifierAllocator { core.packetIdentifiers }
    fileprivate var socket: CocoaMQTTSocketProtocol { core.socket }
    fileprivate var reader: CocoaMQTTReader? { core.reader }

    // Closures
    public var didConnectAck: (CocoaMQTT5, CocoaMQTTCONNACKReasonCode, MqttDecodeConnAck?) -> Void = { _, _, _ in }
    public var didPublishMessage: (CocoaMQTT5, CocoaMQTT5Message, UInt16) -> Void = { _, _, _ in }
    public var didPublishAck: (CocoaMQTT5, UInt16, MqttDecodePubAck?) -> Void = { _, _, _ in }
    public var didPublishRec: (CocoaMQTT5, UInt16, MqttDecodePubRec?) -> Void = { _, _, _ in }
    public var didReceiveMessage: (CocoaMQTT5, CocoaMQTT5Message, UInt16, MqttDecodePublish?) -> Void = { _, _, _, _ in }
    public var didSubscribeTopics: (CocoaMQTT5, NSDictionary, [String], MqttDecodeSubAck?) -> Void = { _, _, _, _  in }
    public var didUnsubscribeTopics: (CocoaMQTT5, [String], MqttDecodeUnsubAck?) -> Void = { _, _, _ in }
    public var didPing: (CocoaMQTT5) -> Void = { _ in }
    public var didReceivePong: (CocoaMQTT5) -> Void = { _ in }
    public var didDisconnect: (CocoaMQTT5, Error?) -> Void = { _, _ in }
    public var didDisconnectReasonCode: (CocoaMQTT5, CocoaMQTTDISCONNECTReasonCode) -> Void = { _, _ in }
    public var didAuthReasonCode: (CocoaMQTT5, CocoaMQTTAUTHReasonCode) -> Void = { _, _ in }
    /// Trust fallback used when neither trust delegate method is implemented.
    public var didReceiveTrust: (CocoaMQTT5, SecTrust, @escaping (Bool) -> Swift.Void) -> Void {
        get { customDidReceiveTrust ?? { _, _, _ in } }
        set { customDidReceiveTrust = newValue }
    }
    private var customDidReceiveTrust: ((CocoaMQTT5, SecTrust, @escaping (Bool) -> Swift.Void) -> Void)?
    public var didCompletePublish: (CocoaMQTT5, UInt16, MqttDecodePubComp?) -> Void = { _, _, _ in }
    public var didChangeState: (CocoaMQTT5, CocoaMQTTConnState) -> Void = { _, _ in }
    public var didScheduleReconnect: (CocoaMQTT5, UInt, UInt16) -> Void = { _, _, _ in }

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
            state: $connState,
            protocolVersion: .v5,
            queueLabel: "io.emqx.CocoaMQTT5.event-loop.\(UUID().uuidString)"
        )
        core.delegate = self
        configureSessionExpiryController(for: clientID)
    }

    deinit {
        sessionExpiryController?.handleDisconnect()
    }

    @discardableResult
    fileprivate func send(_ frame: Frame, tag: Int = 0, disconnectAfterWriting: Bool = false) -> Bool {
        clientStateLock.lock()
        let maximumPacketSize = serverMaximumPacketSize
        clientStateLock.unlock()
        return core.send(
            frame,
            version: version,
            timeout: socketWriteTimeout,
            maximumPacketSize: maximumPacketSize,
            tag: tag,
            disconnectAfterWriting: disconnectAfterWriting
        )
    }

    fileprivate func sendConnectFrame() {
        guard connectProperties?.isValid() ?? true else {
            printError("Invalid MQTT 5 CONNECT properties.")
            internal_disconnect()
            return
        }

        var connect = FrameConnect(clientID: activeClientID)
        connect.keepAlive = keepAlive
        connect.username = username
        connect.password = password
        connect.willMsg5 = willMessage
        connect.cleansess = cleanSession

        connect.connectProperties = connectProperties
        connectSessionExpiryInterval = connectProperties?.sessionExpiryInterval ?? 0
        connectTopicAliasMaximum = connectProperties?.topicAliasMaximum ?? 0
        connectReceiveMaximum = connectProperties?.receiveMaximum ?? UInt16.max
        connectAuthenticationMethod = connectProperties?.authenticationMethod
        clientStateLock.lock()
        connectionReceivedQoS2Identifiers.removeAll(keepingCapacity: true)
        clientStateLock.unlock()

        send(connect)
        reader!.start()
    }

    fileprivate func nextDeliveryToken() -> UInt64 {
        core.nextDeliveryToken()
    }

    fileprivate func discardStoredSession() {
        core.discardStoredSession(clientID: activeClientID, protocolVersion: .v5)
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
            subscriptions.removeAll()
        }
    }

    private func markStoredPacketIdentifiersInUse() {
        core.markStoredPacketIdentifiersInUse(clientID: activeClientID, protocolVersion: .v5)
    }

    private func configureSessionExpiryController(for clientID: String) {
        if sessionExpiryControllerClientID == clientID, sessionExpiryController != nil {
            return
        }
        if let existing = sessionExpiryControllers[clientID] {
            sessionExpiryControllerClientID = clientID
            sessionExpiryController = existing
            return
        }
        sessionExpiryControllerClientID = clientID
        let controller = MQTT5SessionExpiryController(
            clientID: clientID,
            discardSession: { [weak self] in
                guard let self = self else { return }
                self.clientStateLock.lock()
                if self.activeClientID == clientID {
                    self.discardInMemorySession(preservingConnectionQueue: true)
                }
                self.clientStateLock.unlock()
            }
        )
        sessionExpiryControllers[clientID] = controller
        sessionExpiryController = controller
    }

    /// Callers must hold `clientStateLock`.
    private func clearPendingSubscriptionRequestsLocked() {
        core.clearPendingPacketIdentifiers(
            subscriptionsWaitingAck: subscriptionsWaitingAck,
            unsubscriptionsWaitingAck: unsubscriptionsWaitingAck
        )
    }

    /// Restore values that apply before a server has negotiated limits for a
    /// network connection. Callers must hold `clientStateLock`.
    private func resetServerCapabilities() {
        serverMaximumQoS = .qos2
        serverRetainAvailable = true
        serverMaximumPacketSize = UInt32.max
        serverWildcardSubscriptionAvailable = true
        serverSubscriptionIdentifiersAvailable = true
        serverSharedSubscriptionAvailable = true
        deliver.configureServerLimits(
            receiveMaximum: UInt16.max,
            maximumPacketSize: UInt32.max,
            maximumQoS: .qos2,
            retainAvailable: true
        )
    }

    fileprivate func puback(_ type: FrameType,
                            msgid: UInt16,
                            pubCompReasonCode: CocoaMQTTPUBCOMPReasonCode = .success) {
        let sent: Bool
        switch type {
        case .puback:
            sent = send(FramePubAck(msgid: msgid, reasonCode: CocoaMQTTPUBACKReasonCode.success))
        case .pubrec:
            sent = send(FramePubRec(msgid: msgid, reasonCode: CocoaMQTTPUBRECReasonCode.success))
        case .pubcomp:
            sent = send(FramePubComp(msgid: msgid, reasonCode: pubCompReasonCode))
        default: return
        }
        if !sent {
            internal_disconnect()
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
              willMessage?.isValidWill() ?? true,
              connectProperties?.isValid() ?? true else {
            printError("Invalid MQTT 5 CONNECT properties.")
            return false
        }
        // Publish uses the same lock, so pausing transport and starting the
        // connection queue are atomic relative to queue admission.
        resetDisconnectReasonState()
        sessionExpiryController?.prepareStoredSessionForConnect()
        return core.connect(
            host: host,
            port: port,
            timeout: timeout,
            protocolVersion: .v5,
            maximumPacketSize: connectProperties?.maximumPacketSize,
            packetReadTimeout: packetReadTimeout,
            readerDelegate: self
        ) {
            deliver.setTransportEnabled(false)
            if activeClientID != clientID {
                discardInMemorySession()
            }
            activeClientID = clientID
            resetServerCapabilities()
            topicAliases.clear()
            configureSessionExpiryController(for: activeClientID)
            markStoredPacketIdentifiersInUse()
            deliver.beginConnection()
        }
    }

    /// Send a DISCONNECT packet to the broker then close the connection
    ///
    /// - Note: Only can be called from outside.
    ///         This closes the connection expectedly, so auto-reconnect will not run.
    public func disconnect() {
        expected_disconnect(reasonCode: .normalDisconnection, recordsLocalReason: true)
    }

    public func disconnect(reasonCode: CocoaMQTTDISCONNECTReasonCode, userProperties: [String: String] ) {
        guard hasValidMQTTUserProperties(userProperties) else {
            printError("Invalid MQTT 5 DISCONNECT User Properties.")
            return
        }
        expected_disconnect(reasonCode: reasonCode, userProperties: userProperties, recordsLocalReason: true)
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

    func internal_disconnect_withProperties(reasonCode: CocoaMQTTDISCONNECTReasonCode, userProperties: [String: String] ) {
        expected_disconnect(reasonCode: reasonCode, userProperties: userProperties)
    }

    private func expected_disconnect(reasonCode: CocoaMQTTDISCONNECTReasonCode,
                                     userProperties: [String: String]? = nil,
                                     recordsLocalReason: Bool = false) {
        core.disconnectExpectedly(prepare: {
            if recordsLocalReason {
                markPendingLocalDisconnect(reasonCode: reasonCode)
            }
        }, sendDisconnect: {
            var frameDisconnect = FrameDisconnect(disconnectReasonCode: reasonCode)
            frameDisconnect.userProperties = userProperties ?? [:]
            return send(frameDisconnect, tag: -0xE0, disconnectAfterWriting: true)
        })
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
    ///    - properties: Publish Properties
    /// - Returns:
    ///     - 0 will be returned, if the message's qos is qos0
    ///     - 1-65535 will be returned, if the messages's qos is qos1/qos2
    ///     - -1 will be returned, if the messages queue is full
    @discardableResult
    public func publish(_ topic: String, withString string: String, qos: CocoaMQTTQoS = .qos1, DUP: Bool = false, retained: Bool = false, properties: MqttPublishProperties) -> Int {
        guard !(DUP && qos == .qos0) else {
            printError("Invalid PUBLISH flags: DUP=true requires QoS1 or QoS2.")
            return -1
        }
        let message = CocoaMQTT5Message(topic: topic, string: string, qos: qos, retained: retained)
        return publish(message, DUP: DUP, retained: retained, properties: properties)
    }

    /// Publish a message to broker
    ///
    /// - Parameters:
    ///   - message: Message
    ///   - properties: Publish Properties
    @discardableResult
    public func publish(_ message: CocoaMQTT5Message, DUP: Bool = false, retained: Bool = false, properties: MqttPublishProperties) -> Int {
        guard !(DUP && message.qos == .qos0) else {
            printError("Invalid PUBLISH flags: DUP=true requires QoS1 or QoS2.")
            return -1
        }
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        guard message.qos <= serverMaximumQoS,
              !message.retained || serverRetainAvailable,
              properties.isValid(forTopic: message.topic, payload: message.payload),
              let persistenceTopic = topicAliases.resolvedOutboundTopic(
                topic: message.topic,
                alias: properties.topicAlias
              ) else {
            printError("Invalid MQTT 5 PUBLISH topic, QoS, payload, or properties.")
            return -1
        }

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

        printDebug("message.topic \(message.topic )   = message.payload \(message.payload)")

        var frame = FramePublish(topic: message.topic,
                                 payload: message.payload,
                                 qos: message.qos,
                                 msgid: msgid)
        frame.qos = message.qos
        frame.dup = DUP
        frame.snapshotPublishProperties(properties)
        frame.retained = message.retained
        frame.deliveryToken = deliveryToken
        if message.topic.isEmpty {
            frame.persistenceTopic = persistenceTopic
        }

        guard UInt64(frame.bytes(version: version).count) <= UInt64(serverMaximumPacketSize) else {
            packetIdentifiers.release(msgid)
            printError("PUBLISH exceeds the server Maximum Packet Size.")
            return -1
        }

        sendingMessages[deliveryToken] = message

        // Push frame to deliver message queue
        guard deliver.add(frame) else {
            sendingMessages.removeValue(forKey: deliveryToken)
            packetIdentifiers.release(msgid)
            return -1
        }
        topicAliases.recordOutbound(alias: properties.topicAlias, topic: message.topic)

        return Int(msgid)
    }

    /// Subscribe a `<Topic Name>/<Topic Filter>`
    ///
    /// - Parameters:
    ///   - topic: Topic Name or Topic Filter
    ///   - qos: Qos. Default is qos1
    public func subscribe(_ topic: String, qos: CocoaMQTTQoS = .qos1) {
        let filter = MqttSubscription(topic: topic, qos: qos)
        return subscribe([filter])
    }

    /// Subscribe a lists of topics
    ///
    /// - Parameters:
    ///   - topics: A list of tuples presented by `(<Topic Names>/<Topic Filters>, Qos)`
    public func subscribe(_ topics: [MqttSubscription]) {
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        guard !topics.isEmpty,
              topics.allSatisfy({ subscriptionIsAllowed($0, subscriptionIdentifier: nil) }) else {
            printError("Invalid MQTT 5 SUBSCRIBE topic filter or QoS.")
            return
        }
        guard let msgid = packetIdentifiers.reserve() else {
            printError("No MQTT Packet Identifier is available for SUBSCRIBE.")
            return
        }
        let frame = FrameSubscribe(msgid: msgid, subscriptionList: topics)
        guard packetFitsServerMaximum(frame) else {
            packetIdentifiers.release(msgid)
            return
        }
        subscriptionsWaitingAck[msgid] = topics
        send(frame, tag: Int(msgid))
    }

    /// Subscribe a lists of topics
    ///
    /// - Parameters:
    ///   - topics: A list of tuples presented by `(<Topic Names>/<Topic Filters>, Qos)`
    ///   - packetIdentifier: SUBSCRIBE Variable Header
    ///   - subscriptionIdentifier: Subscription Identifier
    ///   - userProperty: User Property
    public func subscribe(_ topics: [MqttSubscription], packetIdentifier: UInt16? = nil, subscriptionIdentifier: UInt32? = nil, userProperty: [String: String] = [:]) {
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        guard !topics.isEmpty,
              topics.allSatisfy({ subscriptionIsAllowed($0, subscriptionIdentifier: subscriptionIdentifier) }),
              subscriptionIdentifier.map({ $0 > 0 && $0 <= 0x0fff_ffff }) ?? true,
              hasValidMQTTUserProperties(userProperty) else {
            printError("Invalid MQTT 5 SUBSCRIBE topic filter, QoS, or properties.")
            return
        }
        let msgid: UInt16
        if let requestedIdentifier = packetIdentifier {
            guard packetIdentifiers.reserve(requestedIdentifier) else {
                printError("The requested MQTT Packet Identifier is already in use or invalid.")
                return
            }
            msgid = requestedIdentifier
        } else {
            guard let identifier = packetIdentifiers.reserve() else {
                printError("No MQTT Packet Identifier is available for SUBSCRIBE.")
                return
            }
            msgid = identifier
        }
        let frame = FrameSubscribe(msgid: msgid, subscriptionList: topics, packetIdentifier: packetIdentifier, subscriptionIdentifier: subscriptionIdentifier, userProperty: userProperty)
        guard packetFitsServerMaximum(frame) else {
            packetIdentifiers.release(msgid)
            return
        }
        subscriptionsWaitingAck[msgid] = topics
        send(frame, tag: Int(msgid))
    }

    /// Unsubscribe a Topic
    ///
    /// - Parameters:
    ///   - topic: A Topic Name or Topic Filter
    public func unsubscribe(_ topic: String) {
        let filter = MqttSubscription(topic: topic)
        return unsubscribe([filter])
    }

    /// Unsubscribe a list of topics
    ///
    /// - Parameters:
    ///   - topics: A list of `<Topic Names>/<Topic Filters>`
    public func unsubscribe(_ topics: [MqttSubscription]) {
        guard !topics.isEmpty,
              topics.allSatisfy({ hasValidMQTTTopicFilter($0.topic) && hasValidMQTTSharedSubscription($0.topic) }) else {
            printError("Invalid MQTT 5 UNSUBSCRIBE topic filter.")
            return
        }
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        guard let msgid = packetIdentifiers.reserve() else {
            printError("No MQTT Packet Identifier is available for UNSUBSCRIBE.")
            return
        }
        let frame = FrameUnsubscribe(msgid: msgid, topics: topics)
        guard packetFitsServerMaximum(frame) else {
            packetIdentifiers.release(msgid)
            return
        }
        unsubscriptionsWaitingAck[msgid] = topics
        send(frame, tag: Int(msgid))
    }

    ///  Authentication exchange
    ///
    ///
    public func auth(reasonCode: CocoaMQTTAUTHReasonCode, authProperties: MqttAuthProperties) {
        guard let connectAuthenticationMethod = connectAuthenticationMethod,
              authProperties.isValid(expectedAuthenticationMethod: connectAuthenticationMethod) else {
            printError("Invalid MQTT 5 AUTH properties or Authentication Method mismatch.")
            return
        }
        printDebug("auth")
        let frame = FrameAuth(reasonCode: reasonCode, authProperties: authProperties)

        guard packetFitsServerMaximum(frame) else { return }
        send(frame)
    }

    private func subscriptionIsAllowed(_ subscription: MqttSubscription,
                                       subscriptionIdentifier: UInt32?) -> Bool {
        let filter = subscription.topic
        guard hasValidMQTTTopicFilter(filter),
              hasValidMQTTSharedSubscription(filter),
              subscription.qos <= .qos2 else { return false }
        if !serverWildcardSubscriptionAvailable,
           filter.contains("+") || filter.contains("#") {
            return false
        }
        if !serverSharedSubscriptionAvailable, isMQTTSharedSubscription(filter) {
            return false
        }
        if isMQTTSharedSubscription(filter), subscription.noLocal {
            return false
        }
        return subscriptionIdentifier == nil || serverSubscriptionIdentifiersAvailable
    }

    private func packetFitsServerMaximum(_ frame: Frame) -> Bool {
        clientStateLock.lock()
        let maximumPacketSize = serverMaximumPacketSize
        clientStateLock.unlock()
        let fits = UInt64(frame.bytes(version: version).count) <= UInt64(maximumPacketSize)
        if !fits {
            printError("Packet exceeds the server Maximum Packet Size: \(frame)")
        }
        return fits
    }
}

// MARK: Shared core delivery adapter
extension CocoaMQTT5 {

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
            var message: CocoaMQTT5Message?

            if let sendingMessage = sendingMessages[deliveryToken] {
                message = sendingMessage
                // printError("Want send \(frame), but not found in CocoaMQTT cache")
            } else {
                message = CocoaMQTT5Message(
                    topic: publish.topic,
                    payload: publish.payload(),
                    qos: publish.qos,
                    retained: publish.retained
                )
            }

            guard send(publish, tag: Int(msgid)) else {
                internal_disconnect()
                return
            }

            if let message = message {
                __delegate_queue { mqtt5 in
                    mqtt5.delegate?.mqtt5(mqtt5, didPublishMessage: message, id: msgid)
                    mqtt5.didPublishMessage(mqtt5, message, msgid)
                }
            }
            if publish.qos == .qos0 {
                sendingMessages.removeValue(forKey: deliveryToken)
            }
        } else if let pubrel = frame as? FramePubRel {
            // -- Send PUBREL
            if !send(pubrel, tag: Int(pubrel.msgid)) {
                internal_disconnect()
            }
        }
    }
}

extension CocoaMQTT5 {

    func __delegate_queue(
        _ fun: @escaping (CocoaMQTT5) -> Void,
        completionOnEventLoop: ((CocoaMQTT5) -> Void)? = nil,
        onDeallocated: (() -> Void)? = nil
    ) {
        let coreCompletion = completionOnEventLoop.map { completion in
            { (delegate: MQTTClientCoreDelegate) in
                guard let mqtt5 = delegate as? CocoaMQTT5 else { return }
                completion(mqtt5)
            }
        }
        core.dispatchCallback({ delegate in
            guard let mqtt5 = delegate as? CocoaMQTT5 else { return }
            fun(mqtt5)
        }, completionOnEventLoop: coreCompletion, onDeallocated: onDeallocated)
    }

    private func resetDisconnectReasonState() {
        disconnectReasonLock.lock()
        pendingLocalDisconnectReasonCode = nil
        _lastDisconnectReason = nil
        disconnectReasonLock.unlock()
    }

    private func markPendingLocalDisconnect(reasonCode: CocoaMQTTDISCONNECTReasonCode) {
        disconnectReasonLock.lock()
        pendingLocalDisconnectReasonCode = reasonCode
        _lastDisconnectReason = nil
        disconnectReasonLock.unlock()
    }

    private func recordRemoteDisconnect(reasonCode: CocoaMQTTDISCONNECTReasonCode) {
        disconnectReasonLock.lock()
        pendingLocalDisconnectReasonCode = nil
        _lastDisconnectReason = CocoaMQTT5DisconnectReason(source: .remote, reasonCode: reasonCode)
        disconnectReasonLock.unlock()
    }

    private func updateDisconnectReasonAfterSocketDisconnect(error: Error?) {
        disconnectReasonLock.lock()
        defer {
            pendingLocalDisconnectReasonCode = nil
            disconnectReasonLock.unlock()
        }

        if error != nil {
            _lastDisconnectReason = nil
        } else if let reasonCode = pendingLocalDisconnectReasonCode {
            _lastDisconnectReason = CocoaMQTT5DisconnectReason(source: .local, reasonCode: reasonCode)
        } else if _lastDisconnectReason?.source != .remote {
            _lastDisconnectReason = nil
        }
    }
}

extension CocoaMQTT5: MQTTClientCoreDelegate {
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
            if delegate?.mqtt5?(self, didReceive: trust, completionHandler: completion) != nil {
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
                delegate?.mqtt5UrlSession?(
                    self,
                    didReceiveTrust: trust,
                    didReceiveChallenge: challenge,
                    completionHandler: completion
                ) != nil
            },
            legacyHandler: { completion in
                if delegate?.mqtt5?(self, didReceive: trust, completionHandler: completion) != nil {
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
        topicAliases.clear()
        resetServerCapabilities()
        clearPendingSubscriptionRequestsLocked()
        connectionReceivedQoS2Identifiers.removeAll(keepingCapacity: true)
        let pendingDeliveryTokens = Set(deliver.connectionPendingFrames().compactMap {
            ($0 as? FramePublish)?.deliveryToken
        })
        sendingMessages.removeValues { key, _ in
            key > UInt64(UInt16.max) && !pendingDeliveryTokens.contains(key)
        }
        clientStateLock.unlock()
        sessionExpiryController?.handleDisconnect()
        updateDisconnectReasonAfterSocketDisconnect(error: error)
    }

    func clientCore(_ core: MQTTClientCore, didDisconnectWithError error: Error?) {
        delegate?.mqtt5DidDisconnect(self, withError: error)
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
        delegate?.mqtt5DidPing(self)
        didPing(self)
    }

    func clientCore(_ core: MQTTClientCore, didChangeStateTo state: CocoaMQTTConnState) {
        delegate?.mqtt5?(self, didStateChangeTo: state)
        didChangeState(self, state)
    }

    func clientCore(
        _ core: MQTTClientCore,
        didScheduleReconnect schedule: CocoaMQTTAutoReconnectSchedule
    ) {
        delegate?.mqtt5?(self, didScheduleReconnect: schedule.attemptCount, after: schedule.interval)
        didScheduleReconnect(self, schedule.attemptCount, schedule.interval)
    }
}

// Keep the historical public socket-delegate conformance source-compatible.
// The built-in transport is wired to `MQTTClientCore` directly.
extension CocoaMQTT5: CocoaMQTTSocketDelegate {
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
extension CocoaMQTT5: CocoaMQTTReaderDelegate {

    func didReceive(_ reader: CocoaMQTTReader, disconnect: FrameDisconnect) {
        let reasonCode = disconnect.receiveReasonCode ?? .normalDisconnection
        recordRemoteDisconnect(reasonCode: reasonCode)
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didReceiveDisconnectReasonCode: reasonCode)
            mqtt5.didDisconnectReasonCode(mqtt5, reasonCode)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, auth: FrameAuth) {
        guard connectAuthenticationMethod != nil,
              auth.authProperties?.authenticationMethod == connectAuthenticationMethod else {
            printError("Received MQTT 5 AUTH with an unexpected Authentication Method.")
            internal_disconnect()
            return
        }
        let reasonCode = auth.receiveReasonCode ?? .success
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didReceiveAuthReasonCode: reasonCode)
            mqtt5.didAuthReasonCode(mqtt5, reasonCode)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, connack: FrameConnAck) {
        printDebug("RECV: \(connack)")

        if connack.reasonCode == .success {

            let properties = connack.connackProperties

            guard !cleanSession || !connack.sessPresent else {
                printError("Broker returned Session Present for a Clean Start connection.")
                connState = .disconnected
                internal_disconnect()
                return
            }
            guard connack.connackProperties?.authenticationMethod == connectAuthenticationMethod else {
                printError("CONNACK Authentication Method does not match CONNECT.")
                connState = .disconnected
                internal_disconnect()
                return
            }

            if activeClientID.isEmpty {
                guard let assignedClientID = properties?.assignedClientIdentifier,
                      hasValidMQTTUTF8Length(assignedClientID) else {
                    printError("Successful CONNACK did not assign a valid Client Identifier.")
                    connState = .disconnected
                    internal_disconnect()
                    return
                }
                clientStateLock.lock()
                activeClientID = assignedClientID
                clientID = assignedClientID
                configureSessionExpiryController(for: assignedClientID)
                clientStateLock.unlock()
            } else if properties?.assignedClientIdentifier != nil {
                printError("Broker assigned a Client Identifier when CONNECT supplied one.")
                connState = .disconnected
                internal_disconnect()
                return
            }

            clientStateLock.lock()
            serverMaximumQoS = properties?.maximumQoS ?? .qos2
            serverRetainAvailable = properties?.retainAvailable ?? true
            serverMaximumPacketSize = properties?.maximumPacketSize ?? UInt32.max
            serverWildcardSubscriptionAvailable = properties?.wildcardSubscriptionAvailable ?? true
            serverSubscriptionIdentifiersAvailable = properties?.subscriptionIdentifiersAvailable ?? true
            serverSharedSubscriptionAvailable = properties?.sharedSubscriptionAvailable ?? true
            deliver.configureServerLimits(
                receiveMaximum: properties?.receiveMaximum ?? UInt16.max,
                maximumPacketSize: serverMaximumPacketSize,
                maximumQoS: serverMaximumQoS,
                retainAvailable: serverRetainAvailable
            )
            clientStateLock.unlock()

            // Disable auto-reconnect

            core.connectionSucceeded()

            let negotiatedKeepAlive = properties?.serverKeepAlive ?? keepAlive

            // recover session if enable

            let expiryInterval = connack.connackProperties?.sessionExpiryInterval
                ?? connectSessionExpiryInterval
            sessionExpiryController?.begin(expiryInterval: expiryInterval)

            if cleanSession || !connack.sessPresent {
                discardCurrentSession(preservingConnectionQueue: true)
                if expiryInterval > 0,
                   let storage = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v5) {
                    deliver.recoverSessionBy(storage)
                }
            } else {
                if let storage = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v5) {
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
            topicAliases.configure(
                inboundMaximum: connectTopicAliasMaximum,
                outboundMaximum: connack.connackProperties?.topicAliasMaximum ?? 0
            )

            deliver.completeConnection()
            connState = .connected
            // Start only after session recovery has completed and the client can send PINGREQ.
            core.startKeepAlive(interval: negotiatedKeepAlive)

        } else {
            connState = .disconnected
            internal_disconnect()
        }

        let reasonCode = connack.reasonCode ?? CocoaMQTTCONNACKReasonCode.unspecifiedError
        let properties = connack.connackProperties
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didConnectAck: reasonCode, connAckData: properties)
            mqtt5.didConnectAck(mqtt5, reasonCode, properties)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, publish: FramePublish) {
        printDebug("RECV: \(publish)")

        guard let publishData = publish.publishRecProperties,
              let topic = topicAliases.resolveInbound(topic: publishData.topic,
                                                       alias: publishData.topicAlias) else {
            printError("Received an invalid or unknown MQTT 5 Topic Alias.")
            internal_disconnect()
            return
        }
        publish.publishRecProperties?.topic = topic
        let message = CocoaMQTT5Message(topic: topic, payload: publish.payload5(), qos: publish.qos, retained: publish.retained)

        message.duplicated = publish.dup
        message.contentType = publish.publishRecProperties?.contentType

        var shouldDeliver = true
        if message.qos == .qos2 {
            clientStateLock.lock()
            let storage = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v5)
            let receiveMaximum = Int(connectReceiveMaximum)
            if !connectionReceivedQoS2Identifiers.contains(publish.msgid),
               connectionReceivedQoS2Identifiers.count >= receiveMaximum {
                clientStateLock.unlock()
                printError("Received QoS 2 PUBLISH beyond the client Receive Maximum.")
                internal_disconnect_withProperties(reasonCode: .receiveMaximumExceeded, userProperties: [:])
                return
            }
            connectionReceivedQoS2Identifiers.insert(publish.msgid)
            shouldDeliver = storage?.markReceivedQoS2(publish.msgid) ?? true
            clientStateLock.unlock()
        }

        if shouldDeliver {
            printInfo("Received message: \(message)")
            let messageID = publish.msgid
            let properties = publish.publishRecProperties
            __delegate_queue { mqtt5 in
                mqtt5.delegate?.mqtt5(mqtt5, didReceiveMessage: message, id: messageID, publishData: properties)
                mqtt5.didReceiveMessage(mqtt5, message, messageID, properties)
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
        let properties = puback.pubAckProperties
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didPublishAck: messageID, pubAckData: properties)
            mqtt5.didPublishAck(mqtt5, messageID, properties)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, pubrec: FramePubRec) {
        printDebug("RECV: \(pubrec)")

        clientStateLock.lock()
        if deliver.ack(by: pubrec) {
            sendingMessages.removeValue(forKey: UInt64(pubrec.msgid))
            packetIdentifiers.release(pubrec.msgid)
        }
        clientStateLock.unlock()

        let messageID = pubrec.msgid
        let properties = pubrec.pubRecProperties
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didPublishRec: messageID, pubRecData: properties)
            mqtt5.didPublishRec(mqtt5, messageID, properties)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, pubrel: FramePubRel) {
        printDebug("RECV: \(pubrel)")

        clientStateLock.lock()
        let wasKnown = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v5)?
            .completeReceivedQoS2(pubrel.msgid) ?? false
        connectionReceivedQoS2Identifiers.remove(pubrel.msgid)
        clientStateLock.unlock()
        puback(
            FrameType.pubcomp,
            msgid: pubrel.msgid,
            pubCompReasonCode: wasKnown ? .success : .packetIdentifierNotFound
        )
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
        let properties = pubcomp.pubCompProperties
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5?(mqtt5, didPublishComplete: messageID, pubCompData: properties)
            mqtt5.didCompletePublish(mqtt5, messageID, properties)
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
            printError("SUBACK Reason Code count does not match the SUBSCRIBE request.")
            internal_disconnect()
            return
        }

        let success: NSMutableDictionary = NSMutableDictionary()
        var failed = [String]()
        for (idx, subscriptionList) in topicsAndQos.enumerated() {
            if suback.grantedQos[idx] != .FAILURE {
                subscriptions[subscriptionList.topic] = suback.grantedQos[idx]
                success[subscriptionList.topic] = suback.grantedQos[idx].rawValue
            } else {
                failed.append(subscriptionList.topic)
            }
        }

        let properties = suback.subAckProperties
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didSubscribeTopics: success, failed: failed, subAckData: properties)
            mqtt5.didSubscribeTopics(mqtt5, success, failed, properties)
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
        guard let reasonCodes = unsuback.unSubAckProperties?.reasonCodes,
              reasonCodes.count == topics.count else {
            printError("UNSUBACK Reason Code count does not match the UNSUBSCRIBE request.")
            internal_disconnect()
            return
        }
        // Remove local subscription
        var removeTopics: [String] = []
        for (index, t) in topics.enumerated() {
            removeTopics.append(t.topic)
            if reasonCodes[index].rawValue < 0x80 {
                subscriptions.removeValue(forKey: t.topic)
            }
        }

        let properties = unsuback.unSubAckProperties
        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5(mqtt5, didUnsubscribeTopics: removeTopics, unsubAckData: properties)
            mqtt5.didUnsubscribeTopics(mqtt5, removeTopics, properties)
        }
    }

    func didReceive(_ reader: CocoaMQTTReader, pingresp: FramePingResp) {
        printDebug("RECV: \(pingresp)")
        core.pingResponseReceived()

        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5DidReceivePong(mqtt5)
            mqtt5.didReceivePong(mqtt5)
        }
    }
}

// For tests
extension CocoaMQTT5 {
    func t_sendingMessagesCount() -> Int {
        sendingMessages.snapshot().count
    }

    func t_reservedPacketIdentifierCount() -> Int {
        packetIdentifiers.reservedCount
    }

    func t_keepAliveInterval() -> TimeInterval? {
        core.keepAliveInterval
    }

    func t_sessionExpiryControllerCount() -> Int {
        clientStateLock.lock()
        defer { clientStateLock.unlock() }
        return sessionExpiryControllers.count
    }

    func t_waitUntilDeliverIdle() {
        deliver.t_waitUntilIdle()
        eventLoopQueue.sync {}
    }
}
