//
//  CharacterTraitViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 17.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class CharacterTraitViewController: UITableViewController, SingleSelViewControllerDataSource {
	
	var characterTraits: [CharacterTrait]?
	var selectedTrait: NSIndexPath?
	
	static let cellID = "characterTraitCell"
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
		if let singleSelVC = segue.destinationViewController as? SingleSelViewController {
			singleSelVC.dataSource = self
		}
	}
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        guard characterTraits != nil && characterTraits! == UserPeerInfo.instance.peer.characterTraits else { return }
        
        // trigger NSUserDefaults archiving
        UserPeerInfo.instance.peer.characterTraits = characterTraits!
    }
    
    // - MARK: UITableView Data Source
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier(CharacterTraitViewController.cellID)!
		let trait = characterTraits![indexPath.row]
		cell.textLabel!.text = trait.name
		cell.detailTextLabel!.text = trait.applies.localizedRawValue
		return cell
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return characterTraits?.count ?? 0
	}
	
	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		selectedTrait = indexPath
	}
    
    // - MARK: SingleSelViewController Data Source
    
    func selectionEditable(pickerView: UIPickerView) -> Bool {
        return characterTraits != nil && characterTraits! == UserPeerInfo.instance.peer.characterTraits
    }
    
    func initialPickerSelection(pickerView: UIPickerView) -> (row: Int, inComponent: Int) {
        return (CharacterTrait.ApplyType.values.indexOf(characterTraits![selectedTrait!.row].applies)!, 0)
    }
	
	func headingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
		return NSLocalizedString("How about...", comment: "Heading of character trait view")
	}
	
	func subHeadingOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
        return characterTraits?[selectedTrait!.row].name ?? ""
	}
	
	func descriptionOfBasicDescriptionViewController(basicDescriptionViewController: BasicDescriptionViewController) -> String? {
        return characterTraits?[selectedTrait!.row].traitDescription ?? ""
	}
	
	func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return CharacterTrait.ApplyType.values.count
	}
	
	func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return CharacterTrait.ApplyType.values[row].localizedRawValue
	}
	
	func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		characterTraits![selectedTrait!.row].applies = CharacterTrait.ApplyType.values[row]
		self.tableView.reloadRowsAtIndexPaths([selectedTrait!], withRowAnimation: .None)
	}
}
