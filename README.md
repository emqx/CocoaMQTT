# CocoaMQTT

![PodVersion](https://img.shields.io/cocoapods/v/CocoaMQTT5.svg)
![Platforms](https://img.shields.io/cocoapods/p/CocoaMQTT5.svg)
![License](https://img.shields.io/cocoapods/l/BadgeSwift.svg?style=flat)
![Swift version](https://img.shields.io/badge/swift-5-orange.svg)

MQTT v3.1.1 and v5.0 client library for iOS/macOS/tvOS/visionOS written with Swift 5.
visionOS is supported through Swift Package Manager.

Both Swift Package Manager products can be used by Swift 6 applications and
are covered by a Swift 6 compatibility check in CI.


## Build

Build with Xcode 11.1 / Swift 5.1

IOS Target: 12.0 or above
OSX Target: 10.13 or above
TVOS Target: 12.0 or above with Swift Package Manager or CocoaPods WebSockets;
10.0 or above with CocoaPods Core
visionOS Target: 1.0 or above (Swift Package Manager only, compile-verified in CI)

##  xcode 14.3 issue:
```ruby
File not found: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/arc/libarclite_iphonesimulator.a
```
If you encounter the issue, Please update your project minimum depolyments to 11.0


## Installation

### Swift Package Manager

To integrate CocoaMQTT into your Xcode project using [Swift Package Manager](https://swift.org/package-manager/), follow these steps:

1. Open your project in Xcode.
2. Go to `File` > `Swift Packages` > `Add Package Dependency`.
3. Enter the repository URL: `https://github.com/emqx/CocoaMQTT.git`.
4. Choose the latest version or specify a version range.
5. Add the package to your target.

Swift Package Manager supports iOS, macOS, tvOS, and visionOS. Both the
`CocoaMQTT` and `CocoaMQTTWebSocket` products are compile-verified against the
visionOS SDK in CI.

At last, import "CocoaMQTT" to your project:

```swift
import CocoaMQTT
```

### CocoaPods

To integrate CocoaMQTT into your Xcode project using [CocoaPods](http://cocoapods.org), you need to modify you `Podfile` like the followings:

> **visionOS:** CocoaPods installation is not currently supported because the
> transitive CocoaPods dependencies do not declare visionOS compatibility. Use
> Swift Package Manager for visionOS applications.

```ruby
use_frameworks!

target 'Example' do
    pod 'CocoaMQTT'
end
```

Then, run the following command:

```bash
$ pod install
```

At last, import "CocoaMQTT" to your project:

```swift
import CocoaMQTT
```

## Usage

Create a client to connect [MQTT broker](https://www.emqx.com/en/mqtt/public-mqtt5-broker):

```swift
///MQTT 5.0
let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
let mqtt5 = CocoaMQTT5(clientID: clientID, host: "broker.emqx.io", port: 1883)

let connectProperties = MqttConnectProperties()
connectProperties.topicAliasMaximum = 0
connectProperties.sessionExpiryInterval = 0
connectProperties.receiveMaximum = 100
connectProperties.maximumPacketSize = 500
mqtt5.connectProperties = connectProperties

mqtt5.username = "test"
mqtt5.password = "public"
mqtt5.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
mqtt5.keepAlive = 60
mqtt5.delegate = self
mqtt5.connect()

///MQTT 3.1.1
let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
let mqtt = CocoaMQTT(clientID: clientID, host: "broker.emqx.io", port: 1883)
mqtt.username = "test"
mqtt.password = "public"
mqtt.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
mqtt.keepAlive = 60
mqtt.delegate = self
mqtt.connect()
```

Now you can use closures instead of `CocoaMQTTDelegate`:

```swift 
mqtt.didReceiveMessage = { mqtt, message, id in
    print("Message received in topic \(message.topic) with payload \(message.string!)")           
}
```

## TLS

### Publicly trusted server certificate

Enable TLS for a broker whose certificate is rooted in the Apple system trust
store. CocoaMQTT verifies the certificate against the broker host by default.

```swift
mqtt.enableSSL = true
```

When connecting to an IP address while the certificate is issued to a DNS name,
set the certificate name explicitly:

```swift
mqtt.tlsServerName = "broker.example.com"
```

### Private CA or self-signed CA

Load a DER or PEM encoded CA certificate and decide whether the system trust
store should also be accepted:

```swift
let data = try Data(contentsOf: Bundle.main.url(forResource: "broker-ca", withExtension: "crt")!)
guard let certificate = CocoaMQTTSocket.serverCertificate(from: data) else {
    fatalError("Invalid CA certificate")
}

mqtt.trustedServerCertificates = [certificate]
mqtt.usesSystemTrustStore = false // Trust only this CA.
mqtt.enableSSL = true
```

For advanced pinning or enterprise policies, set `manuallyEvaluateTrust = true`
and implement the trust delegate method or `didReceiveTrust` closure. Never
accept every certificate in production. The legacy
`allowUntrustCACertificate` property only enables this manual evaluation; it
does not safely trust a private CA by itself.

### Mutual TLS

For a complete setup that works with either `CocoaMQTT` or `CocoaMQTT5`, see
the [PEM/DER example](Example/Example/MutualTLSConfiguration.swift#L34-L55) or
the [PKCS#12 example](Example/Example/MutualTLSConfiguration.swift#L61-L78).
Both examples configure the client identity and broker trust separately.

`certificateData` accepts a DER certificate, a single PEM certificate, or a PEM
bundle with the leaf first followed by its intermediates. `privateKeyData`
accepts RSA PKCS#1 (`RSA PRIVATE KEY`) or unencrypted RSA PKCS#8 (`PRIVATE KEY`)
input. Encrypted and EC PEM private keys are not currently supported. The
intermediate array is flattened in the supplied order after any certificates in
the leaf bundle; duplicates and a repeated leaf are ignored. Pass the leaf
issuer first and normally exclude the root. It is independent from
`trustedServerCertificates`, which validates the broker. The PEM/DER importer
requires macOS 10.14, iOS 12, tvOS 12, or visionOS 1. This API applies to the
built-in TCP transport, not MQTT over WebSocket; assigning it to a client using
another socket transport has no effect.

PKCS#12 is a password-protected identity container supported by Apple's
[`SecPKCS12Import`](https://developer.apple.com/documentation/security/secpkcs12import%28_%3A_%3A_%3A%29).
The example imports its identity and certificate chain, then uses the same
`clientIdentity` API as the PEM/DER path.

Do not ship a production unencrypted PEM private key in the application bundle.
Do not embed a PKCS#12 file together with its password either. Obtain credentials
through secure provisioning or user input, and keep long-lived secrets in
Keychain-backed storage. The file format itself does not determine App Store
eligibility; use supported Security framework APIs and protect the private key.

## MQTT over Websocket

In the 1.3.0, The CocoaMQTT has supported to connect to MQTT Broker by Websocket.

If you integrated by **Swift Package Manager**, follow these steps:

1. Open your project in Xcode.
2. Go to `File` > `Swift Packages` > `Add Package Dependency`.
3. Enter the repository URL: `https://github.com/emqx/CocoaMQTT.git`.
4. Choose the latest version or specify a version range.
5. Add the package to your target.

At last, import "CocoaMQTT" and "Starscream" to your project:

```swift
import CocoaMQTT
import CocoaMQTTWebSocket
import Starscream
```

If you integrated by **CocoaPods**, you need to modify you `Podfile` like the followings and execute `pod install` again:

```ruby
use_frameworks!

target 'Example' do
    pod 'CocoaMQTT/WebSockets'
end
```

If you're using CocoaMQTT in a project with only a `.podspec` and no `Podfile`, e.g. in a module for React Native, add this line to your `.podspec`:

```ruby
Pod::Spec.new do |s|
  ...
  s.dependency "Starscream"
end
```

Then, Create a MQTT instance over Websocket:

```swift
///MQTT 5.0
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
let mqtt5 = CocoaMQTT5(clientID: clientID, host: host, port: 8083, socket: websocket)
let connectProperties = MqttConnectProperties()
connectProperties.topicAliasMaximum = 0
// ...
mqtt5.connectProperties = connectProperties
// ...

_ = mqtt5.connect()

///MQTT 3.1.1
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
let mqtt = CocoaMQTT(clientID: clientID, host: host, port: 8083, socket: websocket)

// ...

_ = mqtt.connect()
```

The built-in Foundation WebSocket transport fails a receive when one WebSocket
message reaches its 1 MiB buffering limit. Set a value greater than the largest
expected WebSocket message before connecting, or use `0` to remove the limit:

```swift
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
websocket.maximumMessageSize = 10 * 1024 * 1024 + 1 // Accept up to 10 MiB.
```

This setting is independent of MQTT 5 Maximum Packet Size. It is not used by
the older Starscream transport, and custom connection builders must configure
their own transport. Use `0` only when message sizes are otherwise controlled,
because it permits unbounded buffering.

If you want to add additional custom header to the connection, you can use the following:

```swift
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
websocket.headers = [
            "x-api-key": "value"
        ]
        websocket.enableSSL = true

let mqtt = CocoaMQTT(clientID: clientID, host: host, port: 8083, socket: websocket)

// ...

_ = mqtt.connect()
```

If you want to connect using WebSocket Secure (wss), you can use the following example:

```swift
import CocoaMQTT
import CocoaMQTTWebSocket
import Starscream

class WebSocketManager {
    
    private var mqttClient: CocoaMQTT?
    var message: String = ""
    var token: String = ""

    func setupMQTTClient(with token: String) {
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        socket.enableSSL = true
        mqttClient = CocoaMQTT(clientID: token, host: "host", port: 443, socket: socket)
        mqttClient?.delegate = self
    }

    func connect() {
        guard let mqttClient = mqttClient else { return }
        mqttClient.connect()
    }
    
}

extension WebSocketManager: CocoaMQTTDelegate {

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        print("Published message with ID: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        print("Unsubscribed from topics: \(topics)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        print("MQTT did ping")
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        print("MQTT did receive pong")
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: (any Error)?) {
        print("Disconnected from MQTT broker with error: \(String(describing: err))")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("Connected to MQTT broker with acknowledgment: \(ack)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        if let messageString = message.string {
            DispatchQueue.main.async {
                self.message = messageString
            }
            print("Received message: \(messageString) on topic: \(message.topic)")
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("Published message: \(message.string ?? "") with ID: \(id)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        print("Subscribed to topics: \(success), failed to subscribe to: \(failed)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWithError err: Error?) {
        print("Disconnected from MQTT broker with error: \(String(describing: err))")
    }
    
}
```

### Large outgoing messages

Socket writes have a five-second deadline by default. Increase it before
publishing large messages on slower connections:

```swift
mqtt.socketWriteTimeout = 30
```

Set `socketWriteTimeout` to `0` or a negative value to disable the deadline.
This setting applies to MQTT 3.1.1 and MQTT 5 over the built-in TCP and
WebSocket transports. It does not override the broker's packet-size limit or
the MQTT 5 Server Maximum Packet Size. Prefer binary payloads or
application-level chunking when messages are large; Base64 increases their
encoded size.

## Example App

You can follow the Example App to learn how to use it. But we need to make the Example App works first:

```bash
$ cd Examples
```

Then, open the `Example.xcodeproj` by Xcode and start it!

## Dependencies


These third-party functions are used:

~~[GCDAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket)~~
* [MqttCocoaAsyncSocket](https://github.com/leeway1208/MqttCocoaAsyncSocket)
* [Starscream](https://github.com/daltoniam/Starscream)


## LICENSE

MIT License (see `LICENSE`)

## Contributors

* [@andypiper](https://github.com/andypiper)
* [@turtleDeng](https://github.com/turtleDeng)
* [@jan-bednar](https://github.com/jan-bednar)
* [@jmiltner](https://github.com/jmiltner)
* [@manucheri](https://github.com/manucheri)
* [@Cyrus Ingraham](https://github.com/cyrusingraham)

## Author

- Feng Lee <feng@emqx.io>
- CrazyWisdom <zh.whong@gmail.com>
- Alex Yu <alexyu.dc@gmail.com>
- Leeway <leeway1208@gmail.com>


## Twitter

https://twitter.com/EMQTech
