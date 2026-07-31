//
//  MQTTClientCore.swift
//  CocoaMQTT
//

import Foundation
import Security
import MqttCocoaAsyncSocket

protocol MQTTClientCoreDelegate: AnyObject {
    func clientCoreDidConnectTransport(_ core: MQTTClientCore)
    func clientCore(
        _ core: MQTTClientCore,
        didReceive trust: SecTrust,
        completionHandler: @escaping (Bool) -> Void
    )
    func clientCore(
        _ core: MQTTClientCore,
        didReceiveTrust trust: SecTrust,
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    )
    func clientCore(_ core: MQTTClientCore, willDisconnectWithError error: Error?)
    func clientCore(_ core: MQTTClientCore, didDisconnectWithError error: Error?)
    func clientCoreRequestsReconnect(_ core: MQTTClientCore) -> Bool
    func clientCoreRequestsPing(_ core: MQTTClientCore) -> Bool
    func clientCoreDidSendPing(_ core: MQTTClientCore)
    func clientCore(_ core: MQTTClientCore, didReject frame: Frame)
    func clientCore(_ core: MQTTClientCore, wantsToSend frame: Frame)
    func clientCore(_ core: MQTTClientCore, didChangeStateTo state: CocoaMQTTConnState)
    func clientCore(
        _ core: MQTTClientCore,
        didScheduleReconnect schedule: CocoaMQTTAutoReconnectSchedule
    )
}

/// Owns the protocol-neutral connection lifecycle shared by the MQTT 3.1.1
/// and MQTT 5 public facades. Protocol frames and session rules stay in the
/// facade and enter this core through the typed delegate boundary above.
final class MQTTClientCore {
    weak var delegate: MQTTClientCoreDelegate?

    let eventLoopQueue: DispatchQueue
    let lifecycleLock = NSRecursiveLock()
    var socket: CocoaMQTTSocketProtocol
    let deliver: CocoaMQTTDeliver
    let packetIdentifiers = MQTTPacketIdentifierAllocator()

    private(set) var reader: CocoaMQTTReader?
    private let connectionState: ConcurrentAtomic<CocoaMQTTConnState>
    private let autoReconnectController: MQTTAutoReconnectController
    private let keepAliveController: MQTTKeepAliveController
    private let socketDelegateProxy: CocoaMQTTSocketDelegateProxy
    private let delegateQueueLock = NSLock()
    private let deliveryTokenLock = NSLock()
    private var storedDelegateQueue = DispatchQueue.main
    private var deliveryToken = UInt64(UInt16.max)

    var delegateQueue: DispatchQueue {
        get {
            delegateQueueLock.lock()
            defer { delegateQueueLock.unlock() }
            return storedDelegateQueue
        }
        set {
            delegateQueueLock.lock()
            storedDelegateQueue = newValue
            delegateQueueLock.unlock()
        }
    }

    var state: CocoaMQTTConnState {
        get { connectionState.wrappedValue }
        set { connectionState.wrappedValue = newValue }
    }

    var enableSSL: Bool {
        get { socket.enableSSL }
        set { socket.enableSSL = newValue }
    }

    var autoReconnect: Bool {
        get { autoReconnectController.isEnabled }
        set { autoReconnectController.isEnabled = newValue }
    }

    var autoReconnectTimeInterval: UInt16 {
        get { autoReconnectController.autoReconnectTimeInterval }
        set { autoReconnectController.autoReconnectTimeInterval = newValue }
    }

    var maxAutoReconnectTimeInterval: UInt16 {
        get { autoReconnectController.maxAutoReconnectTimeInterval }
        set { autoReconnectController.maxAutoReconnectTimeInterval = newValue }
    }

    var reconnectTimeInterval: UInt16 { autoReconnectController.reconnectTimeInterval }
    var reconnectAttemptCount: UInt { autoReconnectController.reconnectAttemptCount }
    var isAutoReconnectPaused: Bool { autoReconnectController.isPaused }
    var keepAliveInterval: TimeInterval? { keepAliveController.interval }

    init(
        socket: CocoaMQTTSocketProtocol,
        state: ConcurrentAtomic<CocoaMQTTConnState>,
        protocolVersion: CocoaMQTTProtocolVersion,
        queueLabel: String
    ) {
        self.socket = socket
        self.connectionState = state
        let deliver = CocoaMQTTDeliver()
        deliver.protocolVersion = protocolVersion
        self.deliver = deliver
        let eventLoopQueue = DispatchQueue(label: queueLabel)
        self.eventLoopQueue = eventLoopQueue
        self.autoReconnectController = MQTTAutoReconnectController(eventLoopQueue: eventLoopQueue)
        self.keepAliveController = MQTTKeepAliveController(eventLoopQueue: eventLoopQueue)
        self.socketDelegateProxy = CocoaMQTTSocketDelegateProxy(eventLoopQueue: eventLoopQueue)
        autoReconnectController.delegate = self
        keepAliveController.delegate = self
        socketDelegateProxy.delegate = self
        deliver.delegate = self
        connectionState.setMutationObserver { [weak self] state in
            guard let self else { return }
            self.dispatchCallback { [weak self] delegate in
                guard let self else { return }
                delegate.clientCore(self, didChangeStateTo: state)
            }
        }
    }

    convenience init(
        socket: CocoaMQTTSocketProtocol,
        protocolVersion: CocoaMQTTProtocolVersion,
        queueLabel: String
    ) {
        self.init(
            socket: socket,
            state: ConcurrentAtomic(wrappedValue: .disconnected, label: "\(queueLabel).state"),
            protocolVersion: protocolVersion,
            queueLabel: queueLabel
        )
    }

    deinit {
        keepAliveController.stop()
        socket.disconnectForClientDeinit()
    }

    func connect(
        host: String,
        port: UInt16,
        timeout: TimeInterval,
        protocolVersion: CocoaMQTTProtocolVersion,
        maximumPacketSize: UInt32? = nil,
        packetReadTimeout: TimeInterval,
        readerDelegate: CocoaMQTTReaderDelegate,
        prepare: () -> Void
    ) -> Bool {
        lifecycleLock.lock()
        prepare()
        lifecycleLock.unlock()

        socket.setDelegate(socketDelegateProxy, delegateQueue: eventLoopQueue)
        reader = CocoaMQTTReader(
            socket: socket,
            delegate: readerDelegate,
            protocolVersion: protocolVersion,
            maximumPacketSize: maximumPacketSize,
            packetReadTimeout: packetReadTimeout
        )
        do {
            if timeout > 0 {
                try socket.connect(toHost: host, onPort: port, withTimeout: timeout)
            } else {
                try socket.connect(toHost: host, onPort: port)
            }
            eventLoopQueue.async { [weak self] in
                self?.state = .connecting
            }
            return true
        } catch let error as NSError {
            printError("socket connect error: \(error.description)")
            return false
        }
    }

    @discardableResult
    func send(
        _ frame: Frame,
        version: String,
        timeout: TimeInterval,
        maximumPacketSize: UInt32? = nil,
        tag: Int = 0,
        disconnectAfterWriting: Bool = false
    ) -> Bool {
        printDebug("SEND: \(frame)")
        let bytes = frame.bytes(version: version)
        if let maximumPacketSize,
           UInt64(bytes.count) > UInt64(maximumPacketSize) {
            printError("Packet exceeds the server Maximum Packet Size: \(frame)")
            return false
        }
        let packet = Data(bytes: bytes, count: bytes.count)
        if disconnectAfterWriting {
            socket.writeAndDisconnect(packet, withTimeout: timeout, tag: tag)
        } else {
            socket.write(packet, withTimeout: timeout, tag: tag)
        }
        return true
    }

    func disconnectUnexpectedly() {
        keepAliveController.stop()
        autoReconnectController.beginUnexpectedDisconnect()
        socket.disconnect()
    }

    func disconnectExpectedly(
        prepare: () -> Void = {},
        sendDisconnect: () -> Bool
    ) {
        guard autoReconnectController.beginExpectedDisconnect() else { return }
        keepAliveController.stop()
        prepare()
        if !sendDisconnect() {
            socket.disconnect()
        }
    }

    func pauseAutoReconnect() {
        autoReconnectController.pause()
    }

    func resumeAutoReconnect() {
        guard let schedule = autoReconnectController.resume(
            connectionIsDisconnected: state == .disconnected
        ) else { return }
        notifyAutoReconnectScheduled(schedule)
    }

    func ping() {
        keepAliveController.pingSent()
        requestPing(requiresConnectedState: false)
    }

    func connectionSucceeded() {
        autoReconnectController.connectionSucceeded()
    }

    func startKeepAlive(interval: UInt16) {
        keepAliveController.start(interval: interval)
    }

    func pingResponseReceived() {
        keepAliveController.pingResponseReceived()
    }

    func nextDeliveryToken() -> UInt64 {
        deliveryTokenLock.lock()
        defer { deliveryTokenLock.unlock() }
        if deliveryToken >= UInt64(Int.max) {
            deliveryToken = UInt64(UInt16.max) + 1
        } else {
            deliveryToken += 1
        }
        return deliveryToken
    }

    func discardStoredSession(clientID: String, protocolVersion: CocoaMQTTProtocolVersion) {
        CocoaMQTTStorage(by: clientID, protocolVersion: protocolVersion)?.removeAll()
    }

    func discardInMemorySession<Message, SubscriptionRequest, UnsubRequest>(
        preservingConnectionQueue: Bool,
        sendingMessages: ThreadSafeDictionary<UInt64, Message>,
        subscriptionsWaitingAck: ThreadSafeDictionary<UInt16, SubscriptionRequest>,
        unsubscriptionsWaitingAck: ThreadSafeDictionary<UInt16, UnsubRequest>,
        clearSubscriptions: () -> Void
    ) {
        let pendingPublishes = preservingConnectionQueue
            ? deliver.connectionPendingFrames().compactMap { $0 as? FramePublish }
            : []
        deliver.cleanAll(
            detachStorage: true,
            preserveConnectionQueue: preservingConnectionQueue
        )
        if preservingConnectionQueue {
            let pendingTokens = Set(pendingPublishes.map {
                $0.deliveryToken ?? UInt64($0.msgid)
            })
            sendingMessages.replace(
                with: sendingMessages.snapshot().filter { pendingTokens.contains($0.key) }
            )
        } else {
            sendingMessages.removeAll()
        }
        subscriptionsWaitingAck.removeAll()
        unsubscriptionsWaitingAck.removeAll()
        clearSubscriptions()
        packetIdentifiers.reset()
        for publish in pendingPublishes where publish.qos > .qos0 {
            packetIdentifiers.markInUse(publish.msgid)
        }
    }

    func markStoredPacketIdentifiersInUse(
        clientID: String,
        protocolVersion: CocoaMQTTProtocolVersion
    ) {
        guard let frames = CocoaMQTTStorage(
            by: clientID,
            protocolVersion: protocolVersion
        )?.readAll() else { return }
        for frame in frames {
            if let publish = frame as? FramePublish {
                packetIdentifiers.markInUse(publish.msgid)
            } else if let pubrel = frame as? FramePubRel {
                packetIdentifiers.markInUse(pubrel.msgid)
            }
        }
    }

    func clearPendingPacketIdentifiers<SubscriptionRequest, UnsubRequest>(
        subscriptionsWaitingAck: ThreadSafeDictionary<UInt16, SubscriptionRequest>,
        unsubscriptionsWaitingAck: ThreadSafeDictionary<UInt16, UnsubRequest>
    ) {
        for identifier in subscriptionsWaitingAck.removeAllValues().keys {
            packetIdentifiers.release(identifier)
        }
        for identifier in unsubscriptionsWaitingAck.removeAllValues().keys {
            packetIdentifiers.release(identifier)
        }
    }

    func dispatchCallback(
        _ callback: @escaping (MQTTClientCoreDelegate) -> Void,
        completionOnEventLoop: ((MQTTClientCoreDelegate) -> Void)? = nil,
        onDeallocated: (() -> Void)? = nil
    ) {
        let callbackQueue = delegateQueue
        callbackQueue.async { [weak self] in
            guard let self, let delegate = self.delegate else {
                onDeallocated?()
                return
            }
            callback(delegate)
            guard let completionOnEventLoop else { return }
            self.eventLoopQueue.async { [weak self] in
                guard let self, let delegate = self.delegate else { return }
                completionOnEventLoop(delegate)
            }
        }
    }

    private func requestPing(requiresConnectedState: Bool = true) {
        if requiresConnectedState && state != .connected {
            keepAliveController.stop()
            return
        }
        guard delegate?.clientCoreRequestsPing(self) == true else {
            disconnectUnexpectedly()
            return
        }
        dispatchCallback { [weak self] delegate in
            guard let self else { return }
            delegate.clientCoreDidSendPing(self)
        }
    }

    private func notifyAutoReconnectScheduled(_ schedule: CocoaMQTTAutoReconnectSchedule) {
        dispatchCallback { [weak self] delegate in
            guard let self,
                  self.autoReconnectController.isCurrent(schedule) else { return }
            delegate.clientCore(self, didScheduleReconnect: schedule)
        }
    }
}

extension MQTTClientCore: CocoaMQTTDeliverProtocol {
    func deliver(_ deliver: CocoaMQTTDeliver, didReject frame: Frame) {
        delegate?.clientCore(self, didReject: frame)
    }

    func deliver(_ deliver: CocoaMQTTDeliver, wantToSend frame: Frame) {
        delegate?.clientCore(self, wantsToSend: frame)
    }
}

extension MQTTClientCore: MQTTAutoReconnectControllerDelegate {
    func autoReconnectControllerRequestsReconnect(_ controller: MQTTAutoReconnectController) {
        guard delegate?.clientCoreRequestsReconnect(self) == false,
              let schedule = controller.reconnectAttemptFailedToStart() else { return }
        notifyAutoReconnectScheduled(schedule)
    }
}

extension MQTTClientCore: MQTTKeepAliveControllerDelegate {
    func keepAliveControllerRequestsPing(_ controller: MQTTKeepAliveController) {
        requestPing()
    }

    func keepAliveControllerDidTimeOut(_ controller: MQTTKeepAliveController) {
        guard state == .connected else { return }
        printWarning("PINGRESP timed out, closing socket")
        disconnectUnexpectedly()
    }
}

extension MQTTClientCore: CocoaMQTTSocketDelegate {
    func socketConnected(_ socket: CocoaMQTTSocketProtocol) {
        autoReconnectController.socketConnected()
        delegate?.clientCoreDidConnectTransport(self)
    }

    func socket(
        _ socket: CocoaMQTTSocketProtocol,
        didReceive trust: SecTrust,
        completionHandler: @escaping (Bool) -> Void
    ) {
        dispatchCallback({ [weak self] delegate in
            guard let self else {
                completionHandler(false)
                return
            }
            delegate.clientCore(self, didReceive: trust, completionHandler: completionHandler)
        }, onDeallocated: { completionHandler(false) })
    }

    func socketUrlSession(
        _ socket: CocoaMQTTSocketProtocol,
        didReceiveTrust trust: SecTrust,
        didReceiveChallenge challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        dispatchCallback({ [weak self] delegate in
            guard let self else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            delegate.clientCore(
                self,
                didReceiveTrust: trust,
                challenge: challenge,
                completionHandler: completionHandler
            )
        }, onDeallocated: {
            completionHandler(.cancelAuthenticationChallenge, nil)
        })
    }

    func socketDidSecure(_ socket: MGCDAsyncSocket) {
        printDebug("Socket has successfully completed SSL/TLS negotiation")
        delegate?.clientCoreDidConnectTransport(self)
    }

    func socket(_ socket: CocoaMQTTSocketProtocol, didWriteDataWithTag tag: Int) {}

    func socket(_ socket: CocoaMQTTSocketProtocol, didRead data: Data, withTag tag: Int) {
        let readTag = CocoaMQTTReadTag(rawValue: tag)!
        var bytes = [UInt8]([0])
        switch readTag {
        case .header:
            data.copyBytes(to: &bytes, count: 1)
            reader!.headerReady(bytes[0])
        case .length:
            data.copyBytes(to: &bytes, count: 1)
            reader!.lengthReady(bytes[0])
        case .payload:
            reader!.payloadReady(data)
        }
    }

    func socketDidDisconnect(_ socket: CocoaMQTTSocketProtocol, withError error: Error?) {
        keepAliveController.stop()
        socket.setDelegate(nil, delegateQueue: nil)
        delegate?.clientCore(self, willDisconnectWithError: error)
        let reconnectContext = autoReconnectController.socketDidDisconnect()

        state = .disconnected
        dispatchCallback({ [weak self] delegate in
            guard let self else { return }
            delegate.clientCore(self, didDisconnectWithError: error)
        }, completionOnEventLoop: { [weak self] _ in
            guard let self,
                  let schedule = self.autoReconnectController.completeDisconnectCallbacks(
                    reconnectContext
                  ) else { return }
            self.notifyAutoReconnectScheduled(schedule)
        })
    }
}
