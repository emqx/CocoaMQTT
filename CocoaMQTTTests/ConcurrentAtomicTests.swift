import XCTest
@testable import CocoaMQTT

final class ConcurrentAtomicTests: XCTestCase {
    @ConcurrentAtomic var value: Int = 1

    func testSetSync() {
        $value.setSync(10)
        XCTAssertEqual($value.wrappedValue, 10, "Set value should be reflected")
    }

    func testAssignmentIsImmediatelyVisible() {
        value = 10
        XCTAssertEqual(value, 10)
    }

    func testMutateReturnsAfterApplyingTransform() {
        value = 1
        let result = $value.mutate { value in
            value *= 20
            return value
        }

        XCTAssertEqual(result, 20)
        XCTAssertEqual(value, 20)
    }

    func testConcurrentMutationsAreAtomic() {
        value = 0

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        for _ in 0..<100 {
            group.enter()
            queue.async {
                self.$value.mutate { $0 += 1 }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(value, 100)
    }

    func testCompareAndSet() {
        value = 10

        XCTAssertFalse($value.compareAndSet(expected: 9, newValue: 11))
        XCTAssertEqual(value, 10)
        XCTAssertTrue($value.compareAndSet(expected: 10, newValue: 12))
        XCTAssertEqual(value, 12)
    }
}
