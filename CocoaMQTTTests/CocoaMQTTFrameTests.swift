//
//  CocoaMQTTFrameTests.swift
//  CocoaMQTT
//
//  Created by HJianBo on 2018/12/31.
//  Copyright © 2018 emqtt.io. All rights reserved.
//

import XCTest
@testable import CocoaMQTT

class CocoaMQTTFrameTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testFrameConnect() {
        let client = CocoaMQTT(clientID: "sheep")
        client.username = nil
        client.password = nil
        client.willMessage = nil
        client.cleanSession = false
        
        var f0 = CocoaMQTTFrameConnect(client: client)
        
        XCTAssertEqual(f0.header, 0x10)
        XCTAssertEqual(f0.type, CocoaMQTTFrameType.connect.rawValue)
        XCTAssertEqual(f0.dup, false)
        XCTAssertEqual(f0.qos, 0)
        XCTAssertEqual(f0.retained, false)
        
        XCTAssertEqual(f0.flags, 0x00)
        XCTAssertEqual(f0.flagUsername, false)
        XCTAssertEqual(f0.flagPassword, false)
        XCTAssertEqual(f0.flagWillRetain, false)
        XCTAssertEqual(f0.flagWillQOS, 0)
        XCTAssertEqual(f0.flagWill, false)
        XCTAssertEqual(f0.flagCleanSession, false)
        
        f0.flagUsername = true
        XCTAssertEqual(f0.flagUsername, true)
        f0.flagUsername = false
        
        f0.flagPassword = true
        XCTAssertEqual(f0.flagPassword, true)
        f0.flagPassword = false
        
        f0.flagWillRetain = true
        XCTAssertEqual(f0.flagWillRetain, true)
        f0.flagWillRetain = false
        
        f0.flagWillQOS = 1
        XCTAssertEqual(f0.flagWillQOS, 1)
        f0.flagWillQOS = 2
        XCTAssertEqual(f0.flagWillQOS, 2)
        f0.flagWillQOS = 0
        
        f0.flagWill = true
        XCTAssertEqual(f0.flagWill, true)
        f0.flagWill = false
        
        f0.flagCleanSession = true
        XCTAssertEqual(f0.flagCleanSession, true)
        f0.flagCleanSession = false
        
        XCTAssertEqual(f0.flags, 0x00)
        XCTAssertEqual(f0.flagUsername, false)
        XCTAssertEqual(f0.flagPassword, false)
        XCTAssertEqual(f0.flagWillRetain, false)
        XCTAssertEqual(f0.flagWillQOS, 0)
        XCTAssertEqual(f0.flagWill, false)
        XCTAssertEqual(f0.flagCleanSession, false)
    }
    
    func testFramePublish() {
        
        // PUBLISH - QOS2 - DUP - RETAINED
        var f0 = CocoaMQTTFramePublish(header: 0x3D, data: [])
        XCTAssertEqual(f0.header, 0x3D)
        XCTAssertEqual(f0.type, CocoaMQTTFrameType.publish.rawValue)
        XCTAssertEqual(f0.dup, true)
        XCTAssertEqual(f0.qos, 2)
        XCTAssertEqual(f0.retained, true)
        
        f0.dup = false
        f0.qos = CocoaMQTTQOS.qos0.rawValue
        f0.retained = false
    
        f0.dup = true
        XCTAssertEqual(f0.dup, true)
        f0.dup = false
        XCTAssertEqual(f0.dup, false)
        
        XCTAssertEqual(f0.qos, 0)
        // FIXME: should use Qos Type???
        f0.qos = CocoaMQTTQOS.qos1.rawValue
        XCTAssertEqual(f0.qos, 1)
        f0.qos = CocoaMQTTQOS.qos2.rawValue
        XCTAssertEqual(f0.qos, 2)
        f0.qos = CocoaMQTTQOS.qos0.rawValue
        XCTAssertEqual(f0.qos, 0)

        XCTAssertEqual(f0.retained, false)
        f0.retained = true
        XCTAssertEqual(f0.retained, true)
        f0.retained = false
        XCTAssertEqual(f0.retained, false)
    }
    
    func testFramePubAck() {
        // INITIAL
        var puback = CocoaMQTTFramePubAck(type: .puback, msgid: 0x1010)
        XCTAssertEqual(puback.header, 0x40)
        XCTAssertEqual(puback.msgid, 0x1010)
        XCTAssertEqual(puback.data(), [0x40, 0x02, 0x10, 0x10])
        
        var pubrec = CocoaMQTTFramePubAck(type: .pubrec, msgid: 0x1011)
        XCTAssertEqual(pubrec.header, 0x50)
        XCTAssertEqual(pubrec.msgid, 0x1011)
        XCTAssertEqual(pubrec.data(), [0x50, 0x02, 0x10, 0x11])
        
        var pubrel = CocoaMQTTFramePubAck(type: .pubrel, msgid: 0x1012)
        XCTAssertEqual(pubrel.header, 0x62)
        XCTAssertEqual(pubrel.msgid, 0x1012)
        XCTAssertEqual(pubrel.data(), [0x62, 0x02, 0x10, 0x12])
        
        var pubcom = CocoaMQTTFramePubAck(type: .pubcomp, msgid: 0x1013)
        XCTAssertEqual(pubcom.header, 0x70)
        XCTAssertEqual(pubcom.msgid, 0x1013)
        XCTAssertEqual(pubcom.data(), [0x70, 0x02, 0x10, 0x13])
    }
    
    func testFrameSubscribe() {
        // INITIAL
        var subs = CocoaMQTTFrameSubscribe(msgid: 0x1010, topic: "topic", reqos: .qos1)
        XCTAssertEqual(subs.header, 0x82)
        XCTAssertEqual(subs.msgid, 0x1010)
        XCTAssertEqual(subs.topics.count, 1)
        for (t, qos) in subs.topics {
            XCTAssertEqual(t, "topic")
            XCTAssertEqual(qos, .qos1)
        }
        XCTAssertEqual(subs.data(), [0x82, 0x0A,
                                     0x10, 0x10,
                                     0x00, 0x05, 0x74, 0x6F, 0x70, 0x69, 0x63,
                                     0x01])
    }
    
    func testFrameSubAck() {
        // TODO:
    }
    
    func testFrameUnsubscribe() {
        // INITIAL
        var unsub = CocoaMQTTFrameUnsubscribe(msgid: 0x1010, topic: "topic")
        XCTAssertEqual(unsub.header, 0xA2)
        XCTAssertEqual(unsub.msgid, 0x1010)
        XCTAssertEqual(unsub.topic, "topic")
        XCTAssertEqual(unsub.data(), [0xA2, 0x09,
                                      0x10, 0x10,
                                      0x00, 0x05, 0x74, 0x6F, 0x70, 0x69, 0x63])
    }
    
    func testFrameUnsubAck() {
        // TODO:
    }
    
    func testFrameDisconnect() {
        // INITIAL
        var disconn = CocoaMQTTFrameDisconnect()
        XCTAssertEqual(disconn.header, 0xE0)
        XCTAssertEqual(disconn.data(), [0xE0, 0x00])
    }
    
    func testFramePing() {
        // INITIAL
        var ping = CocoaMQTTFramePing()
        XCTAssertEqual(ping.header, 0xC0)
        XCTAssertEqual(ping.data(), [0xC0, 0x00])
    }
    
    func testFramePoing() {
        // TODO:
    }
}
