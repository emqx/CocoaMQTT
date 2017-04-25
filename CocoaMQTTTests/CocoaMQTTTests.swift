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
    
    var mqtt: CocoaMQTT = CocoaMQTT(clientID: cilentID, host: host, port: port)
    
    var connExp: XCTestExpectation?
    var subExp: XCTestExpectation?
    
    var pubQos1Exp: XCTestExpectation?
    var pubQos2Exp: XCTestExpectation?
    
    var res0Exp: XCTestExpectation?
    var res1Exp: XCTestExpectation?
    var res2Exp: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        
        // custom set
        mqtt.delegate = self
        mqtt.logLevel = .debug
        mqtt.autoReconnect = true
        mqtt.keepAlive = 60
        mqtt.autoReconnectTimeInterval = 20
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testConnect() {
        connExp = expectation(description: "connection")
        subExp = expectation(description: "sub")
        
        pubQos1Exp = expectation(description: "pub_1")
        pubQos2Exp = expectation(description: "pub_2")
        
        res0Exp = expectation(description: "res_0")
        res1Exp = expectation(description: "res_1")
        res2Exp = expectation(description: "res_2")
        
        mqtt.connect()
        wait(for: [connExp!], timeout: 5)
        
        mqtt.subscribe("animals")
        wait(for: [subExp!], timeout: 5)


        mqtt.publish("animals", withString: "0", qos: .qos0, retained: false, dup: false)
        wait(for: [res0Exp!], timeout: 5)

        mqtt.publish("animals", withString: "1", qos: .qos1, retained: false, dup: false)
        wait(for: [pubQos1Exp!, res1Exp!], timeout: 5)
        
        mqtt.publish("animals", withString: "2", qos: .qos2, retained: false, dup: false)
        wait(for: [pubQos2Exp!, res2Exp!], timeout: 5)
    }
    
    //MARK: - CocoaMQTTDelegate
    
    /// MQTT connected with server
    func mqtt(_ mqtt: CocoaMQTT, didConnect host: String, port: Int) {
    }
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        connExp?.fulfill()
    }
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        
    }
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        pubQos1Exp?.fulfill()
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        pubQos2Exp?.fulfill()
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        
        let string = message.string!
        if string == "0" {
            res0Exp?.fulfill()
        } else if string == "1" {
            res1Exp?.fulfill()
        } else if string == "2" {
            res2Exp?.fulfill()
        }
    }
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        subExp?.fulfill()
    }
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        
    }
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        
    }
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        
    }
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        
    }
}
