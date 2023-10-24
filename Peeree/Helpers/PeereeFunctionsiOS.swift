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

	let title: String
	if idModel.pinState.isPinned {
		title = NSLocalizedString("Unpin", comment: "The user wants to unpin a person")

		let unpinAction = UIContextualAction(style: .destructive, title: title) { (_, _, completion) in
			AccountControllerFactory.shared.use({
				$0.unpin(id: idModel.id)
				DispatchQueue.main.async { completion(true) }
			}, { error in
				error.map { InAppNotificationController.display(error: $0, localizedTitle: title) }

				DispatchQueue.main.async { completion(false) }
			})
		}

		return UISwipeActionsConfiguration(actions: [unpinAction])
	} else {
		title = NSLocalizedString("Pin", comment: "The user wants to pin a person")

		let pinAction = UIContextualAction(style: .normal, title: title) { (_, _, completion) in
			AccountControllerFactory.shared.use({ ac in
				ac.pin(idModel.id)
				DispatchQueue.main.async { completion(true) }
			}, { error in
				error.map { InAppNotificationController.display(error: $0, localizedTitle: title) }

				DispatchQueue.main.async { completion(false) }
			})
		}

		pinAction.backgroundColor = AppTheme.tintColor

		return UISwipeActionsConfiguration(actions: [pinAction])
	}
}
