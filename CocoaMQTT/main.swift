//
//  main.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqtt.io. All rights reserved.
//

import Foundation


class CocoaMQTTCli: CocoaMQTTDelegate {

    func mqtt(mqtt: CocoaMQTT, didConnect host: String, port: Int) {
        print("didConnect \(host):\(port)")
    }

    func mqtt(mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("didConnectAck \(ack.rawValue)")
        mqtt.subscribe("/a/b/c", qos: CocoaMQTTQOS.QOS1)
        mqtt.publish("/a/b/c", withString: "Qos0 Msg", qos: CocoaMQTTQOS.QOS0)
        mqtt.publish("/a/b/c", withString: "Qos1 Msg", qos: CocoaMQTTQOS.QOS1)
        mqtt.publish("/a/b/c", withString: "Qos2 Msg", qos: CocoaMQTTQOS.QOS2)
        mqtt.ping()
    }

    func mqtt(mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("didPublishMessage to \(message.topic)")
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

let mqttCli = CocoaMQTTCli()
let clientIdPid = "CocoaMQTT-" + String(NSProcessInfo().processIdentifier)
let mqtt = CocoaMQTT(clientId: clientIdPid, host: "localhost", port: 1883)

//mqtts
//let mqtt = CocoaMQTT(clientId: clientIdPid, host: "localhost", port: 8883)
//mqtt.secureMQTT = true

mqtt.username = "test"
mqtt.password = "public"
mqtt.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
mqtt.keepAlive = 90
mqtt.delegate = mqttCli
mqtt.connect()

dispatch_main()
