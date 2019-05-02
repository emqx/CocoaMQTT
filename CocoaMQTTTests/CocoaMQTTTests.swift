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
//let host = "q.emqtt.com"
let port: UInt16 = 1883
let clientID = "ClientForUnitTesting-" + randomCode(length: 6)

let timeout: TimeInterval = 5
let keepAlive: UInt16 = 20
let autoReconn: UInt16 = 5

let topicToSub = "animals"
let longString = longStringGen()

class CocoaMQTTTests: XCTestCase, CocoaMQTTDelegate {
    
    var mqtt: CocoaMQTT = CocoaMQTT(clientID: clientID, host: host, port: port)
    
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
        mqtt.keepAlive = keepAlive
        mqtt.autoReconnectTimeInterval = autoReconn
    }
    
    override func tearDown() {
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
        wait(for: [connExp!], timeout: timeout)
        
        if mqtt.connState != .connected {
            XCTFail()
        }
        
        mqtt.subscribe(topicToSub)
        wait(for: [subExp!], timeout: timeout)

        mqtt.publish(topicToSub, withString: "0", qos: .qos0, retained: false, dup: false)
        wait(for: [res0Exp!], timeout: timeout)

        mqtt.publish(topicToSub, withString: "1", qos: .qos1, retained: false, dup: false)
        wait(for: [pubQos1Exp!, res1Exp!], timeout: timeout)
        
        mqtt.publish(topicToSub, withString: "2", qos: .qos2, retained: false, dup: false)
        wait(for: [pubQos2Exp!, res2Exp!], timeout: timeout)
        
        pubQos1Exp = expectation(description: "pub_1")
        res1Exp = expectation(description: "res_1")
        mqtt.publish(topicToSub, withString: longString, qos: .qos1, retained: false, dup: false)
        wait(for: [pubQos1Exp!, res1Exp!], timeout: timeout)
    }
    
    func testAutoReconnect() {
        connExp = expectation(description: "connection")
        mqtt.connect()
        wait(for: [connExp!], timeout: timeout)
        
        connExp = expectation(description: "connection")
        mqtt.internal_disconnect()
        wait(for: [connExp!], timeout: 10)
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
        } else if string == longString {
            res1Exp?.fulfill()
        } else {
            
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topics: [String]) {
        if topics.first! == topicToSub {
            subExp?.fulfill()
        } else {
            XCTFail()
        }
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

// tools

private func randomCode(length: Int) -> String {
    let base62chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    var code = ""
    for _ in 0..<length {
        let random = Int(arc4random_uniform(62))
        let index = base62chars.index(base62chars.startIndex, offsetBy: random)
        code.append(base62chars[index])
    }
    return code
}

private func longStringGen() -> String {
    var string = ""
    let shijing = "燕燕于飞，差池其羽。之子于归，远送于野。瞻望弗及，泣涕如雨。\n" +
                  "燕燕于飞，颉之颃之。之子于归，远于将之。瞻望弗及，伫立以泣。\n" +
                  "燕燕于飞，下上其音。之子于归，远送于南。瞻望弗及，实劳我心。\n" +
                  "仲氏任只，其心塞渊。终温且惠，淑慎其身。先君之思，以勗寡人。\n"
    
    for _ in 1...100 {
        string.append(shijing)
    }
    return string
}
