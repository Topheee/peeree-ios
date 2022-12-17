//
//  NotificationManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.03.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit
import CoreServices

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
	private enum NotificationCategory: String {
		case peerAppeared, pinMatch, message, none
	}
	private enum NotificationActions: String {
		case peerAppearedPin, pinMatchMessage, messageReply
	}

	private static let PeerIDKey = "PeerIDKey"

	private static let PortraitAttachmentIdentifier = "PortraitAttachmentIdentifier"

	/// Prepares local and remote notification handling.
	func initialize() {
		(try? BrowseFilter.getFilter()).map { filter = $0 }

		observeNotifications()

		if #available(iOS 10.0, *) {
			UIApplication.shared.registerForRemoteNotifications()
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
		guard application.applicationState == .inactive,
			  let peerIDString = notification.userInfo?[Self.PeerIDKey] as? String,
			  let peerID = PeerID(uuidString: peerIDString) else { return }

		AppDelegate.shared.showOrMessage(peerID: peerID)
	}

	// MARK: UNUserNotificationCenterDelegate

	@available(iOS 10.0, *)
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		defer { completionHandler() }

		let userInfo = response.notification.request.content.userInfo
		guard let peerIDString = userInfo[Self.PeerIDKey] as? String,
			  let peerID = PeerID(uuidString: peerIDString) else {
			elog("cannot find peerID in notification content.")
			return
		}
		guard let action = NotificationActions(rawValue: response.actionIdentifier) else {
			switch response.actionIdentifier {
			case UNNotificationDefaultActionIdentifier:
				AppDelegate.shared.showOrMessage(peerID: peerID)
			case UNNotificationDismissActionIdentifier:
				return
			default:
				elog("unknown notification action \(response.actionIdentifier).")
				return
			}
			return
		}

		switch action {
		case .pinMatchMessage, .messageReply:
			guard let textResponse = response as? UNTextInputNotificationResponse,
				  textResponse.userText != "" else { return }

			ServerChatFactory.getOrSetupInstance { instanceResult in
				instanceResult.value?.send(message: textResponse.userText, to: peerID) { messageResult in
					messageResult.error.map { elog("failed to send message from notification: \($0.localizedDescription)") }
				}
			}
		case .peerAppearedPin:
			guard let id = PeereeIdentityViewModelController.viewModels[peerID]?.id else { break }

			AccountController.use { $0.pin(id) }
		}

		// unschedule all notifications of this category
		let categoryID = response.notification.request.content.categoryIdentifier
		center.getDeliveredNotifications { (notifications) in
			let sameCategoryIdentifiers: [String] = notifications.compactMap {
				$0.request.content.categoryIdentifier == categoryID ? $0.request.identifier : nil
			}

			center.removeDeliveredNotifications(withIdentifiers: sameCategoryIdentifiers)
		}
	}

	@available(iOS 10.0, *)
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		guard !(notification.request.trigger is UNPushNotificationTrigger) else {
			// do not display remote notifications at all while being in the foreground
			completionHandler([])
			return
		}

		// unschedule all remote notifications when we received a local one
		dismissRemoteNotifications()

		if #available(iOS 14.0, *) {
			completionHandler(UNNotificationPresentationOptions.banner)
		} else {
			completionHandler(UNNotificationPresentationOptions.alert)
		}
	}

	// - MARK: Private

	// MARK: Variables

	/// Currently applied filter.
	private var filter = BrowseFilter()

	// MARK: Methods

	/// shows an in-app or system (local) notification related to a peer
	private func displayPeerRelatedNotification(title: String, body: String, peerID: PeerID, category: NotificationCategory, displayInApp: Bool) {
		if #available(iOS 10, *) {
			guard !AppDelegate.shared.isActive || displayInApp else { return }

			let center = UNUserNotificationCenter.current()
			let content = UNMutableNotificationContent()
			content.title = title
			content.body = body.replacingOccurrences(of: "%", with: "%%")
			content.sound = UNNotificationSound.default
			content.userInfo = [Self.PeerIDKey : peerID.uuidString]
			content.categoryIdentifier = category.rawValue
			content.threadIdentifier = peerID.uuidString

			if #available(iOS 15, *) {
				switch category {
				case .peerAppeared:
					content.relevanceScore = 1.0
					content.interruptionLevel = .timeSensitive
				case .pinMatch:
					content.relevanceScore = 0.9
					content.interruptionLevel = .timeSensitive
				case .message:
					content.relevanceScore = 0.8
					content.interruptionLevel = .timeSensitive
				case .none:
					content.relevanceScore = 0.0
					content.interruptionLevel = .passive
				}
			}

			// TODO: copy the user's portrait to a temporary location to be able to attach it
//			if let attachment = try? UNNotificationAttachment(identifier: NotificationManager.PortraitAttachmentIdentifier,
//													  url: PeeringController.shared.pictureURL(of: peerID),
//															  options: [UNNotificationAttachmentOptionsTypeHintKey : kUTTypeJPEG]) {
//				content.attachments = [attachment]
//			}

			center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false))) { (error) in
				if let error {
					elog("Scheduling local notification failed: \(error.localizedDescription)")
				}
			}
		} else {
			if AppDelegate.shared.isActive && displayInApp {
				InAppNotificationController.display(title: title, message: body, isNegative: false) //{ AppDelegate.shared.showOrMessage(peerID: peerID) }
			} else {
				let note = UILocalNotification()
				note.alertTitle = title
				note.alertBody = body
				note.userInfo = [Self.PeerIDKey : peerID.uuidString]
				note.category = category.rawValue
				UIApplication.shared.presentLocalNotificationNow(note)
			}
		}

		// unschedule all remote notifications when we received a local one
		dismissRemoteNotifications()
	}

	private func received(message: String, from peerID: PeerID) {
		let name = PeerViewModelController.shared.viewModels[peerID]?.info.nickname ?? peerID.uuidString

		let title: String
		if #available(iOS 10.0, *) {
			// The localizedUserNotificationString(forKey:arguments:) method delays the loading of the localized string until the notification is delivered. Thus, if the user changes language settings before a notification is delivered, the alert text is updated to the user’s current language instead of the language that was set when the notification was scheduled.
			title = NSString.localizedUserNotificationString(forKey: "Message from %@.", arguments: [name])
		} else {
			let titleFormat = NSLocalizedString("Message from %@.", comment: "Notification alert body when a message is received.")
			title = String(format: titleFormat, name)
		}
		var messagesNotVisible = true
		if let tabBarVC = AppDelegate.shared.window?.rootViewController as? UITabBarController {
			if tabBarVC.selectedIndex == AppDelegate.PinMatchesTabBarIndex {
				messagesNotVisible = ((tabBarVC.viewControllers?[AppDelegate.PinMatchesTabBarIndex] as? UINavigationController)?.visibleViewController as? MessagingViewController)?.peerID != peerID
			} else {
				tabBarVC.incrementItemBatch(itemIndex: AppDelegate.PinMatchesTabBarIndex)
			}
		}
		displayPeerRelatedNotification(title: title, body: message, peerID: peerID, category: .message, displayInApp: messagesNotVisible)
	}

	private func peerAppeared(_ peerID: PeerID, again: Bool) {
		guard !again, let model = PeerViewModelController.shared.viewModels[peerID],
			  let idModel = PeereeIdentityViewModelController.viewModels[peerID],
			  filter.check(info: model.info, pinState: idModel.pinState) else { return }

		PeeringController.shared.interact(with: peerID) { interaction in
			interaction.loadBio { _ in }
			interaction.loadPicture { _ in }
		}

		let alertBodyFormat = NSLocalizedString("Found %@.", comment: "Notification alert body when a new peer was found on the network.")
		var notBrowsing = true
		if let tabBarVC = AppDelegate.shared.window?.rootViewController as? UITabBarController {
			if tabBarVC.selectedIndex == AppDelegate.BrowseTabBarIndex {
				notBrowsing = (tabBarVC.viewControllers?[AppDelegate.BrowseTabBarIndex] as? UINavigationController)?.visibleViewController as? BrowseViewController == nil
			} else {
				tabBarVC.incrementItemBatch(itemIndex: AppDelegate.BrowseTabBarIndex)
			}
		}

		let category: NotificationCategory = idModel.pinState == .pinMatch ? .none : .peerAppeared
		displayPeerRelatedNotification(title: String(format: alertBodyFormat, model.info.nickname), body: "", peerID: peerID, category: category, displayInApp: notBrowsing)
	}

	private func pinMatchOccured(_ peerID: PeerID) {
		if AppDelegate.shared.isActive {
			guard let pinMatchVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: PinMatchViewController.StoryboardID) as? PinMatchViewController else { return }
			pinMatchVC.peerID = peerID
			pinMatchVC.presentInFrontMostViewController(true, completion: nil)
		} else {
			let title = NSLocalizedString("New Pin Match!", comment: "Notification alert title when a pin match occured.")
			let alertBodyFormat = NSLocalizedString("Pin Match with %@!", comment: "Notification alert body when a pin match occured.")
			let alertBody = String(format: alertBodyFormat, PeerViewModelController.shared.viewModels[peerID]?.info.nickname ?? peerID.uuidString)
			displayPeerRelatedNotification(title: title, body: alertBody, peerID: peerID, category: .pinMatch, displayInApp: true)
		}
	}

	/// Unschedules all remote notifications.
	private func dismissRemoteNotifications() {
		let center = UNUserNotificationCenter.current()

		center.getDeliveredNotifications { (notifications) in
			let remoteNotificationIdentifiers: [String] = notifications.compactMap { notification in
				guard notification.request.trigger is UNPushNotificationTrigger else { return nil }

				return notification.request.identifier
			}

			center.removeDeliveredNotifications(withIdentifiers: remoteNotificationIdentifiers)
		}
	}

	/// Listen on `NotificationCenter`.
	private func observeNotifications() {
		_ = PeeringController.Notifications.connectionChangedState.addObserver { notification in
			if #available(iOS 10.0, *) {
				UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
					// Enable or disable features based on authorization.
					guard error == nil else {
						elog("Error requesting user notification authorization: \(error!.localizedDescription)")
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
		}

		_ = PeeringController.Notifications.peerAppeared.addAnyPeerObserver { peerID, notification  in
			let again = notification.userInfo?[PeeringController.NotificationInfoKey.again.rawValue] as? Bool
			self.peerAppeared(peerID, again: again ?? false)
		}

		_ = AccountController.NotificationName.pinMatch.addAnyPeerObserver { peerID, _  in
			self.pinMatchOccured(peerID)
		}

		_ = PeerViewModel.NotificationName.messageReceived.addAnyPeerObserver { peerID, notification in
			guard let message = notification.userInfo?[PeerViewModel.NotificationInfoKey.message.rawValue] as? String else { return }

			self.received(message: message, from: peerID)
		}

		_ = BrowseFilter.NotificationName.filterChanged.addObserver { notification in
			(notification.object as? BrowseFilter).map { self.filter = $0 }
		}
	}
}
