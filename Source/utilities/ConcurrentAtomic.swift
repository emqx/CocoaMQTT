import Foundation

/// A thread-safe property wrapper that uses a concurrent dispatch queue for atomic operations.
///
/// Reads run concurrently, while writes and compound mutations use synchronous barriers.
///
/// - Important: Although this wrapper provides atomicity for access, it does not make the wrapped
///   value itself thread-safe if the type is not thread-safe. Avoid wrapping types that manage
///   internal shared state without their own synchronization. A read followed by a write is not
///   one atomic operation; use `mutate` for compound changes.
///
/// - Example:
/// ```swift
/// @ConcurrentAtomic var counter: Int = 0
/// $counter.mutate { $0 += 1 }
/// print(counter)
/// ```
@propertyWrapper
public class ConcurrentAtomic<T> {
    private var _value: T
    private var mutationObserver: ((T) -> Void)?
    private let queue: DispatchQueue

    /// Provides synchronous thread-safe access to the wrapped value.
    ///
    /// - Note: Reads use `queue.sync` and can happen concurrently.
    /// - Note: Writes use a synchronous barrier and are visible when assignment returns.
    public var wrappedValue: T {
        get {
            queue.sync { _value }
        }
        set {
            queue.sync(flags: .barrier) {
                self._value = newValue
                self.mutationObserver?(newValue)
            }
        }
    }

    /// Returns the property wrapper instance itself for advanced usage, including mutation and transformation APIs.
    public var projectedValue: ConcurrentAtomic<T> { self }

    /// Initializes the property wrapper with an initial value and a custom queue label.
    ///
    /// - Parameters:
    ///   - wrappedValue: The initial value to store.
    ///   - label: A debug label for the underlying `DispatchQueue`. Default is `"ConcurrentAtomic.Queue"`.
    public init(wrappedValue: T, label: String = "ConcurrentAtomic.Queue") {
        self._value = wrappedValue
        self.queue = DispatchQueue(label: label, attributes: .concurrent)
    }

    /// Synchronously sets a new value in a thread-safe manner.
    ///
    /// This uses `.barrier` to ensure the new value is fully written before continuing.
    ///
    /// - Parameter newValue: The new value to be written.
    public func setSync(_ newValue: T) {
        queue.sync(flags: .barrier) {
            self._value = newValue
            self.mutationObserver?(newValue)
        }
    }

    /// Atomically mutates the wrapped value using a synchronous transform closure.
    ///
    /// The barrier ensures the read-modify-write operation does not overlap with other access.
    ///
    /// - Important: Do not access this `ConcurrentAtomic` instance from `transform`. The
    ///   transform executes while its synchronization barrier is held, so re-entering the
    ///   same instance would deadlock.
    ///
    /// - Parameter transform: A closure that receives `inout` access to the wrapped value.
    /// - Returns: The value returned by `transform`.
    @discardableResult
    public func mutate<Result>(_ transform: (inout T) throws -> Result) rethrows -> Result {
        try queue.sync(flags: .barrier) {
            defer { self.mutationObserver?(self._value) }
            return try transform(&self._value)
        }
    }

    /// Installs an observer that runs inside the mutation barrier.
    ///
    /// The observer must not re-enter this `ConcurrentAtomic` instance.
    func setMutationObserver(_ observer: ((T) -> Void)?) {
        queue.sync(flags: .barrier) {
            mutationObserver = observer
        }
    }
}

public extension ConcurrentAtomic where T: Equatable {
    /// Replaces the stored value only when it equals `expected`.
    ///
    /// - Returns: `true` when the value was replaced; otherwise `false`.
    @discardableResult
    func compareAndSet(expected: T, newValue: T) -> Bool {
        queue.sync(flags: .barrier) {
            guard _value == expected else { return false }
            _value = newValue
            mutationObserver?(newValue)
            return true
        }
    }
}
