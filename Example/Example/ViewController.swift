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
        mqtt!.connect()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        tabBarController?.delegate = self
        animal = tabBarController?.selectedViewController?.tabBarItem.title
        mqttSetting()
        // selfSignedSSLSetting()
        // simpleSSLSetting()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.navigationBar.isHidden = false
    }
    
    func mqttSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: "127.0.0.1", port: 1883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
    }
    
    func simpleSSLSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: "127.0.0.1", port: 8883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
        mqtt!.enableSSL = true
    }
    
    func selfSignedSSLSetting() {
        let clientID = "CocoaMQTT-\(animal!)-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: "127.0.0.1", port: 8883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
        mqtt!.enableSSL = true
        
        let clientCertArray = getClientCertFromP12File(certName: "client-keycert", certPassword: "MySecretPassword")
        
        var sslSettings: [String: NSObject] = [:]
        sslSettings[kCFStreamSSLCertificates as String] = clientCertArray
        
        mqtt!.sslSettings = sslSettings
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
    func mqtt(_ mqtt: CocoaMQTT, didConnect host: String, port: Int) {
        print("didConnect \(host):\(port)")
    }
    
    // Optional ssl CocoaMQTTDelegate
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
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
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("didConnectAck: \(ack)，rawValue: \(ack.rawValue)")
        
        if ack == .accept {
            mqtt.subscribe("chat/room/animals/client/+", qos: CocoaMQTTQOS.qos1)
            
            let chatViewController = storyboard?.instantiateViewController(withIdentifier: "ChatViewController") as? ChatViewController
            chatViewController?.mqtt = mqtt
            navigationController!.pushViewController(chatViewController!, animated: true)
        }
        
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("didPublishMessage with message: \(message.string)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        print("didPublishAck with id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        print("didReceivedMessage: \(message.string) with id \(id)")
        let name = NSNotification.Name(rawValue: "MQTTMessageNotification" + animal!)
        NotificationCenter.default.post(name: name, object: self, userInfo: ["message": message.string!, "topic": message.topic])
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        print("didSubscribeTopic to \(topic)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        print("didUnsubscribeTopic to \(topic)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        print("didPing")
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        _console("didReceivePong")
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        _console("mqttDidDisconnect")
    }
    
    func _console(_ info: String) {
        print("Delegate: \(info)")
    }
}

extension ViewController: UITabBarControllerDelegate {
    // Prevent automatic popToRootViewController on double-tap of UITabBarController
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        return viewController != tabBarController.selectedViewController
    }
}
