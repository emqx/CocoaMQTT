import XCTest
@testable import CocoaMQTT

final class ConcurrentAtomicTests: XCTestCase {
    private enum MutationError: Error, Equatable {
        case expected
    }

    @ConcurrentAtomic var value: Int = 1

    func testSetSync() {
        $value.setSync(10)
        XCTAssertEqual($value.wrappedValue, 10, "Set value should be reflected")
    }

    func testAssignmentIsImmediatelyVisible() {
        value = 10
        XCTAssertEqual(value, 10)
    }

    func testWithMutationReturnsAfterApplyingTransform() {
        value = 1
        let result = $value.withMutation { value in
            value *= 20
            return value
        }

        XCTAssertEqual(result, 20)
        XCTAssertEqual(value, 20)
    }

    @available(*, deprecated, message: "Exercises the CocoaMQTT 2.3 compatibility overload")
    func testResultReturningMutateCompatibilityOverload() {
        value = 1
        let result = $value.mutate { value -> Int in
            value *= 20
            return value
        }

        XCTAssertEqual(result, 20)
        XCTAssertEqual(value, 20)
    }

    @available(*, deprecated, message: "Exercises the CocoaMQTT 2.3 compatibility overload")
    func testThrowingMutateCompatibilityOverload() {
        value = 1

        XCTAssertThrowsError(try $value.mutate { value -> Int in
            value = 20
            throw MutationError.expected
        }) { error in
            XCTAssertEqual(error as? MutationError, .expected)
        }
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

    func testMutationObserverReceivesAssignmentsAndTransforms() {
        var observedValues = [Int]()
        $value.setMutationObserver { observedValues.append($0) }

        value = 2
        $value.mutate { $0 += 3 }
        $value.setSync(8)
        XCTAssertFalse($value.compareAndSet(expected: 7, newValue: 9))
        XCTAssertTrue($value.compareAndSet(expected: 8, newValue: 9))

        XCTAssertEqual(observedValues, [2, 5, 8, 9])
    }
}
