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
    case normalDisconnection = 0x00
    case disconnectWithWillMessage = 0x04
    case unspecifiedError = 0x80
    case malformedPacket = 0x81
    case protocolError = 0x82
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case serverBusy = 0x89
    case serverShuttingDown = 0x8B
    case keepAliveTimeout = 0x8D
    case sessionTakenOver = 0x8E
    case topicFilterInvalid = 0x8F
    case topicNameInvalid = 0x90
    case receiveMaximumExceeded = 0x93
    case topicAliasInvalid = 0x94
    case packetTooLarge = 0x95
    case messageRateTooHigh = 0x96
    case quotaExceeded = 0x97
    case administrativeAction = 0x98
    case payloadFormatInvalid = 0x99
    case retainNotSupported = 0x9A
    case qosNotSupported = 0x9B
    case useAnotherServer = 0x9C
    case serverMoved = 0x9D
    case sharedSubscriptionsNotSupported = 0x9E
    case connectionRateExceeded = 0x9F
    case maximumConnectTime = 0xA0
    case subscriptionIdentifiersNotSupported = 0xA1
    case wildcardSubscriptionsNotSupported = 0xA2
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
