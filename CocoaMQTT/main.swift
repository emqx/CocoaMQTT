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
        print("didConnect \(host):\(port)")
    }

    func mqtt(mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("didConnectAck \(ack.rawValue)")
        mqtt.publish("/c/d/e", withString: "hahah")
        mqtt.subscribe("/a/b/c", qos: CocoaMQTTQOS.QOS1)
        //mqtt.publish("/a/b/c", withString: "hello")
        mqtt.ping()
    }

    func mqtt(mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("didPublishMessage to \(message.topic))")
    }

    func mqtt(mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        print("didReceivedMessage with id \(id)")
        print("message.topic: \(message.topic)")
        print("message.payload: \(message.string)")
    }

    func mqtt(mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        print("didSubscribeTopic to \(topic)")
        //mqtt.unsubscribe(topic)
    }

    func mqtt(mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        print("didUnsubscribeTopic to \(topic)")
    }

    func mqttDidPing(mqtt: CocoaMQTT) {
        print("didPing")
    }

    func mqttDidReceivePong(mqtt: CocoaMQTT) {
        _console("didReceivePong")
    }

    func mqttDidDisconnect(mqtt: CocoaMQTT, withError err: NSError?) {
        _console("mqttDidDisconnect")
    }

    func _console(info: String) {
        print("Delegate: \(info)")
    }

}


print("Hello, CocoaMQTT!")

let clientIdPid = "CocoaMQTT-" + String(NSProcessInfo().processIdentifier)
let mqtt = CocoaMQTT(clientId: clientIdPid)
mqtt.username = "test"
mqtt.password = "public"
mqtt.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
mqtt.keepAlive = 5
mqtt.delegate = CocoaMQTTCli()
mqtt.connect()

dispatch_main()
