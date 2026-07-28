import CocoaMQTT
import CocoaMQTTWebSocket

let coreClient = CocoaMQTT(
    clientID: "swift-6-core",
    host: "localhost"
)
let webSocketClient = CocoaMQTT5(
    clientID: "swift-6-websocket",
    host: "localhost",
    port: 8083,
    socket: CocoaMQTTWebSocket(uri: "/mqtt")
)

precondition(coreClient.clientID == "swift-6-core")
precondition(webSocketClient.clientID == "swift-6-websocket")
