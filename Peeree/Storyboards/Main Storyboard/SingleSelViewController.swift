//
//  SingleSelViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.08.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit

final class SingleSelViewController: UIViewController {
	@IBOutlet private var selectionPickerView: UIPickerView!
	
	var dataSource: SingleSelViewControllerDataSource? {
		didSet {
			guard selectionPickerView != nil else { return }
            
            selectionPickerView.dataSource = dataSource
            selectionPickerView.delegate = dataSource
		}
	}
	
	// MARK: - Navigation
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		super.prepareForSegue(segue, sender: sender)
		if let descriptionVC = segue.destinationViewController as? BasicDescriptionViewController {
			descriptionVC.dataSource = dataSource
		}
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
		selectionPickerView.dataSource = dataSource
		selectionPickerView.delegate = dataSource
	}
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        guard let selection = dataSource?.initialPickerSelection(selectionPickerView) else { return }
        
        selectionPickerView.selectRow(selection.row, inComponent: selection.inComponent, animated: false)
        selectionPickerView.userInteractionEnabled = dataSource?.selectionEditable(selectionPickerView) ?? false
    }
}

protocol SingleSelViewControllerDataSource: BasicDescriptionViewControllerDataSource, UIPickerViewDataSource, UIPickerViewDelegate {
    func initialPickerSelection(pickerView: UIPickerView) -> (row: Int, inComponent: Int)
    func selectionEditable(pickerView: UIPickerView) -> Bool
}
