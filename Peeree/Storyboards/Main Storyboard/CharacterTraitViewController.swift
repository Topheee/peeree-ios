//
//  CharacterTraitViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 17.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

class CharacterTraitViewController: UITableViewController, UITableViewDataSource  {
	
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
	let characterTraits = ["warmness", "emotional stability", "dominance", "vitality", "rule awareness", "social competence", "sensitiveness", "vigilance", "escapism", "privateness", "solicitousness", "openness to change", "frugalilty", "perfectionism", "strain"]
	
	static let characterTraitCellId = "characterTraitCell"
	
	
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		
		let cell = tableView.dequeueReusableCellWithIdentifier(CharacterTraitViewController.characterTraitCellId) as! UITableViewCell
		cell.textLabel!.text = characterTraits[indexPath.row]
		cell.detailTextLabel!.text = "No comment"
		/*
		let traitLabel = cell.viewWithTag(1) as! UILabel
		let traitValueSlider = cell.viewWithTag(2) as! UISlider
		let valueLabel = cell.viewWithTag(3) as! UILabel
		traitLabel.text = characterTraits[indexPath.row]
		traitValueSlider.value = 50.0
		valueLabel.text = "50%"
		*/
		return cell
	}
	
	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return characterTraits.count
	}
	
	// TODO SingleSelVC with heading 'Description', subheading '<character trait>', selection heading 'Applies to me' and selection options of 'no comment' and so on.
}
