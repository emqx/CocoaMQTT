//
//  CocoaMQTTTests.swift
//  CocoaMQTTTests
//
//  Created by CrazyWisdom on 15/12/11.
//  Copyright © 2015年 emqx.io. All rights reserved.
//

import XCTest
@testable import CocoaMQTT

let host = "localhost"
let port: UInt16 = 1883
let clientID = "ClientForUnitTesting-" + randomCode(length: 6)

let topicToSub = "animals"
let longString = longStringGen()

class CocoaMQTTTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
     func testConnect() {
         
         let caller = Caller()
         let mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
         mqtt.delegate = caller
         mqtt.logLevel = .debug
         mqtt.autoReconnect = false
         
         _ = mqtt.connect()
         wait_for {
             caller.isConnected
         }
         
         let topics = ["t/0", "t/1", "t/2"]

         mqtt.subscribe(topics[0])
         mqtt.subscribe(topics[1])
         mqtt.subscribe(topics[2])
         wait_for {
             caller.subs == topics
         }
         
         mqtt.publish(topics[0], withString: "0", qos: .qos0, retained: false)
         mqtt.publish(topics[1], withString: "1", qos: .qos1, retained: false)
         mqtt.publish(topics[2], withString: "2", qos: .qos2, retained: false)
         wait_for {
             if caller.recvs.count >= 3 {
                 let f0 = caller.recvs[0]
                 let f1 = caller.recvs[1]
                 let f2 = caller.recvs[2]
                 XCTAssertEqual(f0.topic, topics[0])
                 XCTAssertEqual(f1.topic, topics[1])
                 XCTAssertEqual(f2.topic, topics[2])
                 return true
             }
             return false
         }
         
         mqtt.unsubscribe(topics[0])
         mqtt.unsubscribe(topics[1])
         mqtt.unsubscribe(topics[2])
         wait_for {
             caller.subs == []
         }
         
         mqtt.disconnect()
    }
    
    func testAutoReconnect() {
        let caller = Caller()
        let mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
        mqtt.delegate = caller
        mqtt.logLevel = .debug
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1
        
        _ = mqtt.connect()
        wait_for {
            caller.isConnected
        }
        
        mqtt.internal_disconnect()
        wait_for {
            caller.isConnected == false
        }
        
        wait_for {
            caller.isConnected
        }
        
        mqtt.disconnect()
        wait_for {
            caller.isConnected == false
        }
    }
   
    func testProcessSafePub() {
        let caller = Caller()
        let mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
        mqtt.delegate = caller
        mqtt.logLevel = .debug
        mqtt.autoReconnect = false
        
        _ = mqtt.connect()
        wait_for {
            caller.isConnected
        }

        mqtt.subscribe("t/#", qos: .qos1)
        wait_for {
            caller.subs == ["t/#"]
        }
        
        mqtt.inflightWindowSize = 10
        mqtt.messageQueueSize = 100
        
        let concurrentQueue = DispatchQueue(label: "tests.cocoamqtt.emqx", qos: .default, attributes: .concurrent)
        for i in 0 ..< 100 {
            concurrentQueue.async {
                mqtt.publish("t/\(i)", withString: "m\(i)", qos: .qos1)
            }
        }
        wait_for {
            caller.recvs.count == 100
        }
        
        mqtt.disconnect()
        wait_for {
            caller.isConnected == false
        }
    }
    
    func wait_for(line: Int = #line, t: Int = 5, _ fun: @escaping () -> Bool) {
        let exp = XCTestExpectation()
        let thrd = Thread {
            while true {
                usleep(useconds_t(1000))
                guard fun() else {
                    continue
                }
                exp.fulfill()
                break
            }
        }
        thrd.start()
        wait(for: [exp], timeout: TimeInterval(t))
        thrd.cancel()
    }
    
    private func ms_sleep(_ ms: Int) {
        usleep(useconds_t(ms * 1000))
    }
}

private class Caller: CocoaMQTTDelegate {
    
    var recvs = [FramePublish]()
    
    var sents = [UInt16]()
    
    var acks = [UInt16]()
    
    var subs = [String]()
    
    var isConnected = false
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept { isConnected = true }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        sents.append(id)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        acks.append(id)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        var frame = message.t_pub_frame
        frame.msgid = id
        recvs.append(frame)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics topics: [String]) {
        subs = subs + topics
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        subs = subs.filter { (e) -> Bool in
            !topics.contains(e)
        }
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) { }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) { }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        isConnected = false
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
