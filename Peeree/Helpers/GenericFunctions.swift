//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

// MARK: - Functions

func archiveObjectInUserDefs<T: NSSecureCoding>(_ object: T, forKey: String) {
	UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
}

func unarchiveObjectFromUserDefs<T: NSSecureCoding>(_ forKey: String) -> T? {
	guard let data = UserDefaults.standard.object(forKey: forKey) as? Data else { return nil }
    
    return NSKeyedUnarchiver.unarchiveObject(with: data) as? T
}

func getIdentity(fromResource resource: String, password : String?) -> (SecIdentity, SecTrust)? {
    // Load certificate file
    guard let path = Bundle.main.path(forResource: resource, ofType : "p12") else { return nil }
    guard let p12KeyFileContent = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    
    // Setting options for the identity
    let options = [String(kSecImportExportPassphrase):password ?? ""]
    var citems: CFArray? = nil
    let resultPKCS12Import = withUnsafeMutablePointer(to: &citems) { citemsPtr in
        SecPKCS12Import(p12KeyFileContent as CFData, options as CFDictionary, citemsPtr)
    }
    
    guard resultPKCS12Import == errSecSuccess else { return nil }
    
    // Recover the identity
    let items = citems! as NSArray
    let identityAndTrust = items.object(at: 0) as! NSDictionary
    let identity = identityAndTrust[String(kSecImportItemIdentity)] as! SecIdentity
    let trust = identityAndTrust[String(kSecImportItemTrust)] as! SecTrust
    
    return (identity as SecIdentity, trust as SecTrust)
}

//Swift 2
//func bridge<T : AnyObject>(_ obj : T) -> UnsafeRawPointer {
//    return UnsafePointer(Unmanaged.passUnretained(obj).toOpaque())
//    // return unsafeAddressOf(obj) // ***
//}
//
//func bridge<T : AnyObject>(_ ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(OpaquePointer(ptr)).takeUnretainedValue()
//    // return unsafeBitCast(ptr, T.self) // ***
//}
//
//func bridgeRetained<T : AnyObject>(_ obj : T) -> UnsafeRawPointer {
//    return UnsafePointer(Unmanaged.passRetained(obj).toOpaque())
//}
//
//func bridgeTransfer<T : AnyObject>(_ ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(OpaquePointer(ptr)).takeRetainedValue()
//}

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

//func getSecIdentitySummaryString(identity: SecIdentityRef) -> String? {
//    // Get the certificate from the identity.
//    var certificatePtr: SecCertificate? = nil
//    let status: OSStatus = withUnsafeMutablePointer(&certificatePtr) { ptr in
//        SecIdentityCopyCertificate(identity, ptr);  // Extracts the certificate from the identity.
//    }
//    
//    guard (status == errSecSuccess) else { return nil }
//    guard let returnedCertificate = certificatePtr else { return nil }
//    
//    return SecCertificateCopySubjectSummary(returnedCertificate) as? String // Gets summary information from the certificate.
//}
//
//func persistentRefForIdentity(identity: SecIdentityRef) -> CFData? {
//    var persistent_ref: CFTypeRef? = nil
//    let dict: [String:AnyObject] = [kSecReturnPersistentRef as String : kCFBooleanTrue, kSecValueRef as String : identity]
//    let status = SecItemAdd(dict, &persistent_ref);
//    
//    guard (status == errSecSuccess) else { return nil }
//    
//    return (persistent_ref as! CFDataRef)
//}

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

extension UIView {
    var marginFrame: CGRect {
        let margins = self.layoutMargins
        var ret = self.frame
        ret.origin.x += margins.left
        ret.origin.y += margins.top
        ret.size.height -= margins.top + margins.bottom
        ret.size.width -= margins.left + margins.right
        return ret
    }
}

extension UIImage {
    func croppedImage(_ cropRect: CGRect) -> UIImage {
        let scaledCropRect = CGRect(x: cropRect.origin.x * scale, y: cropRect.origin.y * scale, width: cropRect.size.width * scale, height: cropRect.size.height * scale)
        
        let imageRef = self.cgImage?.cropping(to: scaledCropRect)
        return UIImage(cgImage: imageRef!, scale: scale, orientation: imageOrientation)
    }
}

extension NotificationCenter {
    class func addObserverOnMain(_ name: String?, usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(forName: name.map { NSNotification.Name(rawValue: $0) }, object: nil, queue: OperationQueue.main, using: block)
    }
}

extension UIViewController {
    func presentInFrontMostViewController(_ animated: Bool, completion: (() -> Void)?) {
        guard let rootVC = UIApplication.shared.keyWindow?.rootViewController else { return }
        
        var vc = rootVC
        while vc.presentedViewController != nil {
            vc = vc.presentedViewController!
        }
        vc.present(self, animated: animated, completion: completion)
    }
}

//protocol NotificationPoster {
//    associatedtype NotificationType: RawRepresentable //where NotificationType.RawValue == String
//    
//    static let PostedNotifications: NotificationType
//    func test() where NotificationType.RawValue == String
//}

// MARK: - Network Reachability

/* Based on the Apple Reachability sample code. */
import SystemConfiguration

class Reachability {
    static let ReachabilityChangedNotification = "kNetworkReachabilityChangedNotification"

    let reachabilityRef: SCNetworkReachability
    
    enum NetworkStatus: Int {
        case notReachable, reachableViaWiFi, reachableViaWWAN
    }

//    static let ShouldPrintReachabilityFlags = true
//
//    static func PrintReachabilityFlags(flags: SCNetworkReachabilityFlags, comment: String) {
//        if ShouldPrintReachabilityFlags {
//            NSLog("Reachability Flag Status: %c%c %c%c%c%c%c%c%c %s\n",
//                   (flags & SCNetworkReachabilityFlags.IsWWAN.rawValue)		 ? "W" : "-",
//                   (flags & SCNetworkReachabilityFlags.Reachable)            ? "R" : "-",
//                   
//                   (flags & SCNetworkReachabilityFlags.TransientConnection)  ? "t" : "-",
//                   (flags & SCNetworkReachabilityFlags.ConnectionRequired)   ? "c" : "-",
//                   (flags & SCNetworkReachabilityFlags.ConnectionOnTraffic)  ? "C" : "-",
//                   (flags & SCNetworkReachabilityFlags.InterventionRequired) ? "i" : "-",
//                   (flags & SCNetworkReachabilityFlags.ConnectionOnDemand)   ? "D" : "-",
//                   (flags & SCNetworkReachabilityFlags.IsLocalAddress)       ? "l" : "-",
//                   (flags & SCNetworkReachabilityFlags.IsDirect)             ? "d" : "-",
//                   comment
//            );
//        }
//    }
    
    static func getNetworkStatus() -> NetworkStatus {
        guard let instance = Reachability() else { return .notReachable }
        
        return instance.currentReachabilityStatus()
    }
    
    init?(hostName: String) {
        guard let tmp = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, hostName) else { return nil } //hostName.UTF8String
        reachabilityRef = tmp
    }
    
    init?(hostAddress: sockaddr) {
        var mutableAddress = hostAddress
        guard let tmp = (withUnsafePointer(to: &mutableAddress) { (unsafePointer) -> SCNetworkReachability? in
            return SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, unsafePointer)
        }) else { return nil }
        reachabilityRef = tmp
    }
    
    init?() {
        var zeroAddress = sockaddr_in()
        bzero(&zeroAddress, MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = UInt8(AF_INET)
        var mutableAddress = zeroAddress
        guard let tmp = (withUnsafePointer(to: &mutableAddress) { (unsafePointer) -> SCNetworkReachability? in
            return unsafePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { (unsafeMutablePointer) in
                SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, unsafeMutablePointer)
            }
        }) else { return nil }
        
        reachabilityRef = tmp
    }

    func startNotifier() -> Bool {
        var returnValue = false
        var selfptr = bridge(obj: self)
        var context = withUnsafeMutablePointer(to: &selfptr) { (unsafePointer) -> SCNetworkReachabilityContext in
            return SCNetworkReachabilityContext(version: 0, info: unsafePointer, retain: nil, release: nil, copyDescription: nil)
        }
        
        if (SCNetworkReachabilitySetCallback(reachabilityRef, ({(target: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutableRawPointer?) in
            assert(info != nil, "info was NULL in ReachabilityCallback")
            let noteObject: Reachability = bridge(ptr: info!)
            
            // Post a notification to notify the client that the network reachability changed.
            NotificationCenter.default.post(name: Notification.Name(rawValue: Reachability.ReachabilityChangedNotification), object: noteObject)
        }), &context)) {
            if (SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)) {
                returnValue = true
            }
        }
        
        return returnValue
    }
        
        
    func stopNotifier() {
        SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
            
    deinit {
        stopNotifier()
//        CFRelease(reachabilityRef)
    }

    func networkStatusForFlags(_ flags: SCNetworkReachabilityFlags) -> NetworkStatus {
//        Reachability.PrintReachabilityFlags(flags, "networkStatusForFlags")
        if !flags.contains(SCNetworkReachabilityFlags.reachable) {
            // The target host is not reachable.
            return .notReachable
        }
        
        var returnValue = NetworkStatus.notReachable
        
        if !flags.contains(SCNetworkReachabilityFlags.connectionRequired) {
            /*
             If the target host is reachable and no connection is required then we'll assume (for now) that you're on Wi-Fi...
             */
            returnValue = .reachableViaWiFi
        }
        
        if flags.contains(SCNetworkReachabilityFlags.connectionOnDemand) || flags.contains(SCNetworkReachabilityFlags.connectionOnTraffic) {
            /*
             ... and the connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs...
             */
            
            if !flags.contains(SCNetworkReachabilityFlags.interventionRequired) {
                /*
                 ... and no [user] intervention is needed...
                 */
                returnValue = .reachableViaWiFi
            }
        }
        
        if flags.contains(SCNetworkReachabilityFlags.isWWAN) {
            /*
             ... but WWAN connections are OK if the calling application is using the CFNetwork APIs.
             */
            returnValue = .reachableViaWWAN
        }
        
        return returnValue
    }
        
        
    func connectionRequired() -> Bool {
        var flags: SCNetworkReachabilityFlags = []
        
        if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
            return flags.contains(SCNetworkReachabilityFlags.connectionRequired)
        }
        
        return false
    }
    
            
    func currentReachabilityStatus() -> NetworkStatus {
        var returnValue = NetworkStatus.notReachable
        var flags: SCNetworkReachabilityFlags = []
        
        if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
            returnValue = networkStatusForFlags(flags)
        }
        
        return returnValue
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
    /* private */ var dictionary: [Key : Value] = [:]
    /* private */ let accessQueue = DispatchQueue(label: "com.peeree.sync_dic_q", attributes: [])
    
    init() { }
    
    init(dictionary: [Key : Value]) {
        self.dictionary = dictionary
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
    open func contains(_ predicate: ((Key, Value)) throws -> Bool) throws -> Bool {
        var ret = false
        var throwError: Error?
        accessQueue.sync {
            do {
                try ret = self.dictionary.contains(where: predicate)
            } catch let error {
                throwError = error
            }
        }
        if let error = throwError {
            throw error
        }
        return ret
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

//import MultipeerConnectivity
//
//extension MCPeerID {
//    /// The maximum allowable length of MCPeerID.displayName is 63 bytes in UTF-8 encoding.
//    static let MaxDisplayNameUTF8Length = 63
//}
