//
//  FilterViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class FilterViewController: UIViewController {
	
	var backend: BrowseFilterSettings!
	
	@IBOutlet private var ageMaxLabel: UILabel!
	@IBOutlet private var ageMaxSlider: UISlider!
	
	@IBOutlet private var ageMinLabel: UILabel!
	@IBOutlet private var ageMinSlider: UISlider!
	
	@IBOutlet private var genderSeg: UISegmentedControl!
	
	
	private func updatePrefs() {
		backend.ageMax = ageMaxSlider.value == ageMaxSlider.maximumValue ? 0 : ageMaxSlider.value
		backend.ageMin = ageMinSlider.value
		backend.gender = BrowseFilterSettings.GenderType(rawValue: genderSeg.selectedSegmentIndex)!
		backend.writeToDefaults()
	}
	
	private func updateAgeMinLabel() {
		let newValue = Int(ageMinSlider.value)
		ageMinLabel.text = "\(newValue)"
	}
	
	private func updateAgeMaxLabel() {
		let newValue = ageMaxSlider.value == ageMaxSlider.maximumValue ? "∞" : "\(Int(ageMaxSlider.value))"
		ageMaxLabel.text = newValue
	}
	
	@IBAction func changeFilter(sender: AnyObject) {
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
	
	override func viewWillAppear(animated: Bool) {
		backend = BrowseFilterSettings.sharedSettings
		ageMaxSlider.value = backend.ageMax
		updateAgeMaxLabel()
		ageMinSlider.value = backend.ageMin
		updateAgeMinLabel()
	}
}