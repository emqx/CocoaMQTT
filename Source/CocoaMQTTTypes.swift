//
//  CocoaMQTTTypes.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/6/9.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation


/// Encode and Decode big-endian UInt16
extension UInt16 {
    
    /// Most Significant Byte (MSB)
    private var highByte: UInt8 {
        return UInt8( (self & 0xFF00) >> 8)
    }
    
    /// Least Significant Byte (LSB)
    private var lowByte: UInt8 {
        return UInt8(self & 0x00FF)
    }
    
    var hlBytes: [UInt8] {
        return [highByte, lowByte]
    }
}


extension String {
    
    /// String with two bytes length
    var bytesWithLength: [UInt8] {
        return UInt16(utf8.count).hlBytes + utf8
    }
}


extension Bool {
    
    /// Bool to bit of UInt8
    var bit: UInt8 {
        return self ? 1 : 0
    }
    
    /// Initial a bool with a bit
    init(bit: UInt8) {
        self = (bit == 0) ? false : true
    }
}

extension UInt8 {
    
    /// Read a bit value
    func bitAt(_ offset: UInt8) -> UInt8 {
        return (self >> offset) & 0x01
    }
}

public enum CocoaMQTTError: Error {
    case invalidFrameStructrue
    case invalidURL
    case readTimeout
    case writeTimeout
    
    @available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    case closed(URLSessionWebSocketTask.CloseCode)
}

extension Array where Element == UInt8 {
    var summary: String {
        if self.count <= 10 {
            return "\(self)"
        } else {
            var descr = "[\(self[0])"
            for i in self[1..<10] {
                descr += ", \(i)"
            }
            return "\(descr), ...]"
        }
    }
}
