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
	var selectedTrait: IndexPath?
    var userTraits = false
	
	static let cellID = "characterTraitCell"
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
		if let singleSelVC = segue.destination as? SingleSelViewController {
			singleSelVC.dataSource = self
		}
	}
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard userTraits else { return }
        guard let traits = characterTraits else { return }
        
        // trigger NSUserDefaults archiving
        UserPeerManager.instance.peer.characterTraits = traits
    }
    
    // MARK: UITableViewDataSource
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: CharacterTraitViewController.cellID, for: indexPath)
		let characterTrait = characterTraits![indexPath.row]
		cell.textLabel!.text = characterTrait.kind.localizedRawValue
		cell.detailTextLabel!.text = characterTrait.applies.localizedRawValue
		return cell
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return characterTraits?.count ?? 0
	}
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		selectedTrait = indexPath
	}
    
    // MARK: SingleSelViewControllerDataSource
    
    func selectionEditable(in pickerView: UIPickerView) -> Bool {
        return characterTraits != nil && userTraits
    }
    
    func initialPickerSelection(for pickerView: UIPickerView) -> (row: Int, inComponent: Int) {
        return (CharacterTrait.ApplyType.allCases.firstIndex(of: characterTraits![selectedTrait!.row].applies)!, 0)
    }
	
	func headingOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String? {
		return characterTraits?[selectedTrait!.row].kind.localizedRawValue
	}
	
	func subHeadingOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String? {
        return nil
	}
	
	func descriptionOfBasicDescriptionViewController(_ basicDescriptionViewController: BasicDescriptionViewController) -> String? {
        return characterTraits?[selectedTrait!.row].kind.kindDescription ?? ""
	}
	
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return CharacterTrait.ApplyType.allCases.count
	}
	
	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return CharacterTrait.ApplyType.allCases[row].localizedRawValue
	}
	
	func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		characterTraits![selectedTrait!.row].applies = CharacterTrait.ApplyType.allCases[row]
		self.tableView.reloadRows(at: [selectedTrait!], with: .none)
	}
}
