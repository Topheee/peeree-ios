//
//  SingleSelViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class SingleSelViewController: UIViewController {
	@IBOutlet private weak var selectionPickerView: UIPickerView!
	
	var dataSource: SingleSelViewControllerDataSource? {
		didSet {
			guard selectionPickerView != nil else { return }
			
			selectionPickerView.dataSource = dataSource
			selectionPickerView.delegate = dataSource
		}
	}
	
	// MARK: - Navigation
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		if let descriptionVC = segue.destination as? BasicDescriptionViewController {
			descriptionVC.dataSource = dataSource
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		selectionPickerView.dataSource = dataSource
		selectionPickerView.delegate = dataSource
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		guard let selection = dataSource?.initialPickerSelection(for: selectionPickerView) else { return }
		
		selectionPickerView.selectRow(selection.row, inComponent: selection.inComponent, animated: false)
		selectionPickerView.isUserInteractionEnabled = dataSource?.selectionEditable(in: selectionPickerView) ?? false
	}
}

protocol SingleSelViewControllerDataSource: BasicDescriptionViewControllerDataSource, UIPickerViewDataSource, UIPickerViewDelegate {
	func initialPickerSelection(for pickerView: UIPickerView) -> (row: Int, inComponent: Int)
	func selectionEditable(in pickerView: UIPickerView) -> Bool
}
