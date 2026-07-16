//
// Copyright © 2022. All rights reserved.
//

import Foundation

/// A thread-safe dictionary. Iterate over `snapshot()` rather than live indices.
public final class ThreadSafeDictionary<K: Hashable, V> {
    private var dictionary: [K: V]
    private let concurrentQueue: DispatchQueue

    public init(label: String, dict: [K: V] = [K: V]()) {
        self.dictionary = dict
        concurrentQueue = DispatchQueue(label: label, attributes: .concurrent)
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
