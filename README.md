CocoaMQTT
=========

An MQTT client for iOS and OS X written with Swift

Currently supports MQTT 3.1 (not MQTT 3.1.1)


Build
=====
Builds in Xcode 6.4 / Swift 1.2

Optionally uses [Swiftlint](https://github.com/realm/SwiftLint) (only in install stage, 
remove run script build phase to skip or ignore linting)


Usage
=====
Example in `main.swift` (note this defaults to connect to localhost):

```swift
let mqtt = CocoaMQTT(clientId: "CocoaMQTT-ClientId")
mqtt.username = "test"
mqtt.password = "public"
mqtt.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
mqtt.keepAlive = 5
mqtt.delegate = CocoaMQTTCli()
mqtt.connect()
```


CocoaMQTT
==========

```swift
/**
 * Blueprint of the mqtt client
 **/
protocol CocoaMQTTClient {
    
    var host: String { get set }
    
    var port: UInt16 { get set }
    
    var clientId: String { get }
    
    var username: String? {get set}
    
    var password: String? {get set}
    
    var cleansess: Bool {get set}
    
    var keepAlive: UInt16 {get set}
    
    var willMessage: CocoaMQTTWill? {get set}
    
    func connect() -> Bool
    
    func publish(topic: String, withString string: String, qos: CocoaMQTTQOS) -> UInt16
    
    func publish(message: CocoaMQTTMessage) -> UInt16
    
    func subscribe(topic: String, qos: CocoaMQTTQOS) -> UInt16
    
    func unsubscribe(topic: String) -> UInt16
    
    func ping()
    
    func disconnect()
    
}
```


CocoaMQTTDelegate
=================

```swift
protocol CocoaMQTTDelegate {
    
    /**
     * MQTT connected with server
     */
    func mqtt(mqtt: CocoaMQTT, didConnect host: String, port: Int)
    
    func mqtt(mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)
    
    func mqtt(mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16)
    
    func mqtt(mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 )
    
    func mqtt(mqtt: CocoaMQTT, didSubscribeTopic topic: String)
    
    func mqtt(mqtt: CocoaMQTT, didUnsubscribeTopic topic: String)
    
    func mqttDidPing(mqtt: CocoaMQTT)
    
    func mqttDidReceivePong(mqtt: CocoaMQTT)
    
    func mqttDidDisconnect(mqtt: CocoaMQTT, withError err: NSError)

}
```


AsyncSocket and Timer
=====================

These third-party functions are used:

* [GCDAsyncSocket.h](https://github.com/robbiehanson/CocoaAsyncSocket)
* [MSWeakTimer.h](https://github.com/mindsnacks/MSWeakTimer)


LICENSE
=======

MIT License (see `LICENSE`)

## Contributors

* [@andypiper](https://github.com/andypiper)


Author
======

feng@emqtt.io

