//
//  Integrator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.10.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

// Platform Dependencies
import UIKit

// Internal Dependencies
import PeereeServer
import PeereeServerChat

/// Calls `AccountController.createAccount` and displays its error.
func createIdentity(displayError: Bool = true) {
	AccountControllerFactory.shared.createAccount { result in
		switch result {
		case .success(let ac):
			setup(ac: ac, errorTitle: NSLocalizedString("Chat Server Account Creation Failed", comment: "Error message title"))

		case .failure(let error):
			guard displayError else { return }
			InAppNotificationController.display(openapiError: error, localizedTitle: NSLocalizedString("Account Creation Failed", comment: "Title of alert"), furtherDescription: NSLocalizedString("Please go to the bottom of your profile to try again.", comment: "Further description of account creation failure error"))
		}
	}
}

/// Sets up an `AccountController` after it was created; must be called on its `dQueue`.
func setup(ac: AccountController, errorTitle: String) {
	ac.delegate = Mediator.shared

	ac.refreshBlockedContent { error in
		let title = NSLocalizedString("Objectionable Content Refresh Failed", comment: "Title of alert when the remote API call to refresh objectionable portrait hashes failed.")
		InAppNotificationController.display(openapiError: error, localizedTitle: title)
	}

	ServerChatFactory.initialize(ourPeerID: ac.peerID, dataSource: Mediator.shared) { factory in
		factory.delegate = Mediator.shared
		factory.conversationDelegate = ServerChatViewModelController.shared

		factory.setup { result in
			switch result {
			case .success(_):
				DispatchQueue.main.async {
					NotificationManager.shared.setupNotifications()
				}
			case .failure(let failure):
				InAppNotificationController.display(serverChatError: failure, localizedTitle: errorTitle)
			}
		}
	}
}
