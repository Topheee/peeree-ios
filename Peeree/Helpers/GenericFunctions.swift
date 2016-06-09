//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation

func archiveObjectInUserDefs<T: AnyObject>(object: T, forKey: String) {
	NSUserDefaults.standardUserDefaults().setObject(NSKeyedArchiver.archivedDataWithRootObject(object), forKey: forKey)
}

func unarchiveObjectFromUserDefs<T: AnyObject>(forKey: String) -> T? {
	guard let data = NSUserDefaults.standardUserDefaults().objectForKey(forKey) as? NSData else {
		return nil
	}
    return NSKeyedUnarchiver.unarchiveObjectWithData(data) as? T
}