//
//  FilterViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultiSelectSegmentedControl
import PeereeCore
import PeereeDiscovery

final class FilterViewController: UITableViewController {
	// MARK: - Interface Builder

	// MARK: Outlets

	@IBOutlet private weak var genderSegments: MultiSelectSegmentedControl!
	@IBOutlet private weak var ageMinTextLabel: UILabel!
	@IBOutlet private weak var ageMaxTextLabel: UILabel!
	@IBOutlet private weak var ageMaxLabel: UILabel!
	@IBOutlet private weak var ageMaxSlider: UISlider!
	@IBOutlet private weak var ageMinLabel: UILabel!
	@IBOutlet private weak var ageMinSlider: UISlider!
	@IBOutlet private weak var pictureSwitch: UISwitch!
	@IBOutlet private weak var ageSwitch: UISwitch!
	@IBOutlet private weak var displayOverrideSwitch: UISwitch!

	// MARK: Actions

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

	// MARK: - UIViewController Overrides
	
	override func viewDidLoad() {
		super.viewDidLoad()
		DispatchQueue.main.async {
			self.ageMaxLabel.widthAnchor.constraint(equalTo: self.ageMinLabel.widthAnchor).isActive = true
			self.ageMaxTextLabel.widthAnchor.constraint(equalTo: self.ageMinTextLabel.widthAnchor).isActive = true
		}
		ageMaxSlider.maximumValue = Float(PeerInfo.MaxAge + 1)
		ageMaxSlider.minimumValue = Float(PeerInfo.MinAge)
		ageMinSlider.maximumValue = Float(PeerInfo.MaxAge)
		ageMinSlider.minimumValue = Float(PeerInfo.MinAge)

		// the localization comes from PeerDescription file
		genderSegments.items = [NSLocalizedString("female", comment: ""), NSLocalizedString("male", comment: ""), NSLocalizedString("queer", comment: "")]
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		(try? BrowseFilter.getFilter()).map { filterSettings = $0 }

		ageMaxSlider.value = filterSettings.ageMax == 0 ? ageMaxSlider.maximumValue : filterSettings.ageMax
		updateAgeMaxLabel()
		ageMinSlider.value = filterSettings.ageMin
		updateAgeMinLabel()

		var genders = IndexSet()
		if filterSettings.gender.contains(.females) { genders.insert(Self.FemalesIndex) }
		if filterSettings.gender.contains(.males) { genders.insert(Self.MalesIndex) }
		if filterSettings.gender.contains(.queers) { genders.insert(Self.QueersIndex) }
		genderSegments.selectedSegmentIndexes = genders

		ageSwitch.isOn = filterSettings.onlyWithAge
		pictureSwitch.isOn = filterSettings.onlyWithPicture
		displayOverrideSwitch.isOn = filterSettings.displayFilteredPeople
	}

	// MARK: - Private

	// MARK: Static Constants

	/// Segment index of `genderSegments`.
	private static let FemalesIndex = 0, MalesIndex = 1, QueersIndex = 2

	// MARK: Variables

	/// Currently applied filter.
	private var filterSettings = BrowseFilter()

	// MARK: Methods

	/// Read preference values from UI and persist them.
	private func updatePrefs() {
		filterSettings.ageMax = ageMaxSlider.value == ageMaxSlider.maximumValue ? 0 : ageMaxSlider.value
		filterSettings.ageMin = ageMinSlider.value
		let selectedGenders = genderSegments.selectedSegmentIndexes
		var genderFilter: BrowseFilter.GenderFilter = []
		if selectedGenders.contains(Self.FemalesIndex) { genderFilter.insert(.females) }
		if selectedGenders.contains(Self.MalesIndex) { genderFilter.insert(.males) }
		if selectedGenders.contains(Self.QueersIndex) { genderFilter.insert(.queers) }
		filterSettings.gender = genderFilter
		filterSettings.onlyWithAge = ageSwitch.isOn
		filterSettings.onlyWithPicture = pictureSwitch.isOn
		filterSettings.displayFilteredPeople = displayOverrideSwitch.isOn

		do {
			try filterSettings.writeToDefaults()
		} catch {
			InAppNotificationController.display(error: error, localizedTitle: NSLocalizedString("Saving Filter Failed", comment: "Error dialog title."))
		}
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
