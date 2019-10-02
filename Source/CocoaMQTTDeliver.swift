//
//  CocoaMQTTDeliver.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/2.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation
import Dispatch

protocol CocoaMQTTDeliverProtocol: class {
    
    var delegateQueue: DispatchQueue { get set }
    
    func deliver(_ deliver: CocoaMQTTDeliver, wantToSend frame: FramePublish)
}

private struct InflightFrame {
    
    var frame: FramePublish
    
    var timestamp: TimeInterval
    
    init(frame: FramePublish) {
        self.init(frame: frame, timestamp: Date.init(timeIntervalSinceNow: 0).timeIntervalSince1970)
    }
    
    init(frame: FramePublish, timestamp: TimeInterval) {
        self.frame = frame
        self.timestamp = timestamp
    }
}

// CocoaMQTTDeliver
class CocoaMQTTDeliver: NSObject {
    
    /// The dispatch queue is used by delivering frames in serially
    private var deliverQueue = DispatchQueue.init(label: "deliver.cocoamqtt.emqx", qos: .default)
    
    weak var delegate: CocoaMQTTDeliverProtocol?
    
    fileprivate var inflight = [InflightFrame]()
    
    fileprivate var mqueue = [FramePublish]()
    
    var mqueueSize: UInt = 1000
    
    var inflightWindowSize: UInt = 10
    
    /// Retry time interval millisecond
    var retryTimeInterval: Double = 5000
    
    private var awaitingTimer: CocoaMQTTTimer?
    
    var isQueueEmpty: Bool { get { return mqueue.count == 0 }}
    var isQueueFull: Bool { get { return mqueue.count > mqueueSize }}
    var isInflightFull: Bool { get { return inflight.count >= inflightWindowSize }}
    var isInflightEmpty: Bool { get { return inflight.count == 0 }}
    
    /// return false means the frame is rejected because of the buffer is full
    func add(_ frame: FramePublish) -> Bool {
        guard !isQueueFull else {
            printError("Buffer is full, message(\(String(describing: frame.msgid))) was abandoned.")
            return false
        }
        
        deliverQueue.async { [weak self] in
            guard let wself = self else { return }
            wself.mqueue.append(frame)
            wself.tryTransport()
        }
        
        return true
    }
    
    ///
    func sendSuccess(withMsgid msgid: UInt16) {
        deliverQueue.async { [weak self] in
            guard let wself = self else { return }
            wself.removeFrameFromInflight(withMsgid: msgid)
            printDebug("Deliver frame success, msgid: \(msgid)")
            
            wself.tryTransport()
        }
    }
    
    /// Clean Inflight content to prevent message blocked, when next connection established
    ///
    /// !!Warning: it's a tempnary method for hotfix #221
    func cleanAll() {
        deliverQueue.async { [weak self] in
            guard let wself = self else { return }
            _ = wself.mqueue.removeAll()
            _ = wself.inflight.removeAll()
        }
    }
}

// MARK: Private Funcs
extension CocoaMQTTDeliver {
    
    // try transport a frame from mqueue to inflight
    private func tryTransport() {
        if isQueueEmpty || isInflightFull { return }
        
        // take out the earliest frame
        if mqueue.isEmpty { return }
        let frame = mqueue.remove(at: 0)
        
        deliver(frame)
        
        // keep trying after a transport
        self.tryTransport()
    }
    
    /// Try to deliver a frame
    private func deliver(_ frame: FramePublish) {
        let sendfun = { (f: FramePublish) in
            guard let delegate = self.delegate else {
                printError("The deliver delegate is nil!!! the frame will be drop: \(f)")
                return
            }
            delegate.delegateQueue.async {
                delegate.deliver(self, wantToSend: f)
            }
        }
        
        if frame.qos == .qos0 {
            // Send Qos0 message, whatever the in-flight queue is full
            // TODO: A retrict deliver mode is need?
            sendfun(frame)
        } else {
            
            sendfun(frame)
            inflight.append(InflightFrame(frame: frame))
            
            // Start a retry timer for resending it if it not receive PUBACK or PUBREC
            if awaitingTimer == nil {
                awaitingTimer = CocoaMQTTTimer.every(retryTimeInterval / 1000.0) { [weak self] in
                    guard let wself = self else { return }
                    wself.deliverQueue.async {
                        wself.redeliver()
                    }
                }
            }
        }
    }
    
    /// Attemp to redliver in-flight messages
    private func redeliver() {
        if isInflightEmpty {
            // Revoke the awaiting timer
            awaitingTimer = nil
            return
        }
        
        let sendfun = { (f: FramePublish) in
            guard let delegate = self.delegate else {
                printError("The deliver delegate is nil!!! the frame will be drop: \(f)")
                return
            }
            delegate.delegateQueue.async {
                delegate.deliver(self, wantToSend: f)
            }
        }
        
        let nowTimestamp = Date(timeIntervalSinceNow: 0).timeIntervalSince1970
        for (idx, frame) in inflight.enumerated() {
            if (nowTimestamp - frame.timestamp) >= (retryTimeInterval/1000.0) {
                var duplicatedFrame = frame
                duplicatedFrame.frame.dup = true
                duplicatedFrame.timestamp = nowTimestamp
                sendfun(duplicatedFrame.frame)
                inflight[idx] = duplicatedFrame
                printInfo("Re-delivery frame \(duplicatedFrame.frame)")
            }
        }
    }
    
    @discardableResult
    private func removeFrameFromInflight(withMsgid msgid: UInt16) -> Bool {
        var success = false
        for (index, frame) in inflight.enumerated() {
            if frame.frame.msgid == msgid {
                success = true
                inflight.remove(at: index)
                break
            }
        }
        return success
    }
}
