//
//  InAppNotificationController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 30.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import UIKit
import NotificationBannerSwift

/// Display custom notifications only in-app, sometimes called 'toasts'.
final class InAppNotificationController {
	/// Provides colors for the in-app notification banners.
	private class BannerColorer: BannerColorsProtocol {
		/// Provides colors for the in-app notification banner styles.
		func color(for style: BannerStyle) -> UIColor {
			if #available(iOS 13.0, *) {
				return UIColor.systemGroupedBackground
			} else {
				return UIColor.lightGray
			}
		}
	}

	/// Proxy to provide an Objective-C Selector.
	private class TapHandler: NSObject {
		/// Action to be executed on tap gesture.
		private let notificationAction: (() -> Void)

		/// Executes `notificationAction`.
		@objc func handleTap(sender: UITapGestureRecognizer) {
			if sender.state == .ended {
				notificationAction()
			}
		}

		/// Constructs a proxy around `notificationAction`.
		init(notificationAction: @escaping () -> Void) {
			self.notificationAction = notificationAction
		}
	}

	/// Show a globally visible in-app notification, similar to a 'toast'.
	static func display(title: String, message: String, isNegative: Bool = true, _ notificationAction: (() -> Void)? = nil) {
		if isNegative {
			wlog("Displaying in-app warning '\(title)': \(message)")
		}

		DispatchQueue.main.async {
			let banner = NotificationBanner(title: title, subtitle: message, style: isNegative ? .danger : .info, colors: BannerColorer())
			banner.titleLabel?.textColor = UIColor.systemRed
			if #available(iOS 13.0, *) {
				banner.subtitleLabel?.textColor = UIColor.label
			} else {
				banner.subtitleLabel?.textColor = UIColor.darkText
			}

			banner.duration = Self.NotificationDuration

			if let action = notificationAction {
				banner.addGestureRecognizer(UITapGestureRecognizer(target: TapHandler(notificationAction: action), action: #selector(TapHandler.handleTap(sender:))))
			}
			banner.show()
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

		display(title: localizedTitle, message: errorMessage, isNegative: true, notificationAction)
	}

	/// Shows a 'toast' explaining `serverChatError`; use this function for Errors from `ServerChatController`.
	static func display(serverChatError error: ServerChatError, localizedTitle: String) {
		if (error as NSError).code == NSURLErrorCannotConnectToHost && (error as NSError).domain == NSURLErrorDomain {
			display(title: localizedTitle, message: serverDownMessage)
		} else {
			switch error {
			case .identityMissing:
				display(title: localizedTitle, message: NSLocalizedString("Chatting requires a Peeree Identity.", comment: "Error message"))
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
			case .noAccount:
				display(title: localizedTitle, message: "No server chat account yet.")
			}
		}
	}

	/// Shows a 'toast' explaining a generic error.
	static func display(error: Error, localizedTitle: String) {
		display(title: localizedTitle, message: error.localizedDescription)
	}

	private static let NotificationDuration: TimeInterval = 5.76

	private static var serverDownMessage: String { return NSLocalizedString("Sorry, we are currently busy trying to plug in the WiFi cable. Please try again in a couple of minutes.", comment: "Error message when a connection cannot be made.") }
}
