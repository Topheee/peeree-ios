//
//  NotificationManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.03.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import UIKit
import CoreServices
import PeereeCore
import PeereeServerChat
import PeereeIdP
import PeereeDiscovery

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

	/// Notifications that came in bevor `mediator` was set.
	private var notificationQueue: [Notification] = []

	private var mediator: Mediator?

	/// Prepares local and remote notification handling.
	override init() {
		super.init()

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

			let pinMatchCategory = UNNotificationCategory(identifier: NotificationCategory.pinMatch.rawValue, actions: [pinMatchMessageAction], intentIdentifiers: [])
			let messageCategory = UNNotificationCategory(identifier: NotificationCategory.message.rawValue, actions: [messageReplyAction], intentIdentifiers: [])
			let peerAppearedCategory = UNNotificationCategory(identifier: NotificationCategory.peerAppeared.rawValue, actions: [peerAppearedPinAction], intentIdentifiers: [])
			
			notificationCenter.setNotificationCategories([pinMatchCategory, messageCategory, peerAppearedCategory])
		}
	}

	/// Call this method after the user took an action that could result in a notification.
	func setupNotifications(mediator: Mediator) {
		self.mediator = mediator

		UNUserNotificationCenter.current().requestAuthorization(
			options: [.alert, .badge, .sound]) { granted, error in

			// Enable or disable features based on authorization.
			guard error == nil else {
				elog(Self.LogTag, "Error requesting user notification authorization: \(error!.localizedDescription)")
				return
			}

			Task { @MainActor in
				UIApplication.shared.registerForRemoteNotifications()
			}
		}
	}

	// MARK: UNUserNotificationCenterDelegate

	@available(iOS 10.0, *)
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		defer { completionHandler() }

		let userInfo = response.notification.request.content.userInfo
		guard let peerIDString = userInfo[Self.PeerIDKey] as? String,
			  let peerID = PeerID(uuidString: peerIDString) else {
			elog(Self.LogTag, "cannot find peerID in notification content.")
			return
		}
		guard let action = NotificationActions(rawValue: response.actionIdentifier) else {
			switch response.actionIdentifier {
			case UNNotificationDefaultActionIdentifier:
				if let m = self.mediator {
					Task { @MainActor in m.showOrMessage(peerID) }
				}
			case UNNotificationDismissActionIdentifier:
				return
			default:
				elog(Self.LogTag, "unknown notification action \(response.actionIdentifier).")
				return
			}
			return
		}

		switch action {
		case .pinMatchMessage, .messageReply:
			guard let textResponse = response as? UNTextInputNotificationResponse,
				  let scvs = self.mediator?.serverChatViewState,
				  textResponse.userText != "" else { return }

			let message = textResponse.userText

			Task {
				do {
					try await scvs.backend?
						.send(message: message, to: peerID)
				} catch {
					elog("NotificationManager.Task",
						 "failed to send message from notification: "
						 + error.localizedDescription)
				}
			}
		case .peerAppearedPin:
			guard let m = self.mediator else { return }

			Task {
				await m.pinToggle(peerID: peerID)
			}
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
		Self.dismissRemoteNotifications()

		if #available(iOS 14.0, *) {
			completionHandler(UNNotificationPresentationOptions.banner)
		} else {
			completionHandler(UNNotificationPresentationOptions.alert)
		}
	}

	// - MARK: Private

	enum NotificationCategory: String {
		case peerAppeared, pinMatch, message, none
	}
	private enum NotificationActions: String {
		case peerAppearedPin, pinMatchMessage, messageReply
	}

	// MARK: Constants

	// Log tag.
	private static let LogTag = "NotificationManager"

	private static let PeerIDKey = "PeerIDKey"

	private static let PortraitAttachmentIdentifier = "PortraitAttachmentIdentifier"

	// MARK: Methods

	/// shows an in-app or system (local) notification related to a peer
	static func displayPeerRelatedNotification(title: String, body: String, peerID: PeerID, category: NotificationCategory) {
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
					elog(Self.LogTag, "Scheduling local notification failed: \(error.localizedDescription)")
				}
			}

		// unschedule all remote notifications when we received a local one
		Self.dismissRemoteNotifications()
	}

	/// Unschedules all remote notifications.
	private static func dismissRemoteNotifications() {
		let center = UNUserNotificationCenter.current()

		center.getDeliveredNotifications { (notifications) in
			let remoteNotificationIdentifiers: [String] = notifications.compactMap { notification in
				guard notification.request.trigger is UNPushNotificationTrigger else { return nil }

				return notification.request.identifier
			}

			center.removeDeliveredNotifications(withIdentifiers: remoteNotificationIdentifiers)
		}
	}
}
