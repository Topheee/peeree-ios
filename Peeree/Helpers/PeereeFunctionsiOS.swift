//
//  PeereeFunctionsiOS.swift
//  Peeree
//
//  Created by Christopher Kobusch on 14.10.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import UIKit
import PeereeCore
import PeereeServer

/// Generates generic actions on peers, notably pin and unpin.
@MainActor
func trailingSwipeActionsConfigurationFor(peerID: PeerID) -> UISwipeActionsConfiguration {
	let idModel = PeereeIdentityViewModelController.viewModel(of: peerID)

	if idModel.pinState.isPinned {
		let unpinAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Unpin", comment: "The user wants to unpin a person")) { (_, _, completion) in
			AccountController.use({
				$0.unpin(id: idModel.id)
				DispatchQueue.main.async { completion(true) }
			}, { DispatchQueue.main.async { completion(false) } })
		}
		return UISwipeActionsConfiguration(actions: [unpinAction])
	} else {
		let pinAction = UIContextualAction(style: .normal, title: NSLocalizedString("Pin", comment: "The user wants to pin a person")) { (_, _, completion) in
			AccountController.use({ ac in
				ac.pin(idModel.id)
				DispatchQueue.main.async { completion(true) }
			}, { DispatchQueue.main.async { completion(false) } })
		}
		pinAction.backgroundColor = AppTheme.tintColor
		return UISwipeActionsConfiguration(actions: [pinAction])
	}
}
