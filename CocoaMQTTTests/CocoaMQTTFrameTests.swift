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
        
        XCTAssertEqual(f0.fixedHeader, 0x10)
        XCTAssertEqual(f0.type, CocoaMQTTFrameType.connect)
        XCTAssertEqual(f0.dup, false)
        XCTAssertEqual(f0.qos, .qos0)
        XCTAssertEqual(f0.retained, false)
        
        XCTAssertEqual(f0.connFlags, 0x00)
        XCTAssertEqual(f0.flagUsername, false)
        XCTAssertEqual(f0.flagPassword, false)
        XCTAssertEqual(f0.flagWillRetain, false)
        XCTAssertEqual(f0.flagWillQoS, 0)
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
        
        f0.flagWillQoS = 1
        XCTAssertEqual(f0.flagWillQoS, 1)
        f0.flagWillQoS = 2
        XCTAssertEqual(f0.flagWillQoS, 2)
        f0.flagWillQoS = 0
        
        f0.flagWill = true
        XCTAssertEqual(f0.flagWill, true)
        f0.flagWill = false
        
        f0.flagCleanSession = true
        XCTAssertEqual(f0.flagCleanSession, true)
        f0.flagCleanSession = false
        
        XCTAssertEqual(f0.connFlags, 0x00)
        XCTAssertEqual(f0.flagUsername, false)
        XCTAssertEqual(f0.flagPassword, false)
        XCTAssertEqual(f0.flagWillRetain, false)
        XCTAssertEqual(f0.flagWillQoS, 0)
        XCTAssertEqual(f0.flagWill, false)
        XCTAssertEqual(f0.flagCleanSession, false)
    }
    
    func testFramePublish() {
        
        // PUBLISH - QOS2 - DUP - RETAINED
        guard var f0 = CocoaMQTTFramePublish(fixedHeader: 0x3D, bytes: [0x00, 0x03, 0x74, 0x2f, 0x61, // topic = t/a
                                                                        0x00, 0x10,                   // msgid = 16
                                                                        0x61, 0x61, 0x61]) else {     // payload = aaa
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(f0.fixedHeader, 0x3D)
        XCTAssertEqual(f0.type, CocoaMQTTFrameType.publish)
        XCTAssertEqual(f0.dup, true)
        XCTAssertEqual(f0.qos, .qos2)
        XCTAssertEqual(f0.retained, true)
        
        XCTAssertEqual(f0.topic, "t/a")
        XCTAssertEqual(f0.msgid, 16)
        XCTAssertEqual(f0.payload, [0x61, 0x61, 0x61])
        
        f0.dup = false
        f0.qos = CocoaMQTTQoS.qos0
        f0.retained = false
    
        f0.dup = true
        XCTAssertEqual(f0.dup, true)
        f0.dup = false
        XCTAssertEqual(f0.dup, false)
        
        XCTAssertEqual(f0.qos, .qos0)
        // FIXME: should use Qos Type???
        f0.qos = CocoaMQTTQoS.qos1
        XCTAssertEqual(f0.qos, .qos1)
        f0.qos = CocoaMQTTQoS.qos2
        XCTAssertEqual(f0.qos, .qos2)
        f0.qos = CocoaMQTTQoS.qos0
        XCTAssertEqual(f0.qos, .qos0)

        XCTAssertEqual(f0.retained, false)
        f0.retained = true
        XCTAssertEqual(f0.retained, true)
        f0.retained = false
        XCTAssertEqual(f0.retained, false)
        
        XCTAssertNil(CocoaMQTTFramePublish(fixedHeader: 0x3D, bytes: []))
        XCTAssertNil(CocoaMQTTFramePublish(fixedHeader: 0x3D, bytes: [0x00, 0x01, 0x02, 0x03]))
    }
    
    func testFramePubAck() {
        // INITIAL
        var puback = CocoaMQTTFramePubAck(msgid: 0x1010)
        XCTAssertEqual(puback.fixedHeader, 0x40)
        XCTAssertEqual(puback.msgid, 0x1010)
        XCTAssertEqual(puback.data(), [0x40, 0x02, 0x10, 0x10])
        
        var pubrec = CocoaMQTTFramePubRec(msgid: 0x1011)
        XCTAssertEqual(pubrec.fixedHeader, 0x50)
        XCTAssertEqual(pubrec.msgid, 0x1011)
        XCTAssertEqual(pubrec.data(), [0x50, 0x02, 0x10, 0x11])
        
        var pubrel = CocoaMQTTFramePubRel(msgid: 0x1012)
        XCTAssertEqual(pubrel.fixedHeader, 0x62)
        XCTAssertEqual(pubrel.msgid, 0x1012)
        XCTAssertEqual(pubrel.data(), [0x62, 0x02, 0x10, 0x12])
        
        var pubcom = CocoaMQTTFramePubCom(msgid: 0x1013)
        XCTAssertEqual(pubcom.fixedHeader, 0x70)
        XCTAssertEqual(pubcom.msgid, 0x1013)
        XCTAssertEqual(pubcom.data(), [0x70, 0x02, 0x10, 0x13])
    }
    
    func testFrameSubscribe() {
        // INITIAL
        var subs = CocoaMQTTFrameSubscribe(msgid: 0x1010, topic: "topic", reqos: .qos1)
        XCTAssertEqual(subs.fixedHeader, 0x82)
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
        // INITIAL
        guard var suback = CocoaMQTTFrameSubAck(fixedHeader: 0x90, bytes: [0x00, 0x11, 0x00, 0x80, 0x02]) else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(suback.type, .suback)
        XCTAssertEqual(suback.qos, .qos0)
        XCTAssertEqual(suback.dup, false)
        XCTAssertEqual(suback.retained, false)
        
        XCTAssertEqual(suback.msgid, 17)
        XCTAssertEqual(suback.grantedQos, [.qos0, .FAILTURE, .qos2])
        
        XCTAssertNil(CocoaMQTTFrameSubAck(fixedHeader: 0x90, bytes: []))
        XCTAssertNil(CocoaMQTTFrameSubAck(fixedHeader: 0x90, bytes: [0x00, 0x01, 0x22]))
    }
    
    func testFrameUnsubscribe() {
        // INITIAL
        var unsub = CocoaMQTTFrameUnsubscribe(msgid: 0x1010, topics: ["topic", "t2"])
        XCTAssertEqual(unsub.fixedHeader, 0xA2)
        XCTAssertEqual(unsub.msgid, 0x1010)
        XCTAssertEqual(unsub.topics, ["topic", "t2"])
        XCTAssertEqual(unsub.data(), [0xA2, 0x0d,
                                      0x10, 0x10,
                                      0x00, 0x05, 0x74, 0x6F, 0x70, 0x69, 0x63,
                                      0x00, 0x02, 0x74, 0x32])
    }
    
    func testFrameUnsubAck() {
        // TODO:
    }
    
    func testFrameDisconnect() {
        // INITIAL
        var disconn = CocoaMQTTFrameDisconnect()
        XCTAssertEqual(disconn.fixedHeader, 0xE0)
        XCTAssertEqual(disconn.data(), [0xE0, 0x00])
    }
    
    func testFramePing() {
        // INITIAL
        var ping = CocoaMQTTFramePing()
        XCTAssertEqual(ping.fixedHeader, 0xC0)
        XCTAssertEqual(ping.data(), [0xC0, 0x00])
    }
    
    func testFramePong() {
        // TODO:
    }
}
