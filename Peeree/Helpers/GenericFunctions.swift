//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

// MARK: - Functions

func archiveObjectInUserDefs<T: NSSecureCoding>(_ object: T, forKey: String) {
    UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
}

func unarchiveObjectFromUserDefs<T: NSSecureCoding>(_ forKey: String) -> T? {
    guard let data = UserDefaults.standard.object(forKey: forKey) as? Data else { return nil }
    
    return NSKeyedUnarchiver.unarchiveObject(with: data) as? T
}


//"Swift 2" - not working
///// Objective-C __bridge cast
//func bridge<T : AnyObject>(_ obj : T) -> UnsafeRawPointer {
//    return UnsafePointer(Unmanaged.passUnretained(obj).toOpaque())
//    // return unsafeAddressOf(obj) // ***
//}
//
///// Objective-C __bridge cast
//func bridge<T : AnyObject>(_ ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(OpaquePointer(ptr)).takeUnretainedValue()
//    // return unsafeBitCast(ptr, T.self) // ***
//}
//
///// Objective-C __bridge_retained equivalent. Casts the object pointer to a void pointer and retains the object.
//func bridgeRetained<T : AnyObject>(_ obj : T) -> UnsafeRawPointer {
//    return UnsafePointer(Unmanaged.passRetained(obj).toOpaque())
//}
//
///// Objective-C __bridge_transfer equivalent. Converts the void pointer back to an object pointer and consumes the retain.
//func bridgeTransfer<T : AnyObject>(_ ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(OpaquePointer(ptr)).takeRetainedValue()
//}

//Swift 1.2
/// Objective-C __bridge cast
func bridge<T : AnyObject>(obj : T) -> UnsafeRawPointer {
    return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

/// Objective-C __bridge cast
func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

/// Objective-C __bridge_retained equivalent. Casts the object pointer to a void pointer and retains the object.
func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
    return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
}

/// Objective-C __bridge_transfer equivalent. Converts the void pointer back to an object pointer and consumes the retain.
func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
}


// MARK: - Extensions

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
    
    init(squareEdgeLength: CGFloat) {
        self.init(x: 0.0, y: 0.0, width: squareEdgeLength, height: squareEdgeLength)
    }
}

extension CGSize {
    init(squareEdgeLength: CGFloat) {
        self.init(width: squareEdgeLength, height: squareEdgeLength)
    }
}

extension RawRepresentable where Self.RawValue == String {
    var localizedRawValue: String {
        return Bundle.main.localizedString(forKey: rawValue, value: nil, table: nil)
    }
}

extension NotificationCenter {
    class func addObserverOnMain(_ name: String?, usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(forName: name.map { NSNotification.Name(rawValue: $0) }, object: nil, queue: OperationQueue.main, using: block)
    }
}

// MARK: - Synchronized Collections

// we could implement CollectionType, SequenceType here, but nope
// we could use struct, but it does not work and as long as class is working out, nope
open class SynchronizedArray<T> {
    /* private */ var array: [T] = []
    /* private */ let accessQueue = DispatchQueue(label: "com.peeree.sync_arr_q", attributes: [])
    
    init() { }
    
    init(array: [T]) {
        self.array = array
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
open class SynchronizedDictionary<Key: Hashable, Value> {
    /* private */ var dictionary = [Key : Value]()
    /* private */ let accessQueue = DispatchQueue(label: "com.peeree.sync_dic_q", attributes: [])
    
    init() { }
    
    init(dictionary: [Key : Value]) {
        self.dictionary = dictionary
    }
    
    // would be more safe but does not work since value semantics
    //    /// runs the passed block synchronized and gives direct access to the dictionary
    //    open func access(_ query: (_ dict: [Key : Value]) -> Void) {
    //        accessQueue.sync {
    //
    //            query(dictionary)
    //        }
    //    }
    
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
//    open func contains(_ predicate: ((Key, Value)) throws -> Bool) rethrows -> Bool {
//        var ret = false
//        var throwError: Error?
//        accessQueue.sync {
//            do {
//                try ret = self.dictionary.contains(where: predicate)
//            } catch let error {
//                throwError = error
//            }
//        }
//        if let error = throwError {
//            throw error
//        }
//        return ret
//    }
    
    // non-throwing as rethrows as above does not work and simple throws would result in too much boilerplate in user code
    open func contains(_ predicate: ((Key, Value)) -> Bool) -> Bool {
        return accessQueue.sync {
            return self.dictionary.contains(where: predicate)
        }
    }
    
    open func removeValueForKey(_ key: Key) -> Value? {
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
    /* private */ var set = Set<T>()
    /* private */ let accessQueue = DispatchQueue(label: "com.peeree.sync_set_q", attributes: [])
    
    init() { }
    
    init(set: Set<T>) {
        self.set = set
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
