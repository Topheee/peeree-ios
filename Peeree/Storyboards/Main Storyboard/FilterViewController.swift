//
//  FilterViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class FilterViewController: UIViewController {
	
	@IBOutlet private var ageMaxLabel: UILabel!
	@IBOutlet private var ageMaxSlider: UISlider!
	
	@IBOutlet private var ageMinLabel: UILabel!
	@IBOutlet private var ageMinSlider: UISlider!
	
	@IBOutlet private var genderSeg: UISegmentedControl!
    
    private let filterSettings = BrowseFilterSettings.sharedSettings
	
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
        super.viewWillAppear(animated)
        ageMaxSlider.maximumValue = Float(SerializablePeerInfo.MaxAge + 1)
        ageMaxSlider.minimumValue = Float(SerializablePeerInfo.MinAge)
        ageMinSlider.maximumValue = Float(SerializablePeerInfo.MaxAge)
        ageMinSlider.minimumValue = Float(SerializablePeerInfo.MinAge)
        
        ageMaxSlider.value = filterSettings.ageMax == 0 ? ageMaxSlider.maximumValue : filterSettings.ageMax
		updateAgeMaxLabel()
		ageMinSlider.value = filterSettings.ageMin
		updateAgeMinLabel()
        genderSeg.selectedSegmentIndex = filterSettings.gender.rawValue
    }
    
    private func updatePrefs() {
        let filterSettings = BrowseFilterSettings.sharedSettings
        filterSettings.ageMax = ageMaxSlider.value == ageMaxSlider.maximumValue ? 0 : ageMaxSlider.value
        filterSettings.ageMin = ageMinSlider.value
        filterSettings.gender = BrowseFilterSettings.GenderType(rawValue: genderSeg.selectedSegmentIndex)!
        filterSettings.writeToDefaults()
    }
    
    private func updateAgeMinLabel() {
        let newValue = Int(ageMinSlider.value)
        ageMinLabel.text = "\(newValue)"
    }
    
    private func updateAgeMaxLabel() {
        let newValue = ageMaxSlider.value == ageMaxSlider.maximumValue ? "∞" : "\(Int(ageMaxSlider.value))"
        ageMaxLabel.text = newValue
    }
}