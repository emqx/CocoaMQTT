//
//  CocoaMQTTReasonCode.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/4.
//

import Foundation

public enum CocoaMQTTAUTHReasonCode: UInt8 {
    case success = 0x00
    case continueAuthentication = 0x18
    case ReAuthenticate = 0x19
}

@objc public enum CocoaMQTTCONNACKReasonCode: UInt8 {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
}


public enum PayloadFormatIndicator: UInt8 {
    case unspecified = 0x00
    case utf8 = 0x01
}



public enum CocoaMQTTDISCONNECTReasonCode: UInt8 {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
}


public enum CocoaMQTTPUBACKReasonCode: UInt8 {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
}


public enum CocoaMQTTPUBCOMPReasonCode: UInt8 {
    case success = 0x00
    case packetIdentifierNotFound = 0x92
}


public enum CocoaMQTTPUBRECReasonCode: UInt8 {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
}


public enum CocoaMQTTPUBRELReasonCode: UInt8 {
    case success = 0x00
    case packetIdentifierNotFound = 0x92
}


public enum CocoaMQTTSUBACKReasonCode: UInt8 {
    case grantedQoS0 = 0x00
    case grantedQoS1 = 0x01
    case grantedQoS2 = 0x02
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case sharedSubscriptionsNotSupported = 0x9E
    case subscriptionIdentifiersNotSupported = 0xA1
    case wildcardSubscriptionsNotSupported = 0xA2
}


public enum CocoaMQTTUNSUBACKReasonCode: UInt8 {
    case grantedQoS0 = 0x00
    case noSubscriptionExisted = 0x11
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUse = 0x91
}



public enum CocoaRetainHandlingOption: UInt8 {
    case sendOnSubscribe = 0
    case sendOnlyWhenSubscribeIsNew = 1
    case none = 2
}
