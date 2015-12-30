//
//  ViewController.swift
//  Example
//
//  Created by CrazyWisdom on 15/12/14.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import UIKit
import CocoaMQTT

class ViewController: UIViewController {
    let clientIdPid = "CocoaMQTT-" + String(NSProcessInfo().processIdentifier)
    var mqtt: CocoaMQTT?
    var connected: Bool = false {
        didSet {
            if connected {
                navigationItem.title = "Online"
                connectButton.setTitle("Disconnect", forState: .Normal)
            } else {
                navigationItem.title = "Offline"
                
                connectButton.setTitle("Connect", forState: .Normal)
            }
        }
    }
    
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var animalsImageView: UIImageView! {
        didSet {
            animalsImageView.clipsToBounds = true
            animalsImageView.layer.borderWidth = 1.0
            animalsImageView.layer.cornerRadius = animalsImageView.frame.width / 2.0
        }
    }
    
    @IBAction func connectToServer() {
        if connected {
            mqtt!.disconnect()
        } else {
            mqtt!.connect()
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mqttSetting()
    }

    func mqttSetting() {
        mqtt = CocoaMQTT(clientId: clientIdPid, host: "localhost", port: 1883)
        //mqtts
        //let mqtt = CocoaMQTT(clientId: clientIdPid, host: "localhost", port: 8883)
        //mqtt.secureMQTT = true
        if let mqtt = mqtt {
            mqtt.username = "test"
            mqtt.password = "public"
            mqtt.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
            mqtt.keepAlive = 90
            mqtt.delegate = self
        }
    }

}


extension ViewController: CocoaMQTTDelegate {
    
    func mqtt(mqtt: CocoaMQTT, didConnect host: String, port: Int) {
        print("didConnect \(host):\(port)")
    }
    
    func mqtt(mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("didConnectAck \(ack.rawValue)")
        if ack == .ACCEPT {
            connected = true
            mqtt.subscribe("/a/b/c", qos: CocoaMQTTQOS.QOS1)
            mqtt.ping()
            
            let chatViewController = storyboard?.instantiateViewControllerWithIdentifier("ChatViewController") as? ChatViewController
            chatViewController?.mqtt = mqtt
            //navigationController!.pushViewController(chatViewController!, animated: true)
            navigationController!.presentViewController(chatViewController!, animated: true, completion: nil)
        }
        
    }
    
    func mqtt(mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("didPublishMessage to \(message.topic)")
    }
    
    
    func mqtt(mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        print("didPublishAck with id \(id)")
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
        connected = false
        _console("mqttDidDisconnect")
    }
    
    func _console(info: String) {
        print("Delegate: \(info)")
    }
    
}