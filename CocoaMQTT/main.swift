//
//  main.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng.lee@nextalk.im> on 14/8/3.
//  Copyright (c) 2014年 slimpp.io. All rights reserved.
//

import Foundation


class CocoaMQTTCli: CocoaMQTTDelegate {
    
    
    func mqtt(mqtt: CocoaMQTT, didConnect host: String, port: Int) {
        println("didConnect \(host):\(port)")
    }
    
    func mqtt(mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        println("didConnectAck \(ack.toRaw())")
        mqtt.publish("/c/d/e", withString: "hahah")
        mqtt.subscribe("/a/b/c", qos: CocoaMQTTQOS.QOS1)
        mqtt.ping()
    }
    
    func mqtt(mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        println("didPublishMessage to \(message.topic))")
    }
    
    func mqtt(mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        println("didReceivedMessage with id \(id)")
        println("message.topic: \(message.topic)")
        println("message.payload: \(message.string)")
    }
    
    func mqtt(mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        println("didSubscribeTopic to \(topic)")
        //mqtt.unsubscribe(topic)
    }
    
    func mqtt(mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        println("didUnsubscribeTopic to \(topic)")
    }
    
    func mqttDidPing(mqtt: CocoaMQTT) {
        println("didPing")
    }
    
    func mqttDidReceivePong(mqtt: CocoaMQTT) {
        _console("didReceivePong")
    }
    
    func mqttDidDisconnect(mqtt: CocoaMQTT, withError err: NSError) {
        _console("mqttDidDisconnect")
    }
    
    func _console(info: String) {
        println("Delegate: \(info)")
    }
    
}


println("Hello, CocoaMQTT!")

let mqtt = CocoaMQTT(clientId: "CocoaMQTT-Client")
mqtt.username = "test"
mqtt.password = "public"
mqtt.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
mqtt.keepAlive = 5
mqtt.delegate = CocoaMQTTCli()
mqtt.connect()

dispatch_main()

