//
//  InAppNotificationController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import UIKit
import Toast

/// Display custom notifications only in-app, sometimes called 'toasts'.
final class InAppNotificationController {
	static func display(title: String, message: String, isNegative: Bool = true) {
		if isNegative {
			wlog("Displaying in-app warning '\(title)': \(message)")
		}

		DispatchQueue.main.async {
			guard let view = UIViewController.frontMostViewController()?.view else { return }

			var style = ToastStyle()
			if isNegative {
				style.titleColor = .red
			}

			view.makeToast(message, duration: InAppNotificationController.NotificationDuration, position: .top, title: title, image: nil, style: style, completion: nil)
		}
	}

	/// Shows a 'toast' explaining `openapiError`; use this function for Errors from `AccountController`.
	static func display(openapiError error: Error, localizedTitle: String, furtherDescription: String? = nil) {
		var notificationAction: (() -> Void)? = nil
		var errorMessage: String
		if let errorResponse = error as? ErrorResponse {
			let httpErrorMessage = NSLocalizedString("HTTP error %d.", comment: "Error message for HTTP status codes")
			switch errorResponse {
			case .parseError(_):
				errorMessage = NSLocalizedString("Malformed server response.", comment: "Message of network error")
			case .httpError(let code, _):
				errorMessage = String(format: httpErrorMessage, code)
				if code == 403 {
					errorMessage = errorMessage + NSLocalizedString(" Something went wrong with the authentication. Please try again in a minute.", comment: "Appendix to message")
				}
			case .sessionTaskError(let code, _, let theError):
				if (theError as NSError).code == NSURLErrorCannotConnectToHost {
					errorMessage = serverDownMessage
				} else {
					errorMessage = "\(String(format: httpErrorMessage, code ?? -1)): \(theError.localizedDescription)"
				}
			case .offline:
				errorMessage = NSLocalizedString("The network appears to be offline. You may need to grant Peeree access to it.", comment: "Message of network offline error")
				notificationAction = { UIApplication.shared.openURL(URL(string: UIApplication.openSettingsURLString)!) }
			}
		} else {
			errorMessage = error.localizedDescription
		}

		if furtherDescription != nil {
			errorMessage += "\n\(furtherDescription!)"
		}

		display(title: localizedTitle, message: errorMessage)
	}

	static func display(serverChatError error: ServerChatError, localizedTitle: String) {
		if (error as NSError).code == NSURLErrorCannotConnectToHost && (error as NSError).domain == NSURLErrorDomain {
			display(title: localizedTitle, message: serverDownMessage)
		} else {
			switch error {
			case .identityMissing:
				display(title: localizedTitle, message: NSLocalizedString("Server Chat requires a Peeree Identity.", comment: "Error message."))
			case .parsing(let parsingError):
				display(title: localizedTitle, message: parsingError)
			case .sdk(let error):
				display(title: localizedTitle, message: error.localizedDescription)
			case .fatal(let error):
				display(title: localizedTitle, message: error.localizedDescription)
			case .cannotChat(let peerID, let reason):
				let name = PeerViewModelController.viewModels[peerID]?.info.nickname ?? peerID.uuidString

				let format: String
				switch reason {
				case .noProfile:
					format = NSLocalizedString("%@ cannot chat online.", comment: "Error message when creating server chat room")
				case .noEncryption:
					format = NSLocalizedString("%@ cannot chat securely.", comment: "Low-level server chat error")
				case .notJoined:
					format = NSLocalizedString("%@ is not yet available to chat. Please try again later.", comment: "Both parties need to be in the chat room before messages can be sent.")
				case .unmatched:
					format = NSLocalizedString("%@ removed their pin.", comment: "Message for the user that he cannot chat anymore with a person.")
				}

				display(title: localizedTitle, message: String(format: format, name))
			}
		}
	}

	static func display(error: Error, localizedTitle: String) {
		display(title: localizedTitle, message: error.localizedDescription)
	}

	private static let NotificationDuration = 5.76

	private static var serverDownMessage: String { return NSLocalizedString("Sorry, we are currently busy trying to plug in the WiFi cable. Please try again in a couple of minutes.", comment: "Error message when a connection cannot be made.") }
}