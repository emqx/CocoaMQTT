# CocoaMQTT

[English](README.md) | **简体中文**

> [!IMPORTANT]
> **`master` 包含 CocoaMQTT 3 的开发代码，可能存在破坏性变更。**
> 生产环境请使用 [CocoaMQTT 2.4.0](https://github.com/emqx/CocoaMQTT/releases/tag/2.4.0)，
> 它是长期维护的 [`release/2.x`](https://github.com/emqx/CocoaMQTT/tree/release/2.x)
> 分支上的最新版本。另请参阅
> [2.x 文档](https://github.com/emqx/CocoaMQTT/blob/release/2.x/README.md)
> 和[维护策略](https://github.com/emqx/CocoaMQTT/blob/release/2.x/MAINTENANCE.md)。

[![稳定版本](https://img.shields.io/github/v/release/emqx/CocoaMQTT?label=stable)](https://github.com/emqx/CocoaMQTT/releases/latest)
[![CocoaPods](https://img.shields.io/cocoapods/v/CocoaMQTT.svg)](https://cocoapods.org/pods/CocoaMQTT)
![支持平台](https://img.shields.io/cocoapods/p/CocoaMQTT.svg)
[![许可证](https://img.shields.io/github/license/emqx/CocoaMQTT)](LICENSE)
![Swift 版本](https://img.shields.io/badge/swift-5-orange.svg)

CocoaMQTT 是一个使用 Swift 编写的 MQTT 3.1.1 和 MQTT 5.0 客户端库，
支持 iOS、macOS、tvOS 和 visionOS。visionOS 仅支持通过 Swift Package
Manager 集成。

两个 Swift Package Manager product 均可用于 Swift 6 应用，并由 CI
持续进行 Swift 6 兼容性检查。

## 构建要求

Package manifest 要求 Swift tools 5.7。CI 使用当前 Xcode 工具链验证构建，
并检查 Swift 6 兼容性。CocoaPods 使用 Swift 5 语言模式。

| Product | iOS | macOS | tvOS | visionOS |
| --- | --- | --- | --- | --- |
| 通过 Swift Package Manager 集成 `CocoaMQTT` | 12.0 | 10.13 | 12.0 | 1.0 |
| 通过 Swift Package Manager 集成 `CocoaMQTTWebSocket` | 13.0 | 10.15 | 13.0 | 1.0 |
| CocoaPods 2.x Core | 12.0 | 10.13 | 10.0 | 不支持 |
| CocoaPods 2.x WebSockets | 13.0 | 10.15 | 13.0 | 不支持 |

visionOS 支持由 CI 进行编译验证。

## 安装

生产应用应安装稳定的 2.x LTS 版本。以下同时提供 CocoaMQTT 3 首个稳定版
发布前的开发快照体验方式。

### Swift Package Manager

在 Xcode 工程中集成 CocoaMQTT：

1. 打开 Xcode 工程。
2. 选择 `File` > `Swift Packages` > `Add Package Dependency`。
3. 输入仓库地址：`https://github.com/emqx/CocoaMQTT.git`。
4. 选择 `2.4.0`，依赖规则选择 “Up to Next Major Version”
   （`2.4.0 ..< 3.0.0`）。
5. 将 package 添加到应用 target。

然后导入 `CocoaMQTT`：

```swift
import CocoaMQTT
```

如需体验 CocoaMQTT 3，请在 Xcode 中选择 `master` 分支，或使用分支依赖：

```swift
.package(url: "https://github.com/emqx/CocoaMQTT.git", branch: "master")
```

生产版本请勿依赖未固定版本的 `master` 分支。

### CocoaPods

使用 [CocoaPods](https://cocoapods.org) 集成 CocoaMQTT 2.x 时，在
`Podfile` 中加入：

> **visionOS：** CocoaPods 暂不支持 visionOS，因为其传递依赖的 podspec
> 尚未声明 visionOS 兼容性。visionOS 应用请使用 Swift Package Manager。

```ruby
use_frameworks!

target 'Example' do
    pod 'CocoaMQTT', '~> 2.4'
end
```

然后执行：

```bash
pod install
```

并在代码中导入：

```swift
import CocoaMQTT
```

CocoaMQTT 3 开发快照尚未发布到 CocoaPods。体验 3.0 时请使用上面的 Swift
Package Manager 分支依赖或本地 checkout。

## 使用

以下内容描述 `master` 上的 CocoaMQTT 3 API。稳定版 CocoaMQTT 2.4 的用法
请参阅 [2.x README](https://github.com/emqx/CocoaMQTT/blob/release/2.x/README.md)。

创建 MQTT 5 客户端：

```swift
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
```

或创建 MQTT 3.1.1 客户端：

```swift
let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
let mqtt = CocoaMQTT(clientID: clientID, host: "broker.emqx.io", port: 1883)
mqtt.username = "test"
mqtt.password = "public"
mqtt.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
mqtt.keepAlive = 60
mqtt.delegate = self
mqtt.connect()
```

也可以使用闭包代替 `CocoaMQTTDelegate`：

```swift
mqtt.didReceiveMessage = { mqtt, message, id in
    print("收到主题 \(message.topic) 的消息：\(message.string ?? "")")
}
```

## TLS

### 由公共 CA 签发的服务端证书

当 broker 证书的根证书位于 Apple 系统信任库中时，启用 TLS 即可。
CocoaMQTT 默认会根据 broker host 验证证书。

```swift
mqtt.enableSSL = true
```

如果使用 IP 地址连接，而证书签发给 DNS 域名，请显式设置证书名称：

```swift
mqtt.tlsServerName = "broker.example.com"
```

### 私有 CA 或自签名 CA

载入 DER 或 PEM 编码的 CA 证书，并选择是否同时信任系统信任库：

```swift
let data = try Data(contentsOf: Bundle.main.url(forResource: "broker-ca", withExtension: "crt")!)
guard let certificate = CocoaMQTTSocket.serverCertificate(from: data) else {
    fatalError("CA 证书无效")
}

mqtt.trustedServerCertificates = [certificate]
mqtt.usesSystemTrustStore = false // 只信任这个 CA
mqtt.enableSSL = true
```

如需高级证书固定或企业信任策略，请设置 `manuallyEvaluateTrust = true`，
并实现信任验证 delegate 方法或 `didReceiveTrust` 闭包。生产环境中请勿接受
所有证书。旧的 `allowUntrustCACertificate` 属性只会启用手动验证，并不会
安全地信任私有 CA。如果既没有信任回调，也没有配置自定义 CA，启用手动
验证将拒绝连接。

### 双向 TLS

TCP 连接照常创建 `CocoaMQTT` 或 `CocoaMQTT5`。WSS 连接可参考
[MQTT 3.1.1 WebSocket 客户端](Example/Example/MutualTLSConfiguration.swift#L35-L47)
或 [MQTT 5 WebSocket 客户端](Example/Example/MutualTLSConfiguration.swift#L52-L64)。
在 macOS 10.15、iOS 13、tvOS 13、visionOS 1 及更高版本中，
`CocoaMQTTWebSocket` 使用 Apple 的 `URLSessionWebSocketTask`。

调用 `connect()` 前，请应用
[PEM/DER 配置](Example/Example/MutualTLSConfiguration.swift#L70-L93)
或 [PKCS#12 配置](Example/Example/MutualTLSConfiguration.swift#L99-L118)。
两种配置均适用于 MQTT 3.1.1 和 MQTT 5 的 TCP 或
`URLSessionWebSocketTask` WSS 连接，并将客户端身份与 broker 信任配置
相互独立。连接 host 与 broker 证书中的 DNS 名称不同时，请使用函数的
`tlsServerName` 参数。

`certificateData` 支持 DER 证书、单个 PEM 证书，以及 leaf 在前、后接
intermediate 的 PEM bundle。`privateKeyData` 支持 RSA PKCS#1
（`RSA PRIVATE KEY`）或未加密的 RSA PKCS#8（`PRIVATE KEY`）。
目前不支持加密或 EC PEM 私钥。

intermediate 数组会按传入顺序追加在 leaf bundle 内的证书之后，重复证书
和重复 leaf 会被忽略。应先传 leaf 的签发者，通常不要包含根证书。
intermediate 与用于验证 broker 的 `trustedServerCertificates` 相互独立。
PEM/DER importer 要求 macOS 10.14、iOS 12、tvOS 12 或 visionOS 1。
该 API 适用于内置 TCP transport 和 Apple `URLSessionWebSocketTask`
transport。自定义 transport 可通过实现
`CocoaMQTTClientIdentityConfiguring` 选择支持该能力。

`URLSessionWebSocketTask` 客户端身份仅适用于原始 WebSocket host 和端口。
未配置 `clientIdentity` 或发生跨 host 重定向时，客户端证书 challenge
会被取消。

内置 TCP 与 `URLSessionWebSocketTask` transport 均支持相同的高层 TLS
配置：`tlsServerName`、`trustedServerCertificates`、
`usesSystemTrustStore`、`manuallyEvaluateTrust` 和 `clientIdentity`，
同时保留各自已有的回调流程。`sslSettings` 仍是 TCP 专用的底层扩展点。
客户端身份和服务端信任配置相互独立。

对于 WebSocket 连接，`tlsServerName` 会覆盖证书身份验证名称；
WebSocket URL host 仍然决定路由和 TLS SNI。

PKCS#12 是 Apple
[`SecPKCS12Import`](https://developer.apple.com/documentation/security/secpkcs12import%28_%3A_%3A_%3A%29)
支持的密码保护身份容器。示例会导入 identity 和证书链，然后与 PEM/DER
方式共用相同的 `clientIdentity` API。

请勿将生产环境中未加密的 PEM 私钥打包进应用，也不要将 PKCS#12 文件和
密码一起内置。应通过安全配置流程或用户输入获取凭据，并把长期凭据保存到
由 Keychain 支持的存储中。文件格式本身不会决定 App Store 审核结果；
请使用受支持的 Security framework API 并保护私钥。

## MQTT over WebSocket

CocoaMQTT 支持通过 WebSocket 连接 MQTT broker。内置实现使用 Apple
Foundation 的 `URLSessionWebSocketTask`，要求 iOS 13、macOS 10.15、
tvOS 13、visionOS 1 或更高版本。

### 从 Starscream fallback 迁移

CocoaMQTT 3 移除了 Starscream 依赖以及公开的
`CocoaMQTTWebSocket.StarscreamConnection` adapter。使用
`CocoaMQTTWebSocket` 的应用必须将 deployment target 提升至上述版本；
也可以通过 availability check 保护调用，并在旧系统上提供其他实现。

仅在应用中添加 Starscream 依赖不会恢复已移除的 adapter。应用应迁移到
`URLSessionWebSocketTask`；需要支持更旧操作系统时继续使用 CocoaMQTT 2；
或者自行实现 `CocoaMQTTWebSocketConnection` 和
`CocoaMQTTWebSocketConnectionBuilder`。如果应用将 Starscream 用于其他
连接，则应自行显式声明该依赖。

通过 **Swift Package Manager** 集成时：

1. 打开 Xcode 工程。
2. 选择 `File` > `Swift Packages` > `Add Package Dependency`。
3. 输入仓库地址：`https://github.com/emqx/CocoaMQTT.git`。
4. 选择 `master` 分支体验 CocoaMQTT 3。
5. 将 `CocoaMQTT` 和 `CocoaMQTTWebSocket` product 添加到应用 target。

导入对应 product：

```swift
import CocoaMQTT
import CocoaMQTTWebSocket
```

CocoaMQTT 3 尚未通过 CocoaPods 分发。稳定的 CocoaMQTT 2.4 WebSocket
subspec 及其旧系统行为请参阅
[2.x WebSocket 安装说明](https://github.com/emqx/CocoaMQTT/blob/release/2.x/README.md#mqtt-over-websocket)。

创建 WebSocket MQTT 客户端：

```swift
// MQTT 5.0
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
let mqtt5 = CocoaMQTT5(clientID: clientID, host: host, port: 8083, socket: websocket)
let connectProperties = MqttConnectProperties()
connectProperties.topicAliasMaximum = 0
mqtt5.connectProperties = connectProperties
_ = mqtt5.connect()

// MQTT 3.1.1
let websocket311 = CocoaMQTTWebSocket(uri: "/mqtt")
let mqtt = CocoaMQTT(clientID: clientID, host: host, port: 8083, socket: websocket311)
_ = mqtt.connect()
```

Apple `URLSessionWebSocketTask` transport 在单条 WebSocket 消息达到默认的
1 MiB 缓冲上限时会接收失败。连接前应把限制设为大于预期最大消息的值，
或者设为 `0` 取消上限：

```swift
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
websocket.maximumMessageSize = 10 * 1024 * 1024 + 1 // 接收最多 10 MiB
```

该配置与 MQTT 5 Maximum Packet Size 相互独立。自定义 connection builder
需要自行配置 transport。只有在其他位置已经限制消息大小时才应使用 `0`，
否则可能产生无上限的内存缓冲。

添加自定义连接 header：

```swift
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
websocket.headers = ["x-api-key": "value"]
websocket.enableSSL = true

let mqtt = CocoaMQTT(clientID: clientID, host: host, port: 8083, socket: websocket)
_ = mqtt.connect()
```

使用 WebSocket Secure（WSS）时，将 `enableSSL` 设为 `true`：

```swift
let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
websocket.enableSSL = true

let mqtt = CocoaMQTT(clientID: clientID, host: "host", port: 443, socket: websocket)
mqtt.delegate = self
_ = mqtt.connect()
```

### 大消息发送

Socket write 默认有五秒超时。在较慢的连接上发送大消息前，可以延长超时：

```swift
mqtt.socketWriteTimeout = 30
```

将 `socketWriteTimeout` 设为 `0` 或负数可取消 deadline。该配置适用于
MQTT 3.1.1 和 MQTT 5 的内置 TCP 与 WebSocket transport，但不会覆盖
broker packet size 限制或 MQTT 5 Server Maximum Packet Size。大消息应
优先使用二进制 payload 或在应用层分片；Base64 会增大编码后的数据量。

## 示例应用

在仓库根目录打开示例工程：

```bash
open Example/Example.xcodeproj
```

然后在 Xcode 中选择 Example scheme 并运行。

## 依赖

- [MqttCocoaAsyncSocket](https://github.com/leeway1208/MqttCocoaAsyncSocket)

## 许可证

MIT License，详见 [`LICENSE`](LICENSE)。

## 贡献者

- [@andypiper](https://github.com/andypiper)
- [@turtleDeng](https://github.com/turtleDeng)
- [@jan-bednar](https://github.com/jan-bednar)
- [@jmiltner](https://github.com/jmiltner)
- [@manucheri](https://github.com/manucheri)
- [@Cyrus Ingraham](https://github.com/cyrusingraham)

## 作者

- Feng Lee <feng@emqx.io>
- CrazyWisdom <zh.whong@gmail.com>
- Alex Yu <alexyu.dc@gmail.com>
- Leeway <leeway1208@gmail.com>
