//
//  CharacterTraitViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 17.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class CharacterTraitViewController: UITableViewController, SingleSelViewControllerDataSource {
	
	/* From wikipedia
	Wärme (z. B. Wohlfühlen in Gesellschaft)
	logisches Schlussfolgern
	emotionale Stabilität
	Dominanz
	Lebhaftigkeit
	Regelbewusstsein (z. B. Moral)
	soziale Kompetenz (z. B. Kontaktfreude)
	Empfindsamkeit
	Wachsamkeit (z. B. Misstrauen)
	Abgehobenheit (z. B. Realitätsnähe)
	Privatheit
	Besorgtheit
	Offenheit für Veränderungen
	Selbstgenügsamkeit
	Perfektionismus
	Anspannung
	*/
	// let characterTraits = ["warmness", "emotional stability", "dominance", "vitality", "rule awareness", "social competence", "sensitiveness", "vigilance", "escapism", "privateness", "solicitousness", "openness to change", "frugalilty", "perfectionism", "strain"]
	internal var characterTraits: Array<CharacterTrait>?
	var selectedTrait: NSIndexPath?
	
	static let cellID = "characterTraitCell"
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
			singleSelVC.dataSource = self
		}
	}
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		
		let cell = tableView.dequeueReusableCellWithIdentifier(CharacterTraitViewController.cellID)!
		let trait = characterTraits![indexPath.row]
		cell.textLabel!.text = trait.name
		cell.detailTextLabel!.text = CharacterTrait.ApplyTypeNames[trait.applies.rawValue]
		return cell
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let traits = characterTraits {
			return traits.count
		}
		return 0
	}
	
	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		selectedTrait = indexPath
	}
	
	func headingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		// TODO localization
		return "How about..."
	}
	
	func subHeadingOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		if let traits = characterTraits {
			return traits[selectedTrait!.row].name
		}
		return ""
	}
	
	func descriptionOfSingleSelViewController(singleSelViewController: SingleSelViewController) -> String? {
		if let traits = characterTraits {
			return traits[selectedTrait!.row].description
		}
		return ""
	}
	
	func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(pickerView: UIPickerView,
		numberOfRowsInComponent component: Int) -> Int {
			return CharacterTrait.ApplyTypeNames.count
	}
	
	func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return CharacterTrait.ApplyTypeNames[row]
	}
	
	func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		characterTraits![selectedTrait!.row].applies = CharacterTrait.ApplyType(rawValue: row)!
		self.tableView.reloadRowsAtIndexPaths([selectedTrait!], withRowAnimation: .None)
	}
}
