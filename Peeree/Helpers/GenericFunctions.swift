//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import UIKit

func archiveObjectInUserDefs<T: NSSecureCoding>(object: T, forKey: String) {
	NSUserDefaults.standardUserDefaults().setObject(NSKeyedArchiver.archivedDataWithRootObject(object), forKey: forKey)
}

func unarchiveObjectFromUserDefs<T: NSSecureCoding>(forKey: String) -> T? {
	guard let data = NSUserDefaults.standardUserDefaults().objectForKey(forKey) as? NSData else {
		return nil
	}
    return NSKeyedUnarchiver.unarchiveObjectWithData(data) as? T
}

extension RawRepresentable where Self.RawValue == String {
    var localizedRawValue: String {
        return NSBundle.mainBundle().localizedStringForKey(rawValue, value: nil, table: nil)
    }
}

func CGRectMakeSquare(edgeLength: CGFloat) -> CGRect {
    return CGRectMake(0.0, 0.0, edgeLength, edgeLength)
}

func CGSizeMakeSquare(edgeLength: CGFloat) -> CGSize {
    return CGSizeMake(edgeLength, edgeLength)
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

//import MultipeerConnectivity
//
//extension MCPeerID {
//    /// The maximum allowable length of MCPeerID.displayName is 63 bytes in UTF-8 encoding.
//    static let MaxDisplayNameUTF8Length = 63
//}