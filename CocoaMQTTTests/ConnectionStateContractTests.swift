import XCTest
@testable import CocoaMQTT

final class ConnectionStateContractTests: XCTestCase {
    private struct ClientHarness {
        let name: String
        let state: () -> CocoaMQTTConnState
        let setState: (CocoaMQTTConnState) -> Void
        let setDelegateQueue: (DispatchQueue) -> Void
        let observeState: (@escaping (CocoaMQTTConnState) -> Void) -> Void
    }

    private func clients() -> [ClientHarness] {
        let mqtt = CocoaMQTT(clientID: "connection-state-contract-311-\(UUID().uuidString)")
        let mqtt5 = CocoaMQTT5(clientID: "connection-state-contract-5-\(UUID().uuidString)")

        return [
            ClientHarness(
                name: "MQTT 3.1.1",
                state: { mqtt.connState },
                setState: { mqtt.connState = $0 },
                setDelegateQueue: { mqtt.delegateQueue = $0 },
                observeState: { observer in
                    mqtt.didChangeState = { _, state in observer(state) }
                }
            ),
            ClientHarness(
                name: "MQTT 5",
                state: { mqtt5.connState },
                setState: { mqtt5.connState = $0 },
                setDelegateQueue: { mqtt5.delegateQueue = $0 },
                observeState: { observer in
                    mqtt5.didChangeState = { _, state in observer(state) }
                }
            )
        ]
    }

    func testClientsStartDisconnectedAndMakeWritesSynchronouslyVisible() {
        for client in clients() {
            XCTAssertEqual(client.state(), .disconnected, client.name)

            client.setState(.connecting)
            XCTAssertEqual(client.state(), .connecting, client.name)

            client.setState(.connected)
            XCTAssertEqual(client.state(), .connected, client.name)
        }
    }

    func testClientsDispatchStateCallbacksInWriteOrder() {
        for client in clients() {
            let callbackQueue = DispatchQueue(
                label: "tests.connection-state-contract.callback.\(client.name)"
            )
            let callbackGate = DispatchSemaphore(value: 0)
            let callbacksReceived = expectation(
                description: "\(client.name) state callbacks"
            )
            callbacksReceived.expectedFulfillmentCount = 4
            var receivedStates = [CocoaMQTTConnState]()

            callbackQueue.async {
                callbackGate.wait()
            }
            client.setDelegateQueue(callbackQueue)
            client.observeState { state in
                receivedStates.append(state)
                callbacksReceived.fulfill()
            }

            client.setState(.connecting)
            client.setState(.connecting)
            client.setState(.connected)
            client.setState(.disconnected)
            callbackGate.signal()

            wait(for: [callbacksReceived], timeout: 1)
            callbackQueue.sync {}
            XCTAssertEqual(
                receivedStates,
                [.connecting, .connecting, .connected, .disconnected],
                client.name
            )
        }
    }
}
