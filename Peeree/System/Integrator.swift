//
//  Integrator.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.10.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

// Platform Dependencies
import Foundation

// Internal Dependencies
import PeereeCore
import PeereeSocial
import PeereeIdP
import PeereeServerChat
import PeereeDiscovery

private var serverDownMessage: String { return NSLocalizedString("Sorry, we are currently busy trying to plug in the WiFi cable. Please try again in a couple of minutes.", comment: "Error message when a connection cannot be made.") }

/// Shows a 'toast' explaining `openapiError`; use this function for Errors from `AccountController`.
func socialModuleErrorMessage(from error: Error) -> String {
	var errorMessage: String
	if (error as NSError).code == NSURLErrorCannotConnectToHost && (error as NSError).domain == NSURLErrorDomain {
		errorMessage = serverDownMessage
	} else {
		errorMessage = error.localizedDescription
	}

	return errorMessage
}
/// Shows a 'toast' explaining `openapiError`; use this function for Errors from `AccountController`.
@MainActor
func serverChatModuleErrorMessage(from error: ServerChatError, on discoveryViewState: DiscoveryViewState) -> String {
	switch error {
	case .identityMissing:
		return NSLocalizedString("Chatting requires a Peeree Identity.", comment: "Error message")
	case .parsing(let parsingError):
		return parsingError
	case .sdk(let sdkError):
		if (sdkError as NSError).code == NSURLErrorCannotConnectToHost && (sdkError as NSError).domain == NSURLErrorDomain {
			return serverDownMessage
		} else {
			return sdkError.localizedDescription
		}
	case .fatal(let error):
		return error.localizedDescription
	case .cannotChat(let peerID, let reason):
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

		let name = discoveryViewState.people[peerID]?.info.nickname ?? peerID.uuidString
		return String(format: format, name)
	case .noAccount:
		return NSLocalizedString(
			"No chat account yet.",
			comment: "A chat function was used but the account is not available.")
	}
}

/// Based on `result`, either presents an error from ServerChat module to the user, or invokes `onSuccess`.
func act<T>(on result: Result<T, ServerChatError>, dvs: DiscoveryViewState, nvs: InAppNotificationStackViewState, localizedErrorTitle: String, onSuccess: (T) -> Void) {
	switch result {
	case .success(let s):
		onSuccess(s)
	case .failure(let failure):
		Task { @MainActor in
			let message = serverChatModuleErrorMessage(from: failure, on: dvs)
			nvs.display(InAppNotification(localizedTitle: localizedErrorTitle, localizedMessage: message, severity: .error, furtherDescription: nil))
		}
	}
}

extension PeereeDiscovery.BrowseFilter {
	/// Applies this filter and returns whether it fits.
	func check(info: PeerInfo, pinState: PinState) -> Bool {
		// always keep pinned or matched peers in filter
		guard pinState == .unpinned || pinState == .unpinning else { return true }

		let matchingGender = (gender.contains(.females) && info.gender == .female) ||
			(gender.contains(.males) && info.gender == .male) ||
			(gender.contains(.queers) && info.gender == .queer)

		var matchingAge: Bool
		if let peerAge = info.age {
			matchingAge = ageMin <= Float(peerAge) && (ageMax == 0.0 || ageMax >= Float(peerAge))
		} else {
			matchingAge = true
		}

		let hasRequiredProperties = (!onlyWithPicture || info.hasPicture) && (!onlyWithAge || info.age != nil)

		return matchingAge && matchingGender && hasRequiredProperties
	}
}
