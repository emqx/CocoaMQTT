import CocoaMQTT
import CocoaMQTTWebSocket

let coreClient = CocoaMQTT(
    clientID: "swift-6-core",
    host: "localhost"
)

precondition(coreClient.clientID == "swift-6-core")

if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
    let webSocketClient = CocoaMQTT5(
        clientID: "swift-6-websocket",
        host: "localhost",
        port: 8083,
        socket: CocoaMQTTWebSocket(uri: "/mqtt")
    )
    precondition(webSocketClient.clientID == "swift-6-websocket")
}
