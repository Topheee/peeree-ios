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
public class SynchronizedDictionary<S: Hashable, T> {
    /* private */ var dictionary: [S : T] = [:]
    /* private */ let accessQueue = dispatch_queue_create("com.peeree.sync_dic_q", DISPATCH_QUEUE_SERIAL)
    
    init() { }
    
    init(dictionary: [S : T]) {
        self.dictionary = dictionary
    }
    
    public subscript(index: S) -> T? {
        set {
            dispatch_async(accessQueue) {
                self.dictionary[index] = newValue
            }
        }
        get {
            var element: T?
            
            dispatch_sync(accessQueue) {
                element = self.dictionary[index]
            }
            
            return element
        }
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