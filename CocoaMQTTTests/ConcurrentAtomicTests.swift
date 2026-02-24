import XCTest
@testable import CocoaMQTT

final class ConcurrentAtomicTests: XCTestCase {
    @ConcurrentAtomic var value: Int = 1

    func testSetSync() {
        $value.setSync(10)
        XCTAssertEqual($value.wrappedValue, 10, "Set value should be reflected")
    }

    func testMutate() {
        // Reset the value to a known state
        $value.setSync(1)
        XCTAssertEqual(self.value, 1, "Immediately after async mutate, value should still be 1")
        // Asynchronously multiply the value
        $value.mutate {
            // 0.1 seconds delay
            usleep(100_000)
            $0 *= 20
        }
        XCTAssertEqual(self.value, 20, "Value should still be 20 immediately after async mutate is called")
    }

    func testMultipleAsyncMutations() {
        let expectation = XCTestExpectation(description: "All async mutations completed")

        // Reset to zero before starting concurrent increments
        $value.setSync(0)

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        // Perform 100 asynchronous increments
        for _ in 0..<100 {
            group.enter()
            queue.async {
                self.$value.mutate { $0 += 1 }
                group.leave()
            }
        }

        // Wait for all tasks to finish, then check the result
        group.notify(queue: .main) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(self.value, 100, "All async mutate operations should complete successfully")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
