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

    func testFrame() {
        // CONNECT Frame
        let f0 = CocoaMQTTFrame(header: 0x10)
        XCTAssertEqual(f0.header, 0x10)
        XCTAssertEqual(f0.type, CocoaMQTTFrameType.connect.rawValue)
        XCTAssertEqual(f0.dup, false)
        XCTAssertEqual(f0.qos, 0)
        XCTAssertEqual(f0.retained, false)
        
        let f00 = CocoaMQTTFrame(type: .connect)
        XCTAssertEqual(f00.header, 0x10)
        XCTAssertEqual(f00.type, CocoaMQTTFrameType.connect.rawValue)
        XCTAssertEqual(f00.dup, false)
        XCTAssertEqual(f00.qos, 0)
        XCTAssertEqual(f00.retained, false)
        
        // PUBLISH - QOS2 - DUP - RETAINED
        let f1 = CocoaMQTTFrame(header: 0x3D)
        XCTAssertEqual(f1.header, 0x3D)
        XCTAssertEqual(f1.type, CocoaMQTTFrameType.publish.rawValue)
        XCTAssertEqual(f1.dup, true)
        XCTAssertEqual(f1.qos, 2)
        XCTAssertEqual(f1.retained, true)
        
        let f11 = CocoaMQTTFrame(type: .publish)
        XCTAssertEqual(f11.header, 0x30)
        XCTAssertEqual(f11.type, CocoaMQTTFrameType.publish.rawValue)
        XCTAssertEqual(f11.dup, false)
        XCTAssertEqual(f11.qos, 0)
        XCTAssertEqual(f11.retained, false)
        
        let frame = CocoaMQTTFrame(type: .connect)
        
        XCTAssertEqual(frame.dup, false)
        frame.dup = true
        XCTAssertEqual(frame.dup, true)
        frame.dup = false
        XCTAssertEqual(frame.dup, false)
        
        XCTAssertEqual(frame.qos, 0)
        // FIXME: should use Qos Type???
        frame.qos = CocoaMQTTQOS.qos1.rawValue
        XCTAssertEqual(frame.qos, 1)
        frame.qos = CocoaMQTTQOS.qos2.rawValue
        XCTAssertEqual(frame.qos, 2)
        frame.qos = CocoaMQTTQOS.qos0.rawValue
        XCTAssertEqual(frame.qos, 0)
        
        
        XCTAssertEqual(frame.retained, false)
        frame.retained = true
        XCTAssertEqual(frame.retained, true)
        frame.retained = false
        XCTAssertEqual(frame.retained, false)
        
        // TODO: pack? unpack?
    }
    
    func testFrameConnect() {
        let client = CocoaMQTT(clientID: "sheep")
        client.username = nil
        client.password = nil
        client.willMessage = nil
        client.cleanSession = false
        
        let f0 = CocoaMQTTFrameConnect(client: client)
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
        
        // TODO: pack? unpack?
    }
    
    func testFramePublish() {
        
    }
    
    func testFramePubAck() {
        
    }
    
    func testFrameSubscribe() {
        
    }
    
    func testFrameUnsubscribe() {
        
    }
}
