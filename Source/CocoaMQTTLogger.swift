//
//  CocoaMQTTLogger.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/5/2.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

// Convenience functions
func printDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CocoaMQTTLogger.logger.log(level: .debug, message: message, file: file, function: function, line: line)
}

func printInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CocoaMQTTLogger.logger.log(level: .info, message: message, file: file, function: function, line: line)
}

func printWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CocoaMQTTLogger.logger.log(level: .warning, message: message, file: file, function: function, line: line)
}

func printError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CocoaMQTTLogger.logger.log(level: .error, message: message, file: file, function: function, line: line)
}


// Enum log levels
public enum CocoaMQTTLoggerLevel: Int {
    case debug = 0, info, warning, error, off
}

public protocol CocoaMQTTLoggerDelegate: AnyObject {
    func cocoaMQTTLog(_ message: String, level: CocoaMQTTLoggerLevel, file: String, function: String, line: Int)
}

open class CocoaMQTTLogger: NSObject {
    
    // Singleton
    public static var logger = CocoaMQTTLogger()
    public override init() { super.init() }

    /// 日志回调协议，用于将日志回传给使用方
    public weak var delegate: CocoaMQTTLoggerDelegate?
    
    /// 是否支持控制台日志输出
    #if DEBUG
    public var logEnable: Bool = true
    #else
    public var logEnable: Bool = false
    #endif
    
    // min level
    public var minLevel: CocoaMQTTLoggerLevel = .warning
    
    // logs
    open func log(level: CocoaMQTTLoggerLevel, message: String, file: String, function: String, line: Int){
        guard level.rawValue >= minLevel.rawValue else { return }
        
        if logEnable {
            print("CocoaMQTT(\(level)): \(message)")
        }
        
        delegate?.cocoaMQTTLog(message, level: level, file: file, function: function, line: line)
    }
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
}
