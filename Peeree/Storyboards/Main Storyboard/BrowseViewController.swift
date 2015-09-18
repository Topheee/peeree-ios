//
//  BrowseViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class BrowseViewController: UITableViewController {
	
	var filter: BrowseFilterSettings?
	
	@IBAction func unwindToBrowseViewController(segue: UIStoryboardSegue) {
		
	}
	
	override func viewDidAppear(animated: Bool) {
		let userDefs = NSUserDefaults.standardUserDefaults()
		let data = userDefs.objectForKey(BrowseFilterSettings.kPrefKey) as? NSData
		if data == nil {
			filter = BrowseFilterSettings()
		} else {
			filter = NSKeyedUnarchiver.unarchiveObjectWithData(data!) as? BrowseFilterSettings
			if filter == nil {
				filter = BrowseFilterSettings()
			}
		}
	}
	
	override func viewDidDisappear(animated: Bool) {
		filter = nil
	}
}