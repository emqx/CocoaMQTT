import Foundation

/// A thread-safe property wrapper that uses a concurrent dispatch queue for atomic operations.
///
/// This wrapper provides both synchronous and asynchronous access to a wrapped value in a
/// thread-safe manner using `DispatchQueue` with `.concurrent` attributes and `.barrier` writes.
///
/// - Important: Although this wrapper provides atomicity for access, it does not make the wrapped
///   value itself thread-safe if the type is not thread-safe. Avoid wrapping types that manage
///   internal shared state without their own synchronization.
///
/// - Example:
/// ```swift
/// @ConcurrentAtomic var counter: Int = 0
/// counter += 1
/// print(counter)
/// ```
@propertyWrapper
public class ConcurrentAtomic<T> {
    private var _value: T
    private let queue: DispatchQueue

    /// Provides synchronous thread-safe access to the wrapped value.
    ///
    /// - Note: Reads use `queue.sync` and can happen concurrently.
    /// - Warning: Writes are done asynchronously with `.barrier`, so a following read may
    ///   not reflect the new value immediately.
    public var wrappedValue: T {
        get {
            queue.sync { _value }
        }
        set {
            queue.async(flags: .barrier) {
                self._value = newValue
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
        }
    }

    /// Asynchronously mutates the wrapped value using a transform closure.
    ///
    /// The mutation is performed with `.barrier`, ensuring it does not overlap with other reads or writes.
    ///
    /// - Parameter transform: A closure that receives `inout` access to the wrapped value.
    public func mutate(_ transform: @escaping (inout T) -> Void) {
        queue.async(flags: .barrier) {
            transform(&self._value)
        }
    }
}
