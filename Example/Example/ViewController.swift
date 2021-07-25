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

    let defaultHost = "localhost"

    var mqtt: CocoaMQTT?
    var animal: String?

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var animalsImageView: UIImageView! {
        didSet {
            animalsImageView.clipsToBounds = true
            animalsImageView.layer.borderWidth = 1.0
            animalsImageView.layer.cornerRadius = animalsImageView.frame.width / 2.0
        }
    }
    
    @IBAction func connectToServer() {
        _ = mqtt!.connect()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        tabBarController?.delegate = self
        animal = tabBarController?.selectedViewController?.tabBarItem.title
        mqttSetting()
        // selfSignedSSLSetting()
        // simpleSSLSetting()
        //mqttWebsocketsSetting()
        // mqttWebsocketSSLSetting()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.navigationBar.isHidden = false
    }
    
    func mqttSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 6301)

        let connectProperties = FrameConnectProperties.init()
        connectProperties.topicAliasMaximum = 60
        connectProperties.sessionExpiryInterval = 0
        connectProperties.receiveMaximum = 100
        connectProperties.maximumPacketSize = 500

        mqtt!.connectProperties = connectProperties
        mqtt!.username = ""
        mqtt!.password = ""

        let lastWillMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        lastWillMessage.contentType = "JSON"
        lastWillMessage.willExpiryInterval = 0
        lastWillMessage.willDelayInterval = 0

        mqtt!.willMessage = lastWillMessage
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
    }
    
    func simpleSSLSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 8883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self

        mqtt!.enableSSL = true
    }
    
    func selfSignedSSLSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 8883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self

        mqtt!.enableSSL = true
        mqtt!.allowUntrustCACertificate = true
        let clientCertArray = getClientCertFromP12File(certName: "client-keycert", certPassword: "MySecretPassword")
        var sslSettings: [String: NSObject] = [:]
        sslSettings[kCFStreamSSLCertificates as String] = clientCertArray

        mqtt!.sslSettings = sslSettings
    }
    
    func mqttWebsocketsSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 8083, socket: websocket)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
    }
    
    func mqttWebsocketSSLSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
        mqtt = CocoaMQTT(clientID: clientID, host: defaultHost, port: 8084, socket: websocket)
        mqtt!.enableSSL = true
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self

    }
    
    func getClientCertFromP12File(certName: String, certPassword: String) -> CFArray? {
        // get p12 file path
        let resourcePath = Bundle.main.path(forResource: certName, ofType: "p12")
        
        guard let filePath = resourcePath, let p12Data = NSData(contentsOfFile: filePath) else {
            print("Failed to open the certificate file: \(certName).p12")
            return nil
        }
        
        // create key dictionary for reading p12 file
        let key = kSecImportExportPassphrase as String
        let options : NSDictionary = [key: certPassword]
        
        var items : CFArray?
        let securityError = SecPKCS12Import(p12Data, options, &items)
        
        guard securityError == errSecSuccess else {
            if securityError == errSecAuthFailed {
                print("ERROR: SecPKCS12Import returned errSecAuthFailed. Incorrect password?")
            } else {
                print("Failed to open the certificate file: \(certName).p12")
            }
            return nil
        }
        
        guard let theArray = items, CFArrayGetCount(theArray) > 0 else {
            return nil
        }
        
        let dictionary = (theArray as NSArray).object(at: 0)
        guard let identity = (dictionary as AnyObject).value(forKey: kSecImportItemIdentity as String) else {
            return nil
        }
        let certArray = [identity] as CFArray
        
        return certArray
    }

}

extension ViewController: CocoaMQTTDelegate {
    
    // Optional ssl CocoaMQTTDelegate
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        TRACE("trust: \(trust)")
        /// Validate the server certificate
        ///
        /// Some custom validation...
        ///
        /// if validatePassed {
        ///     completionHandler(true)
        /// } else {
        ///     completionHandler(false)
        /// }
        completionHandler(true)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTCONNACKReasonCode) {
        TRACE("ack: \(ack)")

        if ack == .success {
            mqtt.subscribe("chat/room/animals/client/+", qos: CocoaMQTTQoS.qos1)
            
            let chatViewController = storyboard?.instantiateViewController(withIdentifier: "ChatViewController") as? ChatViewController
            chatViewController?.mqtt = mqtt
            navigationController!.pushViewController(chatViewController!, animated: true)
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        TRACE("new state: \(state)")
        if state == .disconnected {

        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        TRACE("message: \(message.string.description), id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        TRACE("id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        TRACE("message: \(message.string.description), id: \(id)")
        let name = NSNotification.Name(rawValue: "MQTTMessageNotification" + animal!)

        NotificationCenter.default.post(name: name, object: self, userInfo: ["message": message.string!, "topic": message.topic, "id": id, "animal": animal as Any])
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        TRACE("subscribed: \(success), failed: \(failed)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        TRACE("topic: \(topics)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        TRACE()
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        TRACE()
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        TRACE("\(err.description)")
        let name = NSNotification.Name(rawValue: "MQTTMessageNotificationDisconnect")
        NotificationCenter.default.post(name: name, object: nil)
    }
}

extension ViewController: UITabBarControllerDelegate {
    // Prevent automatic popToRootViewController on double-tap of UITabBarController
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        return viewController != tabBarController.selectedViewController
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        print("---- \(tabBarController.selectedIndex)")
        print("----- \(String(describing: tabBarController.selectedViewController))")
    }
}

extension ViewController {
    func TRACE(_ message: String = "", fun: String = #function) {
        let names = fun.components(separatedBy: ":")
        var prettyName: String
        if names.count == 2 {
            prettyName = names[0]
        } else {
            prettyName = names[1]
        }
        
        if fun == "mqttDidDisconnect(_:withError:)" {
            prettyName = "didDisconnect"
        }

        print("[TRACE] [\(prettyName)]: \(message)")
    }
}

extension Optional {
    // Unwrap optional value for printing log only
    var description: String {
        if let self = self {
            return "\(self)"
        }
        return ""
    }
}
