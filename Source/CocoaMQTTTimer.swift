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
    let name: String

    private let lock = NSLock()
    private let timer: DispatchSourceTimer
    private var eventHandler: (() -> Void)?
    private var retainedUntilCanceled: CocoaMQTTTimer?

    private enum State {
        case suspended
        case resumed
        case canceled
    }

    private var state: State = .suspended

    init(delay: TimeInterval?=nil, name: String, timeInterval: TimeInterval) {
        self.name = name
        self.timeInterval = timeInterval
        if let delay = delay {
            self.startDelay = delay
        } else {
            self.startDelay = timeInterval
        }
        let queue = DispatchQueue(label: "io.emqx.CocoaMQTT." + name, target: CocoaMQTTTimer.target_queue)
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(
            deadline: .now() + startDelay,
            repeating: timeInterval > 0 ? timeInterval : .infinity
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let eventHandler = self.eventHandler
            self.lock.unlock()
            eventHandler?()
        }
    }

    class func every(_ interval: TimeInterval, name: String, _ block: @escaping () -> Void) -> CocoaMQTTTimer {
        let timer = CocoaMQTTTimer(name: name, timeInterval: interval)
        timer.eventHandler = block
        timer.resume()
        return timer
    }

    @discardableResult
    class func after(_ interval: TimeInterval, name: String, _ block: @escaping () -> Void) -> CocoaMQTTTimer {
        let timer = CocoaMQTTTimer(delay: interval, name: name, timeInterval: 0)
        timer.lock.lock()
        timer.retainedUntilCanceled = timer
        timer.eventHandler = { [weak timer] in
            block()
            timer?.cancel()
        }
        timer.lock.unlock()
        timer.resume()
        return timer
    }

    /// Execute the tasks concurrently on the target_queue with default QOS
    private static let target_queue = DispatchQueue(label: "io.emqx.CocoaMQTT.TimerQueue", qos: .default, attributes: .concurrent)

    deinit {
        lock.lock()
        timer.setEventHandler {}
        eventHandler = nil
        if state != .canceled {
            if state == .suspended {
                timer.resume()
            }
            timer.cancel()
        }
        lock.unlock()
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard state == .suspended else {
            return
        }
        state = .resumed
        timer.resume()
    }

    func suspend() {
        lock.lock()
        defer { lock.unlock() }
        guard state == .resumed else {
            return
        }
        state = .suspended
        timer.suspend()
    }

    /// Manually cancel timer
    func cancel() {
        lock.lock()
        guard state != .canceled else {
            lock.unlock()
            return
        }
        if state == .suspended {
            timer.resume()
        }
        state = .canceled
        timer.setEventHandler {}
        eventHandler = nil
        timer.cancel()
        retainedUntilCanceled = nil
        lock.unlock()
    }
}
