//
//  CocoaMQTTTimer.swift
//  CocoaMQTT
//
//  Contributed by Jens(https://github.com/jmiltner)
//
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

// modeled after RepeatingTimer by Daniel Galasko: https://medium.com/@danielgalasko/a-background-repeating-timer-in-swift-412cecfd2ef9
/// RepeatingTimer mimics the API of DispatchSourceTimer but in a way that prevents
/// crashes that occur from calling resume multiple times on a timer that is
/// already resumed (noted by https://github.com/SiftScience/sift-ios/issues/52)
class CocoaMQTTTimer {
    
    let timeInterval: TimeInterval
    let startDelay: TimeInterval
    
    init(delay:TimeInterval?=nil, timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
        if let delay = delay {
            self.startDelay = delay
        } else {
            self.startDelay = timeInterval
        }
    }
    
    class func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> CocoaMQTTTimer {
        let timer = CocoaMQTTTimer(timeInterval: interval)
        timer.eventHandler = block
        timer.resume()
        return timer
    }
    
    @discardableResult
    class func after(_ interval: TimeInterval, _ block: @escaping () -> Void) -> CocoaMQTTTimer {
        var timer : CocoaMQTTTimer? = CocoaMQTTTimer(delay: interval, timeInterval:0)
        timer?.eventHandler = {
            block()
            timer?.suspend()
            timer = nil
        }
        timer?.resume()
        return timer!
    }
    
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + self.startDelay, repeating: self.timeInterval > 0 ? Double(self.timeInterval) : Double.infinity)
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return t
    }()
    
    var eventHandler: (() -> Void)?
    
    private enum State {
        case suspended
        case resumed
        case canceled
    }
    
    private var state: State = .suspended
    
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here https://forums.developer.apple.com/thread/15902
         */
        resume()
        eventHandler = nil
    }
    
    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }
    
    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
    
    /// Manually cancel timer
    func cancel() {
        if state == .canceled {
            return
        }
        state = .canceled
        timer.cancel()
    }
}
