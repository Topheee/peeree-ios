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
				errorMessage = "\(String(format: httpErrorMessage, code ?? -1)): \(theError.localizedDescription)"
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

	static func display(error: Error, localizedTitle: String) {
		display(title: localizedTitle, message: error.localizedDescription)
	}

	private static let NotificationDuration = 5.76
}
