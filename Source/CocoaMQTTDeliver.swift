//
//  CocoaMQTTDeliver.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/2.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation
import Dispatch

protocol CocoaMQTTDeliverProtocol: class {
    
    var dispatchQueue: DispatchQueue { get set }
    
    func deliver(_ deliver: CocoaMQTTDeliver, wantToSend frame: CocoaMQTTFramePublish)
}

// CocoaMQTTDeliver
class CocoaMQTTDeliver: NSObject {
    
    /// The dispatch queue is used by delivering frames in serially
    private var deliverQueue = DispatchQueue.init(label: "deliver.cocoamqtt.emqx", qos: .default)
    
    weak var delegate: CocoaMQTTDeliverProtocol?
    
    fileprivate var inflight = [CocoaMQTTFramePublish]()
    
    fileprivate var mqueue = [CocoaMQTTFramePublish]()
    
    var mqueueSize: UInt = 1000
    
    var inflightWindowSize: UInt = 10
    
    var timeout: Double = 60
    
    var isQueueEmpty: Bool { get { return mqueue.count == 0 }}
    var isQueueFull : Bool { get { return mqueue.count > mqueueSize }}
    var isInflightFull  : Bool { get { return inflight.count >= inflightWindowSize }}
    
    
    /// return false means the frame is rejected because of the buffer is full
    func add(_ frame: CocoaMQTTFramePublish) -> Bool {
        guard !isQueueFull else {
            printError("Buffer is full, message(\(String(describing: frame.msgid))) was abandoned.")
            return false
        }
        
        deliverQueue.async { [weak self] in
            guard let wSelf = self else { return }
            wSelf.mqueue.append(frame)
            wSelf.tryTransport()
        }
        
        return true
    }
    
    ///
    func sendSuccess(withMsgid msgid: UInt16) {
        deliverQueue.async { [weak self] in
            guard let wself = self else { return }
            wself.removeFrameFromInflight(withMsgid: msgid)
            printDebug("Frame \(msgid) send success")
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
    
    private func deliver(_ frame: CocoaMQTTFramePublish) {
        guard let delegate = self.delegate else {
            printError("The deliver delegate is nil!!! the frame will be drop: \(frame)")
            return
        }
        
        delegate.dispatchQueue.async {
            delegate.deliver(self, wantToSend: frame)
        }
        
        // Insert to In-flight window for Qos1/Qos2 message
        if frame.qos != 0 && frame.msgid != nil {
            let _ = CocoaMQTTTimer.after(timeout) { [weak self] in
                guard let wself = self else { return }
                wself.deliverQueue.async {
                    var dupFrame = frame
                    dupFrame.dup = true
                    printDebug("re-delvery frame \(dupFrame)")
                    wself.deliver(dupFrame)
                }
            }
            inflight.append(frame)
        }
    }
    
    @discardableResult
    private func removeFrameFromInflight(withMsgid msgid: UInt16) -> Bool {
        var success = false
        for (index, frame) in inflight.enumerated() {
            if frame.msgid == msgid {
                success = true
                inflight.remove(at: index)
                tryTransport()
                break
            }
        }
        return success
    }
}
