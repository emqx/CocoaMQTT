//
//  CocoaMQTTTypes.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2019/6/9.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

enum CocoaMQTTResources {
    static var bundle: Bundle {
        #if IS_SWIFT_PACKAGE
        return .module
        #else
        return Bundle(for: CocoaMQTT.self)
        #endif
    }
}

struct CocoaMQTTAutoReconnectSchedule {
    let attemptCount: UInt
    let interval: UInt16
    let generation: UInt64
}

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
        guard utf8.count <= Int(UInt16.max) else {
            printError("UTF-8 string exceeds the MQTT length limit.")
            return []
        }
        return UInt16(utf8.count).hlBytes + utf8
    }

    var stringUTF8: String {
        let data = self.data(using: .nonLossyASCII)
        return String(data: data!, encoding: .utf8) ?? ""
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
    case invalidURL
    case readTimeout
    case writeTimeout
    @available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public enum FoundationConnection: Error {
        case closed(URLSessionWebSocketTask.CloseCode)
    }
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

extension Data {
    var uint8: UInt8 {
        var number: UInt8 = 0
        self.copyBytes(to: &number, count: MemoryLayout<UInt8>.size)
        return number
    }

    var uint16: UInt16 {
        let i16array = self.withUnsafeBytes { $0.load(as: UInt16.self) }
        return i16array
    }

    var uint32: UInt32 {
        let i32array = self.withUnsafeBytes { $0.load(as: UInt32.self) }
        return i32array
    }

    var uuid: NSUUID? {
        var bytes = [UInt8](repeating: 0, count: self.count)
        self.copyBytes(to: &bytes, count: self.count * MemoryLayout<UInt32>.size)
        return NSUUID(uuidBytes: bytes)
    }
    var stringASCII: String? {
        return NSString(data: self, encoding: String.Encoding.ascii.rawValue) as String?
    }

    var stringUTF8: String? {
        return NSString(data: self, encoding: String.Encoding.utf8.rawValue) as String?
    }

    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }

}

extension Int {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<Int>.size)
    }
}

extension UInt8 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt8>.size)
    }
}

extension UInt16 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt32>.size)
    }

    var byteArrayLittleEndian: [UInt8] {
        return [
            UInt8((self & 0xFF000000) >> 24),
            UInt8((self & 0x00FF0000) >> 16),
            UInt8((self & 0x0000FF00) >> 8),
            UInt8(self & 0x000000FF)
        ]
    }
}

extension Dictionary where Key == String, Value == String {
    var userPropertyBytes: [UInt8] {
        return reduce([UInt8](), { $0 + getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: $1.key.bytesWithLength + $1.value.bytesWithLength) })
    }
}

extension Array where Element == CocoaMQTTUserProperty {
    var userPropertyBytes: [UInt8] {
        return reduce(into: [UInt8]()) { bytes, property in
            bytes += getMQTTPropertyData(
                type: CocoaMQTTPropertyName.userProperty.rawValue,
                value: property.key.bytesWithLength + property.value.bytesWithLength
            )
        }
    }
}

func hasValidMQTTUTF8Length(_ string: String, allowEmpty: Bool = false) -> Bool {
    return (allowEmpty || !string.isEmpty)
        && string.utf8.count <= Int(UInt16.max)
        && !string.unicodeScalars.contains(where: { $0.value == 0 })
}

func hasValidMQTTTopicName(_ topic: String, allowEmpty: Bool = false) -> Bool {
    return hasValidMQTTUTF8Length(topic, allowEmpty: allowEmpty)
        && !topic.contains("+")
        && !topic.contains("#")
}

func hasValidMQTTTopicFilter(_ filter: String) -> Bool {
    guard hasValidMQTTUTF8Length(filter) else { return false }

    let characters = Array(filter)
    for index in characters.indices {
        switch characters[index] {
        case "#":
            guard index == characters.index(before: characters.endIndex),
                  index == characters.startIndex || characters[characters.index(before: index)] == "/" else {
                return false
            }
        case "+":
            let startsLevel = index == characters.startIndex || characters[characters.index(before: index)] == "/"
            let next = characters.index(after: index)
            let endsLevel = next == characters.endIndex || characters[next] == "/"
            guard startsLevel && endsLevel else { return false }
        default:
            break
        }
    }
    return true
}

func isMQTTSharedSubscription(_ filter: String) -> Bool {
    return filter.hasPrefix("$share/")
}

func hasValidMQTTSharedSubscription(_ filter: String) -> Bool {
    guard isMQTTSharedSubscription(filter) else { return true }
    let remainder = filter.dropFirst("$share/".count)
    guard let separator = remainder.firstIndex(of: "/") else { return false }
    let shareName = remainder[..<separator]
    let topicFilter = remainder[remainder.index(after: separator)...]
    return !shareName.isEmpty
        && !shareName.contains("+")
        && !shareName.contains("#")
        && !topicFilter.isEmpty
        && !topicFilter.hasPrefix("$share/")
        && hasValidMQTTTopicFilter(String(topicFilter))
}

func hasValidMQTTUserProperties(_ properties: [String: String]?) -> Bool {
    return properties?.allSatisfy {
        hasValidMQTTUTF8Length($0.key, allowEmpty: true)
            && hasValidMQTTUTF8Length($0.value, allowEmpty: true)
    } ?? true
}

func hasValidMQTTUserProperties(_ properties: [CocoaMQTTUserProperty]) -> Bool {
    return properties.allSatisfy {
        hasValidMQTTUTF8Length($0.key, allowEmpty: true)
            && hasValidMQTTUTF8Length($0.value, allowEmpty: true)
    }
}

func hasValidMQTTBinaryLength(_ bytes: [UInt8]) -> Bool {
    return bytes.count <= Int(UInt16.max)
}

func hasValidMQTTPasswordLength(_ password: String?) -> Bool {
    return (password?.utf8.count ?? 0) <= Int(UInt16.max)
}
