//
//  CocoaMQTTDeliver.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/2.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import Foundation


protocol CocoaMQTTDeliverProtocol: class {
    
    var dispatchQueue: DispatchQueue { get set }
    
    func deliver(_ deliver: CocoaMQTTDeliver, wantToSend frame: CocoaMQTTFramePublish)
}

// CocoaMQTTDeliver
class CocoaMQTTDeliver: NSObject {
    
    weak var delegate: CocoaMQTTDeliverProtocol?
    
    fileprivate var inflight = [CocoaMQTTFramePublish]()
    
    fileprivate var mqueue = [CocoaMQTTFramePublish]()
    
    var mqueueSize: UInt = 1000
    
    var inflightWindowSize: UInt = 10
    
    var timeout: Double = 60
    
    var isQueueEmpty: Bool { get { return mqueue.count == 0 }}
    var isQueueFull : Bool { get { return mqueue.count > mqueueSize }}
    var isInflightFull  : Bool { get { return inflight.count >= inflightWindowSize }}
    
    
    // return false means the frame is rejected because of the buffer is full
    func add(_ frame: CocoaMQTTFramePublish) -> Bool {
        guard !isQueueFull else {
            printError("Buffer is full, message(\(String(describing: frame.msgid))) was abandoned.")
            return false
        }
        
        mqueue.append(frame)
        tryTransport()
        return true
    }
    
    // try transport a frame from mqueue to inflight
    func tryTransport() {
        if isQueueEmpty || isInflightFull { return }
        
        // take out the earliest frame
        if mqueue.isEmpty { return }
        let frame = mqueue.remove(at: 0)
        
        send(frame)
        
        // keep trying after a transport
        self.tryTransport()
    }
    
    func send(_ frame: CocoaMQTTFramePublish) {
        guard let delegate = self.delegate else { return }
        delegate.dispatchQueue.async {
            delegate.deliver(self, wantToSend: frame)
        }
        
        // Insert to In-flight window for Qos1/Qos2 message
        if frame.qos != 0 && frame.msgid != nil {
            let _ = CocoaMQTTTimer.after(timeout) { [weak self] in
                guard let weakSelf = self else { return }
                printDebug("re-delvery frame \(frame)")
                weakSelf.send(frame)
            }
            inflight.append(frame)
        }
    }
    
    func sendSuccess(withMsgid msgid: UInt16) {
        DispatchQueue.main.async { [weak self] in
            self?.removeFrameFromInflight(withMsgid: msgid)
            printDebug("sendMessageSuccess:\(msgid)")
        }
    }
    
    /// Clean Inflight content to prevent message blocked, when next connection established
    ///
    /// !!Warning: it's a tempnary method for hotfix #221
    func cleanAll() {
        DispatchQueue.main.async { [weak self] in
            _ = self?.mqueue.removeAll()
            _ = self?.inflight.removeAll()
        }
    }
}

// MARK: Private Funcs
extension CocoaMQTTDeliver {
    
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
