//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

// TODO use this in the swagger completion blocks as argument, to eliminate the case that both error and data are nil
enum OperationResult<T> {
    case good(T), bad(Error)
}

// MARK: - Functions

func archiveObjectInUserDefs<T: NSSecureCoding>(_ object: T, forKey: String) {
    UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
}

func unarchiveObjectFromUserDefs<T: NSSecureCoding>(_ forKey: String) -> T? {
    guard let data = UserDefaults.standard.object(forKey: forKey) as? Data else { return nil }
    
    return NSKeyedUnarchiver.unarchiveObject(with: data) as? T
}

/// create a plist and add it to copied resources. In the file, make the root entry to an array and add string values to it
func arrayFromBundle(name: String) -> [String]? {
    guard let url = Bundle.main.url(forResource: name, withExtension:"plist") else { return nil }
    return NSArray(contentsOf: url) as? [String]
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
    
    public func addObserver(usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
    }
}

extension NotificationCenter {
    class func addObserverOnMain(_ name: String?, usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(forName: name.map { NSNotification.Name(rawValue: $0) }, object: nil, queue: OperationQueue.main, using: block)
    }
}

extension String {
    /// stores the encoding along the serialization of the string to let decoders know which it is
    func data(prefixedEncoding encoding: String.Encoding) -> Data? {
        // NOTE: all the sizes where MemoryLayout<String.Encoding.RawValue>.size, but that is depending on architecture (64 or 32 bits), so we choose 32 bits (4 bytes) fixed
        // PERFORMANCE: let size = MemoryLayout<UInt32>.size + nickname.lengthOfBytes(using: encoding)
        var encodingRawValue = UInt32(encoding.rawValue)
        let encodingPointer = withUnsafeMutablePointer(to: &encodingRawValue, { (pointer) -> UnsafeMutablePointer<UInt32> in
            return pointer
        })
        
        var data = Data(bytesNoCopy: encodingPointer, count: MemoryLayout<UInt32>.size, deallocator: Data.Deallocator.none)
        
        guard let payload = self.data(using: encoding) else { return nil }
        data.append(payload)
        return data
    }
    
    /// takes data encoded with <code>data(prefixedEncoding:)</code> and constructs a string with the serialized encoding
    init?(dataPrefixedEncoding data: Data) {
        // NOTE: all the sizes where MemoryLayout<String.Encoding.RawValue>.size, but that is depending on architecture (64 or 32 bits), so we choose 32 bits (4 bytes) fixed
        // PEFORMANCE
        let encodingData = data.subdata(in: 0..<MemoryLayout<UInt32>.size)
//        var encodingRawValue: String.Encoding.RawValue = String.Encoding.utf8.rawValue
//        withUnsafeMutableBytes(of: &encodingRawValue) { pointer in
//            pointer.copyBytes(from: encodingData)
//        }
        
        var encodingRawValue: UInt32 = UInt32(String.Encoding.utf8.rawValue)
        withUnsafeMutableBytes(of: &encodingRawValue) { pointer in
            pointer.copyBytes(from: encodingData)
        }
        
        let encoding = String.Encoding(rawValue: String.Encoding.RawValue(encodingRawValue))
        let suffix = data.suffix(from: MemoryLayout<UInt32>.size)
        self.init(data: data.subdata(in: suffix.startIndex..<suffix.endIndex), encoding: encoding)
    }
    
    /// returns first count characters
    func left(_ count: String.IndexDistance) -> String {
        let endIndex = self.index(self.startIndex, offsetBy: count)
        return self.substring(to: endIndex)
    }
    
    /// returns last count characters
    func right(_ count: String.IndexDistance) -> String {
        let endIndex = self.index(self.endIndex, offsetBy: -count)
        return self.substring(from: endIndex)
    }
}

extension Data {
    func hexString() -> String {
        var hex = ""
        for byte in self {
            hex += String(format: "%02x", byte)
        }
        
        return hex
    }
}

extension HTTPURLResponse {
    var isFailure: Bool { return statusCode > 399 && statusCode < 600 }
}

extension Bool {
    /// Create an instance initialized to false, if <code>value</code> is zero, and true otherwise.
    init<T: Integer>(_ value: T) {
        self.init(value != 0)
    }
}

extension SignedInteger {
    /// Create an instance initialized to zero, if <code>value</code> is false, and 1 otherwise.
    init(_ value: Bool) {
        self.init(value ? 1 : 0)
    }
}

extension UnsignedInteger {
    /// Create an instance initialized to zero, if <code>value</code> is false, and 1 otherwise.
    init(_ value: Bool) {
        self.init(value ? 1 : 0)
    }
}
