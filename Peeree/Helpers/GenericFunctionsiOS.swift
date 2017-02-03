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

//protocol NotificationPoster {
//    associatedtype NotificationType: RawRepresentable //where NotificationType.RawValue == String
//    
//    static let PostedNotifications: NotificationType
//    func test() where NotificationType.RawValue == String
//}
