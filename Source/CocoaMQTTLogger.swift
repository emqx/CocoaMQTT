//
//  CocoaMQTTLogger.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/2.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

// Convenience functions
//
// Messages are `@autoclosure`s so that string interpolation (for example the
// description of a whole payload) is only evaluated when the level is enabled.
func printDebug(_ message: @autoclosure () -> String) {
    CocoaMQTTLogger.logger.debug(message())
}

func printInfo(_ message: @autoclosure () -> String) {
    CocoaMQTTLogger.logger.info(message())
}

func printWarning(_ message: @autoclosure () -> String) {
    CocoaMQTTLogger.logger.warning(message())
}

func printError(_ message: @autoclosure () -> String) {
    CocoaMQTTLogger.logger.error(message())
}

// Enum log levels
public enum CocoaMQTTLoggerLevel: Int {
    case debug = 0, info, warning, error, off
}

open class CocoaMQTTLogger: NSObject {

    // Singleton
    // Keep mutable global logger for backward compatibility.
    // Accesses are intentionally marked as unsafe-isolated for Swift 6 readiness.
    #if swift(>=6)
    public nonisolated(unsafe) static var logger = CocoaMQTTLogger()
    #else
    public static var logger = CocoaMQTTLogger()
    #endif
    public override init() { super.init() }

    // min level
    @ConcurrentAtomic(wrappedValue: .warning, label: "CocoaMQTTLogger.minLevel")
    public var minLevel: CocoaMQTTLoggerLevel

    // logs
    open func log(level: CocoaMQTTLoggerLevel, message: String) {
        guard level.rawValue >= minLevel.rawValue else { return }
        print("CocoaMQTT(\(level)): \(message)")
    }

    /// Whether messages at `level` are passed to `log(level:message:)`.
    ///
    /// Messages below `minLevel` are not built at all, so set `minLevel` to the lowest
    /// level you want to receive, including when overriding `log(level:message:)`.
    func isEnabled(_ level: CocoaMQTTLoggerLevel) -> Bool {
        level.rawValue >= minLevel.rawValue
    }

    func debug(_ message: @autoclosure () -> String) {
        guard isEnabled(.debug) else { return }
        log(level: .debug, message: message())
    }

    func info(_ message: @autoclosure () -> String) {
        guard isEnabled(.info) else { return }
        log(level: .info, message: message())
    }

    func warning(_ message: @autoclosure () -> String) {
        guard isEnabled(.warning) else { return }
        log(level: .warning, message: message())
    }

    func error(_ message: @autoclosure () -> String) {
        guard isEnabled(.error) else { return }
        log(level: .error, message: message())
    }

}
