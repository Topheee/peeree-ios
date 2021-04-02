//
//  NotificationManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.03.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
	private enum NotificationCategory: String {
		case peerAppeared, pinMatch, message, none
	}
	private enum NotificationActions: String {
		case peerAppearedPin, pinMatchMessage, messageReply
	}
	private static let PeerIDKey = "PeerIDKey"

	func initialize() {

		_ = PeeringController.Notifications.connectionChangedState.addObserver { notification in
			if #available(iOS 10.0, *) {
				UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
					// Enable or disable features based on authorization.
					guard error == nil else {
						NSLog("ERROR: Error requesting user notification authorization: \(error!.localizedDescription)")
						return
					}
				}
			} else {
				let pinMatchMessageAction = UIMutableUserNotificationAction()
				pinMatchMessageAction.identifier = NotificationActions.pinMatchMessage.rawValue
				pinMatchMessageAction.title = NSLocalizedString("Send Message", comment: "Notification action title.")
				let messageReplyAction = UIMutableUserNotificationAction()
				messageReplyAction.identifier = NotificationActions.messageReply.rawValue
				messageReplyAction.title = NSLocalizedString("Reply", comment: "Notification action title.")
				messageReplyAction.behavior = .textInput
				messageReplyAction.parameters = [UIUserNotificationTextInputActionButtonTitleKey : NSLocalizedString("Send", comment: "Text notification button title.")]
				let peerAppearedPinAction = UIMutableUserNotificationAction()
				peerAppearedPinAction.identifier = NotificationActions.peerAppearedPin.rawValue
				peerAppearedPinAction.title = NSLocalizedString("Pin", comment: "Notification action title.")
				let pinMatchCategory = UIMutableUserNotificationCategory()
				let messageCategory = UIMutableUserNotificationCategory()
				let peerAppearedCategory = UIMutableUserNotificationCategory()
				pinMatchCategory.identifier = NotificationCategory.pinMatch.rawValue
				messageCategory.identifier = NotificationCategory.message.rawValue
				peerAppearedCategory.identifier = NotificationCategory.peerAppeared.rawValue
				pinMatchCategory.setActions([pinMatchMessageAction], for: .default)
				pinMatchCategory.setActions([pinMatchMessageAction], for: .minimal)

				UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: [pinMatchCategory, messageCategory, peerAppearedCategory]))
			}
			// TODO remove. Only for debug purposes
//			let note = UILocalNotification()
//			note.alertTitle = "Peeree went \(PeeringController.shared.peering ? "online" : "offline"). \(notification.userInfo?["ReasonKey"] ?? "")"
//			UIApplication.shared.presentLocalNotificationNow(note)
		}

		_ = PeeringController.Notifications.peerAppeared.addPeerObserver { peerID, notification  in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool
			self.peerAppeared(peerID, again: again ?? false)
		}

		_ = PeeringController.Notifications.peerDisappeared.addPeerObserver { peerID, _  in
			self.peerDisappeared(peerID)
		}

		_ = AccountController.Notifications.pinMatch.addPeerObserver { peerID, _  in
			PeeringController.shared.manager(for: peerID).peerInfo.map { self.pinMatchOccured($0) }
		}

		_ = PeerManager.Notifications.messageReceived.addPeerObserver { peerID, _  in
			self.messageReceived(from: peerID)
		}

		if #available(iOS 10.0, *) {
			let notificationCenter = UNUserNotificationCenter.current()
			notificationCenter.delegate = self
			// for strings-gen
			// NSLocalizedString("Send Message", comment: "Notification action title.")
			// NSLocalizedString("Reply", comment: "Notification action title.")
			// NSLocalizedString("Send", comment: "Text notification button title.")
			// NSLocalizedString("Message", comment: "Text Notification action placeholder.")
			// NSLocalizedString("Pin", comment: "Notification action title.")
			let pinMatchMessageAction = UNNotificationAction(identifier: NotificationActions.pinMatchMessage.rawValue, title: NSString.localizedUserNotificationString(forKey: "Send Message", arguments: nil))
			let messageReplyAction = UNTextInputNotificationAction(identifier: NotificationActions.messageReply.rawValue, title: NSString.localizedUserNotificationString(forKey: "Reply", arguments: nil), options: [], textInputButtonTitle: NSString.localizedUserNotificationString(forKey: "Send", arguments: nil), textInputPlaceholder: NSString.localizedUserNotificationString(forKey: "Message", arguments: nil))
			let peerAppearedPinAction = UNNotificationAction(identifier: NotificationActions.peerAppearedPin.rawValue, title: NSString.localizedUserNotificationString(forKey: "Pin", arguments: nil))
//			if #available(iOS 12.0, *) {
//				let pinMatchCategory = UNNotificationCategory(identifier: NotificationCategory.pinMatch.rawValue, actions: [pinMatchMessageAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "", categorySummaryFormat: NSString.localizedUserNotificationString(forKey: "%u pin matches.", arguments: nil), options: [])
//				let messageCategory = UNNotificationCategory(identifier: NotificationCategory.message.rawValue, actions: [messageReplyAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "", categorySummaryFormat: NSString.localizedUserNotificationString(forKey: "%u messages.", arguments: nil), options: [])
//				let peerAppearedCategory = UNNotificationCategory(identifier: NotificationCategory.peerAppeared.rawValue, actions: [peerAppearedPinAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "", categorySummaryFormat: NSString.localizedUserNotificationString(forKey: "%u new people.", arguments: nil), options: [])
//				notificationCenter.setNotificationCategories([pinMatchCategory, messageCategory, peerAppearedCategory])
//			} else {
				let pinMatchCategory = UNNotificationCategory(identifier: NotificationCategory.pinMatch.rawValue, actions: [pinMatchMessageAction], intentIdentifiers: [])
				let messageCategory = UNNotificationCategory(identifier: NotificationCategory.message.rawValue, actions: [messageReplyAction], intentIdentifiers: [])
				let peerAppearedCategory = UNNotificationCategory(identifier: NotificationCategory.peerAppeared.rawValue, actions: [peerAppearedPinAction], intentIdentifiers: [])
			notificationCenter.setNotificationCategories([pinMatchCategory, messageCategory, peerAppearedCategory])
//			}
		}
	}
	
	func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
		guard application.applicationState == .inactive else { return }
		guard let peerIDData = notification.userInfo?[NotificationManager.PeerIDKey] as? Data else { return }
		guard let peerID = NSKeyedUnarchiver.unarchiveObject(with: peerIDData) as? PeerID else { return }
		
		AppDelegate.shared.show(peerID: peerID)
	}

	// MARK: UNUserNotificationCenterDelegate

	@available(iOS 10.0, *)
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		defer { completionHandler() }

		let userInfo = response.notification.request.content.userInfo
		guard let peerIDData = userInfo[NotificationManager.PeerIDKey] as? Data,
			  let peerID = NSKeyedUnarchiver.unarchiveObject(with: peerIDData) as? PeerID else {
			NSLog("ERROR: cannot find peerID in notification content.")
			return
		}
		guard let action = NotificationActions(rawValue: response.actionIdentifier) else {
			switch response.actionIdentifier {
			case UNNotificationDefaultActionIdentifier:
				AppDelegate.shared.show(peerID: peerID)
			case UNNotificationDismissActionIdentifier:
				return
			default:
				NSLog("ERROR: unknown notification action \(response.actionIdentifier).")
				return
			}
			return
		}

		let peerManager = PeeringController.shared.manager(for: peerID)
		switch action {
		case .pinMatchMessage, .messageReply:
			guard let textResponse = response as? UNTextInputNotificationResponse,
				  textResponse.userText != "" else { return }
			peerManager.send(message: textResponse.userText) { _error in
				if let error = _error { NSLog("ERROR: failed to send message from notification: \(error.localizedDescription)") }
			}
		case .peerAppearedPin:
			peerManager.peerInfo.map { AccountController.shared.pin($0) }
		}

		// unschedule all notifications of this category
		center.getDeliveredNotifications { (notifications) in
			var identifiers = [String]()
			for notification in notifications {
				if notification.request.content.categoryIdentifier == response.notification.request.content.categoryIdentifier {
					identifiers.append(notification.request.identifier)
				}
			}
			center.removeDeliveredNotifications(withIdentifiers: identifiers)
		}
	}

	@available(iOS 10.0, *)
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		if #available(iOS 14.0, *) {
			completionHandler(UNNotificationPresentationOptions.banner)
		} else {
			completionHandler(UNNotificationPresentationOptions.alert)
		}
	}

	// MARK: Private Methods

	/// shows an in-app or system (local) notification related to a peer
	private func displayPeerRelatedNotification(title: String, body: String, peerID: PeerID, category: NotificationCategory, displayInApp: Bool) {
		if #available(iOS 10, *) {
			guard !AppDelegate.shared.isActive || displayInApp else { return }
			let center = UNUserNotificationCenter.current()
			let content = UNMutableNotificationContent()
			content.title = title
			content.body = body.replacingOccurrences(of: "%", with: "%%")
			content.sound = UNNotificationSound.default
			content.userInfo = [NotificationManager.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peerID)]
			content.categoryIdentifier = category.rawValue
			content.threadIdentifier = peerID.uuidString
			center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false))) { (_error) in
				if let error = _error {
					NSLog("ERROR: Scheduling local notification failed: \(error.localizedDescription)")
				}
			}
		} else {
			if AppDelegate.shared.isActive && displayInApp {
				InAppNotificationViewController.presentGlobally(title: title, message: body, isNegative: false) { AppDelegate.shared.show(peerID: peerID) }
			} else {
				let note = UILocalNotification()
				note.alertTitle = title
				note.alertBody = body
				note.userInfo = [NotificationManager.PeerIDKey : NSKeyedArchiver.archivedData(withRootObject: peerID)]
				note.category = category.rawValue
				UIApplication.shared.presentLocalNotificationNow(note)
			}
		}
	}

	private func messageReceived(from peerID: PeerID) {
		let manager = PeeringController.shared.manager(for: peerID)
		guard let peer = manager.peerInfo, let message = manager.transcripts.last?.message else { return }
		let title: String
		if #available(iOS 10.0, *) {
			// The localizedUserNotificationString(forKey:arguments:) method delays the loading of the localized string until the notification is delivered. Thus, if the user changes language settings before a notification is delivered, the alert text is updated to the user’s current language instead of the language that was set when the notification was scheduled.
			title = NSString.localizedUserNotificationString(forKey: "Message from %@.", arguments: [peer.nickname])
		} else {
			let titleFormat = NSLocalizedString("Message from %@.", comment: "Notification alert body when a message is received.")
			title = String(format: titleFormat, peer.nickname)
		}
		let peerNotVisible = ((AppDelegate.shared.window?.rootViewController as? UINavigationController)?.visibleViewController as? PersonDetailViewController)?.peerManager.peerID != peerID
		displayPeerRelatedNotification(title: title, body: message, peerID: peerID, category: .message, displayInApp: peerNotVisible)
	}

	private func peerAppeared(_ peerID: PeerID, again: Bool) {
		guard !again, let peer = PeeringController.shared.manager(for: peerID).peerInfo,
			BrowseFilterSettings.shared.check(peer: peer) else { return }
		if AppDelegate.shared.isActive {
			_ = PeeringController.shared.manager(for: peerID).loadPicture()
		}
		let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
		let notBrowsing = ((AppDelegate.shared.window?.rootViewController as? UINavigationController)?.visibleViewController as? BrowseViewController) == nil
		displayPeerRelatedNotification(title: String(format: alertBodyFormat, peer.nickname), body: "", peerID: peerID, category: peer.pinMatched ? .none : .peerAppeared, displayInApp: notBrowsing)
	}

	private func peerDisappeared(_ peerID: PeerID) {
		// ignored
	}

	private func pinMatchOccured(_ peer: PeerInfo) {
		if AppDelegate.shared.isActive {
			let pinMatchVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: PinMatchViewController.StoryboardID) as! PinMatchViewController
			pinMatchVC.displayedPeer = peer
			DispatchQueue.main.async {
				if let presentingVC = AppDelegate.shared.window?.rootViewController?.presentedViewController {
					// if Me screen is currently presented
					presentingVC.present(pinMatchVC, animated: true, completion: nil)
				} else {
					AppDelegate.shared.window?.rootViewController?.present(pinMatchVC, animated: true, completion: nil)
				}
			}
		} else {
			let title = NSLocalizedString("New Pin Match!", comment: "Notification alert title when a pin match occured.")
			let alertBodyFormat = NSLocalizedString("Pin Match with %@!", comment: "Notification alert body when a pin match occured.")
			let alertBody = String(format: alertBodyFormat, peer.nickname)
			displayPeerRelatedNotification(title: title, body: alertBody, peerID: peer.peerID, category: .pinMatch, displayInApp: true)
		}
	}
}
