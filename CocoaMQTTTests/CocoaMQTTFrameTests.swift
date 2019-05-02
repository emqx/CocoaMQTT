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
        
    }
    
    func testFrameSubscribe() {
        
    }
    
    func testFrameUnsubscribe() {
        
    }
}
