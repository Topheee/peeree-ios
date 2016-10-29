//
//  FilterViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class FilterViewController: UITableViewController {
	
	@IBOutlet private weak var ageMaxLabel: UILabel!
	@IBOutlet private weak var ageMaxSlider: UISlider!
	
	@IBOutlet private weak var ageMinLabel: UILabel!
	@IBOutlet private weak var ageMinSlider: UISlider!
	
	@IBOutlet private weak var genderSeg: UISegmentedControl!
    
    // TODO implement age- and pictureSwitch
    @IBOutlet private weak var pictureSwitch: UISwitch!
    @IBOutlet private weak var ageSwitch: UISwitch!
    
    private let filterSettings = BrowseFilterSettings.shared
	
	@IBAction func changeFilter(_ sender: AnyObject) {
		updatePrefs()
	}
	
	@IBAction func changeAgeMin(_ sender: UISlider) {
		if sender.value > ageMaxSlider.value {
			ageMaxSlider.value = sender.value
			updateAgeMaxLabel()
		}
		updateAgeMinLabel()
	}
	
	@IBAction func changeAgeMax(_ sender: UISlider) {
		if sender.value < ageMinSlider.value {
			ageMinSlider.value = sender.value
			updateAgeMinLabel()
		}
		updateAgeMaxLabel()
	}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        ageMaxLabel.widthAnchor.constraint(equalTo: ageMinLabel.widthAnchor, multiplier: 1.0)
        ageMaxSlider.maximumValue = Float(PeerInfo.MaxAge + 1)
        ageMaxSlider.minimumValue = Float(PeerInfo.MinAge)
        ageMinSlider.maximumValue = Float(PeerInfo.MaxAge)
        ageMinSlider.minimumValue = Float(PeerInfo.MinAge)
    }
	
	override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        ageMaxSlider.value = filterSettings.ageMax == 0 ? ageMaxSlider.maximumValue : filterSettings.ageMax
		updateAgeMaxLabel()
		ageMinSlider.value = filterSettings.ageMin
		updateAgeMinLabel()
        genderSeg.selectedSegmentIndex = filterSettings.gender.rawValue
        ageSwitch.isOn = filterSettings.onlyWithAge
        pictureSwitch.isOn = filterSettings.onlyWithPicture
        // why? i don't know
        self.tableView.backgroundColor = theme.globalBackgroundColor
    }
    
    private func updatePrefs() {
        let filterSettings = BrowseFilterSettings.shared
        filterSettings.ageMax = ageMaxSlider.value == ageMaxSlider.maximumValue ? 0 : ageMaxSlider.value
        filterSettings.ageMin = ageMinSlider.value
        filterSettings.gender = BrowseFilterSettings.GenderType(rawValue: genderSeg.selectedSegmentIndex)!
        filterSettings.onlyWithAge = ageSwitch.isOn
        filterSettings.onlyWithPicture = pictureSwitch.isOn
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
