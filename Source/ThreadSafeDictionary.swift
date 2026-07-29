//
// Copyright © 2022. All rights reserved.
//

import Foundation

/// A thread-safe dictionary.
///
/// Iteration uses a stable snapshot so concurrent mutations cannot invalidate an
/// iterator. Use `snapshot()` when an operation needs one consistent dictionary.
///
/// - Important: Index-based `Collection` operations are retained for source
///   compatibility, but an index can be invalidated by a mutation between calls.
///   Use `snapshot()` for multi-step indexed access.
public final class ThreadSafeDictionary<K: Hashable, V>: Collection {
    public typealias Element = Dictionary<K, V>.Element
    public typealias Iterator = Dictionary<K, V>.Iterator

    private var dictionary: [K: V]
    private let concurrentQueue: DispatchQueue

    public var startIndex: Dictionary<K, V>.Index {
        concurrentQueue.sync { dictionary.startIndex }
    }

    public var endIndex: Dictionary<K, V>.Index {
        concurrentQueue.sync { dictionary.endIndex }
    }

    public var count: Int {
        concurrentQueue.sync { dictionary.count }
    }

    public var isEmpty: Bool {
        concurrentQueue.sync { dictionary.isEmpty }
    }

    public var first: Element? {
        snapshot().first
    }

    public init(label: String, dict: [K: V] = [K: V]()) {
        self.dictionary = dict
        concurrentQueue = DispatchQueue(label: label, attributes: .concurrent)
    }

    /// `for-in`, `map`, and other sequence operations iterate over one snapshot.
    public func makeIterator() -> Iterator {
        snapshot().makeIterator()
    }

    public func index(after index: Dictionary<K, V>.Index) -> Dictionary<K, V>.Index {
        concurrentQueue.sync {
            dictionary.index(after: index)
        }
    }

    public subscript(key: K) -> V? {
        get {
            concurrentQueue.sync {
                self.dictionary[key]
            }
        }
        set(newValue) {
            concurrentQueue.sync(flags: .barrier) {
                dictionary[key] = newValue
            }
        }
    }

    public subscript(index: Dictionary<K, V>.Index) -> Element {
        concurrentQueue.sync {
            dictionary[index]
        }
    }

    @discardableResult
    public func removeValue(forKey key: K) -> V? {
        concurrentQueue.sync(flags: .barrier) {
            self.dictionary.removeValue(forKey: key)
        }
    }

    public func removeAll() {
        concurrentQueue.sync(flags: .barrier) {
            dictionary.removeAll()
        }
    }

    func removeAllValues() -> [K: V] {
        concurrentQueue.sync(flags: .barrier) {
            let removed = dictionary
            dictionary.removeAll()
            return removed
        }
    }

    func removeValues(where shouldRemove: (K, V) -> Bool) {
        concurrentQueue.sync(flags: .barrier) {
            let keys = dictionary.compactMap { key, value in
                shouldRemove(key, value) ? key : nil
            }
            for key in keys {
                dictionary.removeValue(forKey: key)
            }
        }
    }

    public func snapshot() -> [K: V] {
        concurrentQueue.sync {
            dictionary
        }
    }

    public func replace(with newDictionary: [K: V]) {
        concurrentQueue.sync(flags: .barrier) {
            dictionary = newDictionary
        }
    }
}
