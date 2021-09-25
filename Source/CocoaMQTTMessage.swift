//
//  CocoaMQTTMessage.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqx.io. All rights reserved.
//

import Foundation


/// MQTT Message
public class CocoaMQTTMessage: NSObject {
    //3.3.2.3.4 Topic Alias
    public var topicAlias: UInt16?

    public var qos = CocoaMQTTQoS.qos1
    
    public var topic: String

    public var payload: [UInt8]
    
    public var retained = false


    public var isUTF8EncodedData: Bool = true

    public var willDelayInterval: UInt32? = 0

    public var willPayloadFormatIndicator: UInt8?

    public var willExpiryInterval: UInt32? = 0

    public var contentType: String?

    public var willResponseTopic: String?

    public var willCorrelationData: Data?

    public var willUserProperty: [String: String]?
    
    /// The `duplicated` property show that this message maybe has be received before
    ///
    /// - note: Readonly property
    public var duplicated = false
    
    
    /// Return the payload as a utf8 string if possible
    ///
    /// It will return nil if the payload is not a valid utf8 string
    public var string: String? {
        get {
            if isUTF8EncodedData {
                return NSString(bytes: payload, length: payload.count, encoding: String.Encoding.utf8.rawValue) as String?
            }else{
                return NSString(bytes: payload, length: payload.count, encoding: String.Encoding.ascii.rawValue) as String?
            }

        }
    }

    public var properties: [UInt8] {
        var properties = [UInt8]()
        var retVal = [UInt8]()

        /// 3.1.3.2.2 Property Length
        if let willDelayInterval = self.willDelayInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.willDelayInterval.rawValue, value: willDelayInterval.byteArrayLittleEndian)
        }


        /// 3.1.3.2.4 Message Expiry Interval
        if let willExpiryInterval = self.willExpiryInterval {
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.willExpiryInterval.rawValue, value: willExpiryInterval.byteArrayLittleEndian)
        }

        /// 3.1.3.2.3 Payload Format Indicator
        if isUTF8EncodedData {
            properties += [1, 1]
        }else{
            properties += [1, 0]
        }

        
        /// 3.1.3.2.5 Content Type
        if var contentType = self.contentType {
            if isUTF8EncodedData {
                contentType = (NSString(bytes: contentType, length: contentType.count, encoding: String.Encoding.utf8.rawValue) as String?)!
            }else{
                contentType = (NSString(bytes: contentType, length: contentType.count, encoding: String.Encoding.ascii.rawValue) as String?)!
            }
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.contentType.rawValue, value: contentType.bytesWithLength)
        }

        /// 3.1.3.2.6 Response Topic
        if var willResponseTopic = self.willResponseTopic {
            if isUTF8EncodedData {
                willResponseTopic = (NSString(bytes: willResponseTopic, length: willResponseTopic.count, encoding: String.Encoding.utf8.rawValue) as String?)!
            }else{
                willResponseTopic = (NSString(bytes: willResponseTopic, length: willResponseTopic.count, encoding: String.Encoding.ascii.rawValue) as String?)!
            }
            properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.responseTopic.rawValue, value: willResponseTopic.bytesWithLength)
        }
        /// 3.1.3.2.7 Correlation Data
        if let willCorrelationData = self.willCorrelationData {
            properties += willCorrelationData
        }
        /// 3.1.3.2.8 User Property
        if let willUserProperty = self.willUserProperty {
            let dictValues = [String](willUserProperty.values)
            for (value) in dictValues {
                var res = value
                if isUTF8EncodedData {
                    res = (NSString(bytes: res, length: res.count, encoding: String.Encoding.utf8.rawValue) as String?)!
                }else{
                    res = (NSString(bytes: res, length: res.count, encoding: String.Encoding.ascii.rawValue) as String?)!
                }
                properties += getMQTTPropertyData(type: CocoaMQTTPropertyName.userProperty.rawValue, value: res.bytesWithLength)
            }
        }


        retVal += properties
        return retVal
    }
    
    public init(topic: String, string: String, qos: CocoaMQTTQoS = .qos1, retained: Bool = false) {
        self.topic = topic
        self.payload = [UInt8](string.utf8)
        self.qos = qos
        self.retained = retained
    }

    public init(topic: String, payload: [UInt8], qos: CocoaMQTTQoS = .qos1, retained: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retained = retained
    }
}

extension CocoaMQTTMessage {
    
    public override var description: String {
        return "CocoaMQTTMessage(topic: \(topic), qos: \(qos), payload: \(payload.summary))"
    }
}

// For test
extension CocoaMQTTMessage {
    
    var t_pub_frame: FramePublish {
        var frame = FramePublish(topic: topic, payload: payload, qos: qos, msgid: 0)
        frame.retained = retained
        frame.dup = duplicated
        return frame
    }
    
}
