//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

// MARK: - Functions

func archiveObjectInUserDefs<T: NSSecureCoding>(object: T, forKey: String) {
	NSUserDefaults.standardUserDefaults().setObject(NSKeyedArchiver.archivedDataWithRootObject(object), forKey: forKey)
}

func unarchiveObjectFromUserDefs<T: NSSecureCoding>(forKey: String) -> T? {
	guard let data = NSUserDefaults.standardUserDefaults().objectForKey(forKey) as? NSData else {
		return nil
	}
    return NSKeyedUnarchiver.unarchiveObjectWithData(data) as? T
}

func getIdentity(fromResource resource: String, password : String?) -> (SecIdentityRef, SecTrustRef)? {
    // Load certificate file
    guard let path = NSBundle.mainBundle().pathForResource(resource, ofType : "p12") else { return nil }
    guard let p12KeyFileContent = NSData(contentsOfFile: path) else { return nil }
    
    // Setting options for the identity
    let options = [String(kSecImportExportPassphrase):password ?? ""]
    var citems: CFArray? = nil
    let resultPKCS12Import = withUnsafeMutablePointer(&citems) { citemsPtr in
        SecPKCS12Import(p12KeyFileContent, options, citemsPtr)
    }
    
    guard resultPKCS12Import == errSecSuccess else { return nil }
    
    // Recover the identity
    let items = citems! as NSArray
    let identityAndTrust = items.objectAtIndex(0) as! NSDictionary
    let identity = identityAndTrust[String(kSecImportItemIdentity)] as! SecIdentity
    let trust = identityAndTrust[String(kSecImportItemTrust)] as! SecTrust
    
    return (identity as SecIdentityRef, trust as SecTrustRef)
}

/// Objective-C __bridge cast
func bridge<T : AnyObject>(obj : T) -> UnsafePointer<Void> {
    return UnsafePointer(Unmanaged.passUnretained(obj).toOpaque())
    // return unsafeAddressOf(obj) // ***
}

/// Objective-C __bridge cast
func bridge<T : AnyObject>(ptr : UnsafePointer<Void>) -> T {
    return Unmanaged<T>.fromOpaque(COpaquePointer(ptr)).takeUnretainedValue()
    // return unsafeBitCast(ptr, T.self) // ***
}

/// Objective-C __bridge_retained equivalent. Casts the object pointer to a void pointer and retains the object.
func bridgeRetained<T : AnyObject>(obj : T) -> UnsafePointer<Void> {
    return UnsafePointer(Unmanaged.passRetained(obj).toOpaque())
}

/// Objective-C __bridge_transfer equivalent. Converts the void pointer back to an object pointer and consumes the retain.
func bridgeTransfer<T : AnyObject>(ptr : UnsafePointer<Void>) -> T {
    return Unmanaged<T>.fromOpaque(COpaquePointer(ptr)).takeRetainedValue()
}

// Swift 3
//func bridge<T : AnyObject>(obj : T) -> UnsafeRawPointer {
//    return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
//}
//
//func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
//}
//
//func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
//    return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
//}
//
//func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
//}

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
        return NSBundle.mainBundle().localizedStringForKey(rawValue, value: nil, table: nil)
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
    func croppedImage(cropRect: CGRect) -> UIImage {
        let scaledCropRect = CGRectMake(cropRect.origin.x * scale, cropRect.origin.y * scale, cropRect.size.width * scale, cropRect.size.height * scale)
        
        let imageRef = CGImageCreateWithImageInRect(self.CGImage, scaledCropRect)
        return UIImage(CGImage: imageRef!, scale: scale, orientation: imageOrientation)
    }
}

extension NSNotificationCenter {
    class func addObserverOnMain(name: String?, usingBlock block: (NSNotification) -> Void) -> NSObjectProtocol {
        return NSNotificationCenter.defaultCenter().addObserverForName(name, object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: block)
    }
}

extension UIViewController {
    func presentInFrontMostViewController(animated: Bool, completion: (() -> Void)?) {
        guard let rootVC = UIApplication.sharedApplication().keyWindow?.rootViewController else { return }
        
        var vc = rootVC
        while vc.presentedViewController != nil {
            vc = vc.presentedViewController!
        }
        vc.presentViewController(self, animated: animated, completion: completion)
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

    let reachabilityRef: SCNetworkReachabilityRef
    
    enum NetworkStatus: Int {
        case NotReachable, ReachableViaWiFi, ReachableViaWWAN
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
        guard let instance = Reachability() else { return .NotReachable }
        
        return instance.currentReachabilityStatus()
    }
    
    init?(hostName: String) {
        guard let tmp = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, hostName) else { return nil } //hostName.UTF8String
        reachabilityRef = tmp
    }
    
    init?(hostAddress: sockaddr) {
        var mutableAddress = hostAddress
        guard let tmp = (withUnsafePointer(&mutableAddress) { (unsafePointer) -> SCNetworkReachability? in
            return SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, unsafePointer)
        }) else { return nil }
        reachabilityRef = tmp
    }
    
    init?() {
        var zeroAddress = sockaddr_in()
        bzero(&zeroAddress, sizeof(sockaddr_in))
        zeroAddress.sin_len = UInt8(sizeof(sockaddr_in))
        zeroAddress.sin_family = UInt8(AF_INET)
        var mutableAddress = zeroAddress
        guard let tmp = (withUnsafePointer(&mutableAddress) { (unsafePointer) -> SCNetworkReachability? in
            return SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer(unsafePointer))
        }) else { return nil }
        reachabilityRef = tmp
    }

    func startNotifier() -> Bool {
        var returnValue = false
        var selfptr = bridge(self)
        var context = withUnsafeMutablePointer(&selfptr) { (unsafePointer) -> SCNetworkReachabilityContext in
            return SCNetworkReachabilityContext(version: 0, info: unsafePointer, retain: nil, release: nil, copyDescription: nil)
        }
        
        if (SCNetworkReachabilitySetCallback(reachabilityRef, ({(target: SCNetworkReachabilityRef, flags: SCNetworkReachabilityFlags, info: UnsafeMutablePointer<Void>) in
            assert(info != nil, "info was NULL in ReachabilityCallback")
            let noteObject: Reachability = bridge(info)
            
            // Post a notification to notify the client that the network reachability changed.
            NSNotificationCenter.defaultCenter().postNotificationName(Reachability.ReachabilityChangedNotification, object: noteObject)
        }), &context)) {
            if (SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)) {
                returnValue = true
            }
        }
        
        return returnValue
    }
        
        
    func stopNotifier() {
        SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)
    }
            
    deinit {
        stopNotifier()
//        CFRelease(reachabilityRef)
    }

    func networkStatusForFlags(flags: SCNetworkReachabilityFlags) -> NetworkStatus {
//        Reachability.PrintReachabilityFlags(flags, "networkStatusForFlags")
        if !flags.contains(SCNetworkReachabilityFlags.Reachable) {
            // The target host is not reachable.
            return .NotReachable
        }
        
        var returnValue = NetworkStatus.NotReachable
        
        if !flags.contains(SCNetworkReachabilityFlags.ConnectionRequired) {
            /*
             If the target host is reachable and no connection is required then we'll assume (for now) that you're on Wi-Fi...
             */
            returnValue = .ReachableViaWiFi
        }
        
        if flags.contains(SCNetworkReachabilityFlags.ConnectionOnDemand) || flags.contains(SCNetworkReachabilityFlags.ConnectionOnTraffic) {
            /*
             ... and the connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs...
             */
            
            if !flags.contains(SCNetworkReachabilityFlags.InterventionRequired) {
                /*
                 ... and no [user] intervention is needed...
                 */
                returnValue = .ReachableViaWiFi
            }
        }
        
        if flags.contains(SCNetworkReachabilityFlags.IsWWAN) {
            /*
             ... but WWAN connections are OK if the calling application is using the CFNetwork APIs.
             */
            returnValue = .ReachableViaWWAN
        }
        
        return returnValue
    }
        
        
    func connectionRequired() -> Bool {
        var flags: SCNetworkReachabilityFlags = []
        
        if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
            return flags.contains(SCNetworkReachabilityFlags.ConnectionRequired)
        }
        
        return false
    }
    
            
    func currentReachabilityStatus() -> NetworkStatus {
        var returnValue = NetworkStatus.NotReachable
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
public class SynchronizedArray<T> {
    /* private */ var array: [T] = []
    /* private */ let accessQueue = dispatch_queue_create("com.peeree.sync_arr_q", DISPATCH_QUEUE_SERIAL)
    
    init() { }
    
    init(array: [T]) {
        self.array = array
    }
    
    public func append(newElement: T) {
        dispatch_async(accessQueue) {
            self.array.append(newElement)
        }
    }
    
    public subscript(index: Int) -> T {
        set {
            dispatch_async(accessQueue) {
                self.array[index] = newValue
            }
        }
        get {
            var element: T!
            
            dispatch_sync(accessQueue) {
                element = self.array[index]
            }
            
            return element
        }
    }
}

// we could implement CollectionType, SequenceType here, but nope
// we could use struct, but it does not work and as long as class is working out, nope
public class SynchronizedDictionary<Key: Hashable, Value> {
    /* private */ var dictionary: [Key : Value] = [:]
    /* private */ let accessQueue = dispatch_queue_create("com.peeree.sync_dic_q", DISPATCH_QUEUE_SERIAL)
    
    init() { }
    
    init(dictionary: [Key : Value]) {
        self.dictionary = dictionary
    }
    
    public subscript(index: Key) -> Value? {
        set {
            dispatch_async(accessQueue) {
                self.dictionary[index] = newValue
            }
        }
        get {
            var element: Value?
            
            dispatch_sync(accessQueue) {
                element = self.dictionary[index]
            }
            
            return element
        }
    }
    
    // @warn_unused_result public @rethrows func contains(@noescape predicate: (Self.Generator.Element) throws -> Bool) rethrows -> Bool {
    @warn_unused_result public func contains(predicate: ((Key, Value)) throws -> Bool) throws -> Bool {
        var ret = false
        var throwError: ErrorType?
        dispatch_sync(accessQueue) {
            do {
                try ret = self.dictionary.contains(predicate)
            } catch let error {
                throwError = error
            }
        }
        if let error = throwError {
            throw error
        }
        return ret
    }
    
    public func removeValueForKey(key: Key) -> Value? {
        var ret: Value? = nil
        dispatch_sync(accessQueue) {
            ret = self.dictionary.removeValueForKey(key)
        }
        return ret
    }
    
    public func removeAll() {
        dispatch_async(accessQueue) { 
            self.dictionary.removeAll()
        }
    }
}

// we could implement CollectionType, SequenceType here, but nope
// we could use struct, but it does not work and as long as class is working out, nope
public class SynchronizedSet<T : Hashable> {
    /* private */ var set = Set<T>()
    /* private */ let accessQueue = dispatch_queue_create("com.peeree.sync_set_q", DISPATCH_QUEUE_SERIAL)
    
    init() { }
    
    init(set: Set<T>) {
        self.set = set
    }
    
    public func contains(member: T) -> Bool {
        var contains: Bool!
        
        dispatch_sync(accessQueue) {
            contains = self.set.contains(member)
        }
        
        return contains
    }
    
    public func insert(member: T) {
        dispatch_async(accessQueue) {
            self.set.insert(member)
        }
    }
    
    public func remove(member: T) {
        dispatch_async(accessQueue) {
            self.set.remove(member)
        }
    }
    
    public func removeAll() {
        dispatch_async(accessQueue) {
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