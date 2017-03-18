//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

// MARK: - Functions

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
    func cropped(to cropRect: CGRect) -> UIImage? {
//        return autoreleasepool {
            let scaledCropRect = CGRect(x: cropRect.origin.x * scale, y: cropRect.origin.y * scale, width: cropRect.size.width * scale, height: cropRect.size.height * scale)
            
            guard let imageRef = self.cgImage?.cropping(to: scaledCropRect) else { return nil }
            return UIImage(cgImage: imageRef, scale: scale, orientation: imageOrientation)
//        }
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

extension UIAlertController {
    /// This is the preferred method to display an UIAlertController since it sets the tint color of the global theme.
    func present(_ completion: (() -> Void)?) {
        presentInFrontMostViewController(true, completion: completion)
        self.view.tintColor = AppDelegate.shared.theme.globalTintColor
    }
}

extension UIView {
    /**
     *	Animates views like they are flown in from the bottom of the screen.
     *	@param views    the views to animate
     */
    func flyInSubviews(_ views: [UIView], duration: TimeInterval, delay: TimeInterval, damping: CGFloat, velocity: CGFloat) {
        var positions = [CGRect]()
        for value in views {
            positions.append(value.frame)
            value.frame.origin.y = self.frame.height
            value.alpha = 0.0
        }
        
        UIView.animate(withDuration: duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: velocity, options: UIViewAnimationOptions(rawValue: 0), animations: { () -> Void in
            for (index, view) in views.enumerated() {
                view.frame = positions[index]
                view.alpha = 1.0
            }
        }, completion: nil)
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
