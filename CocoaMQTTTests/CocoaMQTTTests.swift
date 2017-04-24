//
//  CocoaMQTTTests.swift
//  CocoaMQTTTests
//
//  Created by CrazyWisdom on 15/12/11.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import XCTest
@testable import CocoaMQTT

let host = "localhost"
let port: UInt16 = 1883
let cilentID = "ClientForUnitTesting001"

class CocoaMQTTTests: XCTestCase, CocoaMQTTDelegate {
    
    var readyExpectation: XCTestExpectation?
    var mqtt: CocoaMQTT = CocoaMQTT(clientID: cilentID, host: host, port: port)
    
    override func setUp() {
        super.setUp()
        
        // custom set
        mqtt.delegate = self
        mqtt.logLevel = .debug
        mqtt.autoReconnect = true
        mqtt.keepAlive = 60
        mqtt.autoReconnectTimeInterval = 5
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testConnect() {
        
        readyExpectation = expectation(description: "Swift Expectations")
        
        mqtt.connect()
        
        
        waitForExpectations(timeout: 5) { error in
            XCTAssert(self.mqtt.connState == .connected)
        }
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    /// MQTT connected with server
    func mqtt(_ mqtt: CocoaMQTT, didConnect host: String, port: Int) {
    }
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        readyExpectation?.fulfill()
    }
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        
    }
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        
    }
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        
    }
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        
    }
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        
    }
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        
    }
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        
    }
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        readyExpectation?.fulfill()
    }
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        
    }
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        
    }
    
}
