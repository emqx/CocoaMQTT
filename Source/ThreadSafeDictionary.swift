//
// Copyright © 2022. All rights reserved.
//

import Foundation

/// A thread-safe dictionary
public class ThreadSafeDictionary<K: Hashable, V>: Collection {
    private var dictionary: [K: V]
    private let concurrentQueue: DispatchQueue

    public var startIndex: Dictionary<K, V>.Index {
        concurrentQueue.sync {
            return self.dictionary.startIndex
        }
    }

    public var endIndex: Dictionary<K, V>.Index {
        concurrentQueue.sync {
            return self.dictionary.endIndex
        }
    }

    public init(label: String, dict: [K: V] = [K: V]()) {
        self.dictionary = dict
        concurrentQueue = DispatchQueue(label: label, attributes: .concurrent)
    }

    public func index(after i: Dictionary<K, V>.Index) -> Dictionary<K, V>.Index {
        concurrentQueue.sync {
            self.dictionary.index(after: i)
        }
    }

    public subscript(key: K) -> V? {
        get {
            concurrentQueue.sync {
                self.dictionary[key]
            }
        }
        set(newValue) {
            concurrentQueue.async(flags: .barrier) {[weak self] in
                self?.dictionary[key] = newValue
            }
        }
    }

    public subscript(index: Dictionary<K, V>.Index) -> Dictionary<K, V>.Element {
        concurrentQueue.sync {
            self.dictionary[index]
        }
    }

    func setValue(_ value: V?, forKey key: K) {
        concurrentQueue.sync(flags: .barrier) {
            dictionary[key] = value
        }
    }

    @discardableResult
    public func removeValue(forKey key: K) -> V? {
        concurrentQueue.sync(flags: .barrier) {
            self.dictionary.removeValue(forKey: key)
        }
    }

    public func removeAll() {
        concurrentQueue.async(flags: .barrier) {[weak self] in
            self?.dictionary.removeAll()
        }
    }

    func removeAllSync() {
        concurrentQueue.sync(flags: .barrier) {
            dictionary.removeAll()
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
