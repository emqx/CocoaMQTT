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

    @ConcurrentAtomic(wrappedValue: CocoaMQTTConnState.disconnected, label: "CocoaMQTT5.connState")
    public var connState

    // deliver
    private var deliver = CocoaMQTTDeliver()

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
    private var aliveTimer: CocoaMQTTTimer?

    /// Maximum duration in seconds for each Remaining Length byte and the complete payload read.
    /// Each deadline starts with its read and is not reset by partial data. Header reads remain unlimited.
    /// Nonpositive or nonfinite values disable these deadlines. Default is 30 seconds.
    /// Changes take effect on the next connection.
    public var packetReadTimeout: TimeInterval = CocoaMQTTReader.defaultPacketReadTimeout

    /// Enable auto-reconnect mechanism
    public var autoReconnect: Bool {
        get { autoReconnectController.isEnabled }
        set { autoReconnectController.isEnabled = newValue }
    }

    /// Reconnect time interval
    ///
    /// - note: This value will be increased with `autoReconnectTimeInterval *= 2`
    ///         if reconnect failed
    public var autoReconnectTimeInterval: UInt16 {
        get { autoReconnectController.autoReconnectTimeInterval }
        set { autoReconnectController.autoReconnectTimeInterval = newValue }
    }

    /// Maximum auto reconnect time interval
    ///
    /// The timer starts from `autoReconnectTimeInterval` second and grows exponentially until this value
    /// After that, it uses this value for subsequent requests.
    public var maxAutoReconnectTimeInterval: UInt16 {
        get { autoReconnectController.maxAutoReconnectTimeInterval }
        set { autoReconnectController.maxAutoReconnectTimeInterval = newValue }
    }

    /// 3.1.2.11 CONNECT Properties
    public var connectProperties: MqttConnectProperties?

    /// 3.15.2.2 AUTH Properties
    public var authProperties: MqttAuthProperties?

    /// Auto-reconnect backoff interval in seconds for the current reconnect cycle.
    ///
    /// This value is advanced for the next reconnect attempt while auto-reconnect is active,
    /// and resets to `0` when auto-reconnect is inactive.
    public var reconnectTimeInterval: UInt16 { autoReconnectController.reconnectTimeInterval }

    /// Number of reconnect attempts scheduled in the current auto-reconnect cycle.
    ///
    /// The value resets to `0` after a successful connection or expected disconnect.
    public var reconnectAttemptCount: UInt { autoReconnectController.reconnectAttemptCount }

    /// Whether auto-reconnect is currently paused by the application.
    public var isAutoReconnectPaused: Bool {
        autoReconnectController.isPaused
    }

    private let autoReconnectController: MQTTAutoReconnectController
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
    private let clientStateLock = NSRecursiveLock()
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
        get { return self.socket.enableSSL }
        set { socket.enableSSL = newValue }
    }

    ///
    public var sslSettings: [String: NSObject]? {
        get { return (self.socket as? CocoaMQTTSocket)?.sslSettings ?? nil }
        set { (self.socket as? CocoaMQTTSocket)?.sslSettings = newValue }
    }

    /// Server name used for TLS identity verification. Defaults to `host`.
    @objc public var tlsServerName: String? {
        get { return (self.socket as? CocoaMQTTSocket)?.tlsServerName }
        set { (self.socket as? CocoaMQTTSocket)?.tlsServerName = newValue }
    }

    /// Additional CA certificates trusted by the built-in TCP socket.
    public var trustedServerCertificates: [SecCertificate] {
        get { return (self.socket as? CocoaMQTTSocket)?.trustedServerCertificates ?? [] }
        set { (self.socket as? CocoaMQTTSocket)?.trustedServerCertificates = newValue }
    }

    /// Whether custom CA validation also accepts the system trust store.
    @objc public var usesSystemTrustStore: Bool {
        get { return (self.socket as? CocoaMQTTSocket)?.usesSystemTrustStore ?? true }
        set { (self.socket as? CocoaMQTTSocket)?.usesSystemTrustStore = newValue }
    }

    /// Enables manual server trust evaluation on the built-in TCP socket.
    /// Implement the trust delegate method or `didReceiveTrust` closure before
    /// enabling this property.
    @objc public var manuallyEvaluateTrust: Bool {
        get { return (self.socket as? CocoaMQTTSocket)?.manuallyEvaluateTrust ?? false }
        set { (self.socket as? CocoaMQTTSocket)?.manuallyEvaluateTrust = newValue }
    }

    /// Legacy name for enabling manual trust evaluation.
    ///
    /// This setting does not apply to `CocoaMQTTWebSocket`. Handle a WebSocket
    /// trust challenge with `mqtt5UrlSession` or `didReceiveTrust` instead.
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

    private let packetIdentifiers = MQTTPacketIdentifierAllocator()
    private var _deliveryToken = UInt64(UInt16.max)
    private let messageIdentifierLock = NSLock()
    fileprivate var socket: CocoaMQTTSocketProtocol
    fileprivate var reader: CocoaMQTTReader?

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
        self.socket = socket
        let eventLoopQueue = DispatchQueue(label: "io.emqx.CocoaMQTT5.event-loop.\(UUID().uuidString)")
        self.eventLoopQueue = eventLoopQueue
        self.autoReconnectController = MQTTAutoReconnectController(eventLoopQueue: eventLoopQueue)
        super.init()
        autoReconnectController.delegate = self
        socketDelegateProxy = CocoaMQTTSocketDelegateProxy(eventLoopQueue: eventLoopQueue)
        socketDelegateProxy.delegate = self
        $connState.setMutationObserver { [weak self] state in
            guard let self = self else { return }
            self.__delegate_queue { mqtt5 in
                mqtt5.delegate?.mqtt5?(mqtt5, didStateChangeTo: state)
                mqtt5.didChangeState(mqtt5, state)
            }
        }
        configureSessionExpiryController(for: clientID)
        deliver.protocolVersion = .v5
        deliver.delegate = self
    }

    deinit {
        aliveTimer?.suspend()
        sessionExpiryController?.handleDisconnect()
        socket.setDelegate(nil, delegateQueue: nil)
        socket.disconnect()
    }

    @discardableResult
    fileprivate func send(_ frame: Frame, tag: Int = 0, disconnectAfterWriting: Bool = false) -> Bool {
        printDebug("SEND: \(frame)")
        let data = frame.bytes(version: version)

        clientStateLock.lock()
        let maximumPacketSize = serverMaximumPacketSize
        clientStateLock.unlock()
        guard UInt64(data.count) <= UInt64(maximumPacketSize) else {
            printError("Packet exceeds the server Maximum Packet Size: \(frame)")
            return false
        }

        let packet = Data(bytes: data, count: data.count)
        if disconnectAfterWriting {
            socket.writeAndDisconnect(packet, withTimeout: 5, tag: tag)
        } else {
            socket.write(packet, withTimeout: 5, tag: tag)
        }
        return true
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
        CocoaMQTTStorage(by: activeClientID, protocolVersion: .v5)?.removeAll()
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
        subscriptions.removeAll()
        packetIdentifiers.reset()
        for publish in pendingPublishes where publish.qos > .qos0 {
            packetIdentifiers.markInUse(publish.msgid)
        }
    }

    private func markStoredPacketIdentifiersInUse() {
        guard let frames = CocoaMQTTStorage(by: activeClientID, protocolVersion: .v5)?.readAll() else {
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
        for identifier in subscriptionsWaitingAck.removeAllValues().keys {
            packetIdentifiers.release(identifier)
        }
        for identifier in unsubscriptionsWaitingAck.removeAllValues().keys {
            packetIdentifiers.release(identifier)
        }
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
        clientStateLock.lock()
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
        clientStateLock.unlock()
        resetDisconnectReasonState()
        sessionExpiryController?.prepareStoredSessionForConnect()
        socket.setDelegate(socketDelegateProxy, delegateQueue: eventLoopQueue)
        reader = CocoaMQTTReader(
            socket: socket,
            delegate: self,
            protocolVersion: .v5,
            maximumPacketSize: connectProperties?.maximumPacketSize,
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
        autoReconnectController.beginUnexpectedDisconnect()
        socket.disconnect()
    }

    /// Pause auto-reconnect attempts without disabling `autoReconnect`.
    ///
    /// Use this when the application knows reconnect attempts should not run yet,
    /// for example while waiting for network reachability to recover.
    public func pauseAutoReconnect() {
        autoReconnectController.pause()
    }

    /// Resume auto-reconnect attempts after `pauseAutoReconnect()`.
    ///
    /// If an auto-reconnect attempt is pending, this schedules the next reconnect
    /// attempt immediately.
    public func resumeAutoReconnect() {
        guard let schedule = autoReconnectController.resume(
            connectionIsDisconnected: connState == .disconnected
        ) else { return }
        notifyAutoReconnectScheduled(schedule)
    }

    func internal_disconnect_withProperties(reasonCode: CocoaMQTTDISCONNECTReasonCode, userProperties: [String: String] ) {
        expected_disconnect(reasonCode: reasonCode, userProperties: userProperties)
    }

    private func expected_disconnect(reasonCode: CocoaMQTTDISCONNECTReasonCode,
                                     userProperties: [String: String]? = nil,
                                     recordsLocalReason: Bool = false) {
        guard autoReconnectController.beginExpectedDisconnect() else { return }
        if recordsLocalReason {
            markPendingLocalDisconnect(reasonCode: reasonCode)
        }
        var frameDisconnect = FrameDisconnect(disconnectReasonCode: reasonCode)
        frameDisconnect.userProperties = userProperties ?? [:]
        guard send(frameDisconnect, tag: -0xE0, disconnectAfterWriting: true) else {
            socket.disconnect()
            return
        }
    }
    /// Send a PING request to broker
    public func ping() {
        printDebug("ping")
        guard send(FramePingReq(), tag: -0xC0) else {
            internal_disconnect()
            return
        }

        __delegate_queue { mqtt5 in
            mqtt5.delegate?.mqtt5DidPing(mqtt5)
            mqtt5.didPing(mqtt5)
        }
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

// MARK: CocoaMQTTDeliverProtocol
extension CocoaMQTT5: CocoaMQTTDeliverProtocol {

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
        let callbackQueue = delegateQueue
        callbackQueue.async { [weak self] in
            guard let self = self else {
                onDeallocated?()
                return
            }
            fun(self)
            guard let completionOnEventLoop = completionOnEventLoop else { return }
            self.eventLoopQueue.async { [weak self] in
                guard let self = self else { return }
                completionOnEventLoop(self)
            }
        }
    }

    private func notifyAutoReconnectScheduled(_ schedule: CocoaMQTTAutoReconnectSchedule) {
        __delegate_queue { mqtt5 in
            guard mqtt5.autoReconnectController.isCurrent(schedule) else { return }
            mqtt5.delegate?.mqtt5?(mqtt5, didScheduleReconnect: schedule.attemptCount, after: schedule.interval)
            mqtt5.didScheduleReconnect(mqtt5, schedule.attemptCount, schedule.interval)
        }
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

extension CocoaMQTT5: MQTTAutoReconnectControllerDelegate {
    func autoReconnectControllerRequestsReconnect(_ controller: MQTTAutoReconnectController) {
        guard !connect(),
              let schedule = controller.reconnectAttemptFailedToStart() else { return }
        notifyAutoReconnectScheduled(schedule)
    }
}

// MARK: - CocoaMQTTSocketDelegate
extension CocoaMQTT5: CocoaMQTTSocketDelegate {

    public func socketConnected(_ socket: CocoaMQTTSocketProtocol) {
        autoReconnectController.socketConnected()
        sendConnectFrame()
    }

    public func socket(_ socket: CocoaMQTTSocketProtocol,
                       didReceive trust: SecTrust,
                       completionHandler: @escaping (Bool) -> Swift.Void) {

        printDebug("Call the SSL/TLS manually validating function")

        __delegate_queue({ mqtt5 in
            CocoaMQTTTrustHandling.resolveManualTrust(handler: { completion in
                if mqtt5.delegate?.mqtt5?(mqtt5, didReceive: trust, completionHandler: completion) != nil {
                    return true
                }
                guard let handler = mqtt5.customDidReceiveTrust else { return false }
                handler(mqtt5, trust, completion)
                return true
            }, fallback: { completion in
                (socket as? CocoaMQTTSocket)?.evaluateServerTrust(
                    trust,
                    completionHandler: completion
                ) ?? false
            }, completionHandler: completionHandler)
        }, onDeallocated: { completionHandler(false) })
    }

    public func socketUrlSession(_ socket: CocoaMQTTSocketProtocol, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        printDebug("Call the SSL/TLS manually validating function - socketUrlSession")

        __delegate_queue({ mqtt5 in
            CocoaMQTTTrustHandling.resolveURLSessionChallenge(
                urlSessionHandler: { completion in
                    mqtt5.delegate?.mqtt5UrlSession?(
                        mqtt5,
                        didReceiveTrust: trust,
                        didReceiveChallenge: challenge,
                        completionHandler: completion
                    ) != nil
                },
                legacyHandler: { completion in
                    if mqtt5.delegate?.mqtt5?(mqtt5, didReceive: trust, completionHandler: completion) != nil {
                        return true
                    }
                    guard let handler = mqtt5.customDidReceiveTrust else { return false }
                    handler(mqtt5, trust, completion)
                    return true
                },
                legacyCredential: URLCredential(trust: trust),
                completionHandler: completionHandler
            )
        }, onDeallocated: { completionHandler(.cancelAuthenticationChallenge, nil) })
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
        // Publish uses the same lock, so no frame can enter the new connection
        // queue while it still observes aliases or limits from the old one.
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
        updateDisconnectReasonAfterSocketDisconnect(error: err)
        let reconnectContext = autoReconnectController.socketDidDisconnect()

        connState = .disconnected
        __delegate_queue({ mqtt5 in
            mqtt5.delegate?.mqtt5DidDisconnect(mqtt5, withError: err)
            mqtt5.didDisconnect(mqtt5, err)
        }, completionOnEventLoop: { mqtt5 in
            mqtt5.continueAfterDisconnectCallbacks(reconnectContext)
        })
    }

    private func continueAfterDisconnectCallbacks(_ context: MQTTAutoReconnectDisconnectContext) {
        guard let schedule = autoReconnectController.completeDisconnectCallbacks(context) else { return }
        notifyAutoReconnectScheduled(schedule)
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

            autoReconnectController.connectionSucceeded()

            // Start keepalive timer

            let negotiatedKeepAlive = properties?.serverKeepAlive ?? keepAlive
            aliveTimer = nil
            if negotiatedKeepAlive > 0 {
                aliveTimer = CocoaMQTTTimer.every(Double(negotiatedKeepAlive), name: "aliveTimer") { [weak self] in
                    guard let self = self else { return }
                    self.eventLoopQueue.async {
                        guard self.connState == .connected else {
                            self.aliveTimer = nil
                            return
                        }
                        self.ping()
                    }
                }
            }

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
        aliveTimer?.timeInterval
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
