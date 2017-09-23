//
//  SynchronizedCollections.swift
//  Peeree
//  All classes are declared final to speed up compilation
//
//  Created by Christopher Kobusch on 27.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

// we could implement CollectionType, SequenceType here, but nope
// we could use struct, but it does not work and as long as class is working out, nope
final public class SynchronizedArray<T> {
    private var array: [T]
    private let accessQueue: DispatchQueue
    
    var count: Int {
        return accessQueue.sync {
            return array.count
        }
    }
    
    init(queueLabel: String, array: [T] = [], qos: DispatchQoS = .default) {
        self.array = array
        self.accessQueue = DispatchQueue(label: queueLabel, qos: qos, attributes: [])
    }
    
    /// runs the passed block synchronized and gives direct access to the array
    open func accessAsync(query: @escaping (inout [T]) -> Void) {
        accessQueue.async {
            query(&self.array)
        }
    }
    
    open func accessSync<S>(execute work: @escaping (inout [T]) throws -> S) rethrows -> S {
        return try accessQueue.sync {
            return try work(&self.array)
        }
    }
    
    open func append(_ newElement: T) {
        accessQueue.async {
            self.array.append(newElement)
        }
    }
    
    open subscript(index: Int) -> T {
        set {
            accessQueue.async {
                self.array[index] = newValue
            }
        }
        get {
            var element: T!
            
            accessQueue.sync {
                element = self.array[index]
            }
            
            return element
        }
    }
}

// we could implement CollectionType, SequenceType here, but nope
// we could use struct, but it does not work and as long as class is working out, nope
final public class SynchronizedDictionary<Key: Hashable, Value> {
    private var dictionary: [Key : Value]
    private let accessQueue: DispatchQueue
    
    var count: Int {
        return accessQueue.sync {
            return dictionary.count
        }
    }
    
    init(queueLabel: String, dictionary: [Key : Value] = [:], qos: DispatchQoS = .default) {
        self.dictionary = dictionary
        self.accessQueue = DispatchQueue(label: queueLabel, qos: qos, attributes: [])
    }
    
    /// runs the passed block synchronized and gives direct access to the dictionary
    open func accessAsync(query: @escaping (inout [Key : Value]) -> Void) {
        accessQueue.async {
            query(&self.dictionary)
        }
    }
    
    open func accessSync<S>(execute work: @escaping (inout [Key : Value]) throws -> S) rethrows -> S {
        return try accessQueue.sync {
            return try work(&self.dictionary)
        }
    }
    
    open subscript(index: Key) -> Value? {
        set {
            accessQueue.async {
                self.dictionary[index] = newValue
            }
        }
        get {
            var element: Value?
            
            accessQueue.sync {
                element = self.dictionary[index]
            }
            
            return element
        }
    }
    
    // @warn_unused_result public @rethrows func contains(@noescape predicate: (Self.Generator.Element) throws -> Bool) rethrows -> Bool {
    open func contains( predicate: ((Key, Value)) throws -> Bool) rethrows -> Bool {
        return try accessQueue.sync {
            return try self.dictionary.contains(where: predicate)
        }
    }
    
    open func removeValue(forKey key: Key) -> Value? {
        var ret: Value? = nil
        accessQueue.sync {
            ret = self.dictionary.removeValue(forKey: key)
        }
        return ret
    }
    
    open func removeAll() {
        accessQueue.async {
            self.dictionary.removeAll()
        }
    }
}

// we could implement CollectionType, SequenceType here, but nope
// we could use struct, but it does not work and as long as class is working out, nope
open class SynchronizedSet<T : Hashable> {
    private var set: Set<T>
    private let accessQueue: DispatchQueue
    
    var count: Int {
        return accessQueue.sync {
            return set.count
        }
    }
    
    init(queueLabel: String, set: Set<T> = Set<T>(), qos: DispatchQoS = .default) {
        self.set = set
        self.accessQueue = DispatchQueue(label: queueLabel, qos: qos, attributes: [])
    }
    
    /// runs the passed block synchronized and gives direct access to the set
    open func accessAsync(query: @escaping (inout Set<T>) -> Void) {
        accessQueue.async {
            query(&self.set)
        }
    }
    
    open func accessSync<S>(execute work: @escaping (inout Set<T>) throws -> S) rethrows -> S {
        return try accessQueue.sync {
            return try work(&self.set)
        }
    }
    
    open func contains(_ member: T) -> Bool {
        var contains: Bool!
        
        accessQueue.sync {
            contains = self.set.contains(member)
        }
        
        return contains
    }
    
    open func insert(_ member: T) {
        accessQueue.async {
            self.set.insert(member)
        }
    }
    
    open func remove(_ member: T) {
        accessQueue.async {
            self.set.remove(member)
        }
    }
    
    open func removeAll() {
        accessQueue.async {
            self.set.removeAll()
        }
    }
}
