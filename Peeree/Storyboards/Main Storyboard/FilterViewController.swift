//
//  FilterViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class FilterViewController: UIViewController {
	
	var backend: BrowseFilterSettings?
	
	@IBOutlet var ageMaxLabel: UILabel!
	@IBOutlet var ageMaxSlider: UISlider!
	
	@IBOutlet var ageMinLabel: UILabel!
	@IBOutlet var ageMinSlider: UISlider!
	
	private func updatePrefs() {
		let userDefs = NSUserDefaults.standardUserDefaults()
		backend!.ageMax = ageMaxSlider.value == ageMaxSlider.maximumValue ? 0 : ageMaxSlider.value
		backend!.ageMin = ageMinSlider.value
		let data = NSKeyedArchiver.archivedDataWithRootObject(backend!)
		userDefs.setObject(data, forKey: BrowseFilterSettings.kPrefKey)
	}
	
	private func updateAgeMinLabel() {
		let newValue = Int(ageMinSlider.value)
		ageMinLabel.text = "\(newValue)"
	}
	
	private func updateAgeMaxLabel() {
		let newValue = ageMaxSlider.value == ageMaxSlider.maximumValue ? "∞" : "\(Int(ageMaxSlider.value))"
		ageMaxLabel.text = newValue
	}
	
	@IBAction func changeAgeMaxEnd(sender: UISlider) {
		updatePrefs()
	}
	@IBAction func changeAgeMinEnd(sender: UISlider) {
		updatePrefs()
	}
	
	@IBAction func changeAgeMin(sender: UISlider) {
		if sender.value > ageMaxSlider.value {
			ageMaxSlider.value = sender.value
			updateAgeMaxLabel()
		}
		updateAgeMinLabel()
	}
	
	@IBAction func changeAgeMax(sender: UISlider) {
		if sender.value < ageMinSlider.value {
			ageMinSlider.value = sender.value
			updateAgeMinLabel()
		}
		updateAgeMaxLabel()
	}
	
	override func viewDidAppear(animated: Bool) {
		let userDefs = NSUserDefaults.standardUserDefaults()
		let data = userDefs.objectForKey(BrowseFilterSettings.kPrefKey) as? NSData
		if data == nil {
			backend = BrowseFilterSettings()
		} else {
			backend = NSKeyedUnarchiver.unarchiveObjectWithData(data!) as? BrowseFilterSettings
			if backend == nil {
				backend = BrowseFilterSettings()
			}
		}
		ageMaxSlider.value = backend!.ageMax
		updateAgeMaxLabel()
		ageMinSlider.value = backend!.ageMin
		updateAgeMinLabel()
	}
	
	override func viewDidDisappear(animated: Bool) {
		backend = nil
	}
}