//
//  AppDelegate.swift
//  Peeree
//
//  Created by Christopher Kobusch on 19.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeServerChat
import PeereeIdP
import PeereeDiscovery

@main
struct PeereeApp: App {
	@UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

	@Environment(\.scenePhase) private var scenePhase

	private let mediator = Mediator()

	var body: some Scene {
		WindowGroup {
			MainView()
				.environmentObject(mediator.discoveryViewState)
				.environmentObject(mediator.serverChatViewState)
				.environmentObject(mediator.socialViewState)
				.environmentObject(InAppNotificationStackViewState.shared)
				.environmentObject(mediator.appViewState)
				.overlay(alignment: .top) {
					InAppNotificationStackView(controller: InAppNotificationStackViewState.shared)
				}
				.task {
					do {
						try await self.mediator.discoveryViewState.load()

						// start Bluetooth and server chat, but only if account exists
						if let ac = try await self.mediator.accountControllerFactory.use() {
							try await self.mediator.setup(ac: ac, errorTitle: NSLocalizedString("Login to Chat Server Failed", comment: "Error message title"))
							try await self.mediator.togglePeering(on: true)
						}
					} catch {
						InAppNotificationStackViewState.shared.display(genericError: error)
					}
				}
		}
		.onChange(of: scenePhase) { phase in
			mediator.appViewState.scenePhase = phase

			switch phase {
			case .background:
				break
			case .inactive:
				break
			case .active:
				if #available(iOS 10.0, *) {
					let notificationCenter = UNUserNotificationCenter.current()
					notificationCenter.removeAllPendingNotificationRequests()
					notificationCenter.removeAllDeliveredNotifications()

					if #available(iOS 16.0, *) {
						notificationCenter.setBadgeCount(0)
					}
				} else {
					UIApplication.shared.cancelAllLocalNotifications()
				}

				UIApplication.shared.applicationIconBadgeNumber = 0
				break
			@unknown default:
				break
			}
		}
	}
}

final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {

	// MARK: UIApplicationDelegate

	/**
	 *  Registers for notifications, presents onboarding on first launch and applies GUI theme
	 */
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

		return true
	}

	/**
	 *  Stops networking and synchronizes preferences
	 */
	func applicationWillTerminate(_ application: UIApplication) {
		ServerChatFactory.use { $0?.closeServerChat() }
		//mediator.togglePeering(on: false)
		UserDefaults.standard.synchronize()
	}

	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		//mediator.togglePeering(on: false)
	}

	/// MARK: Notifications

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		elog(Self.LogTag, "Remote notifications are unavailable: \(error.localizedDescription)")
		InAppNotificationStackViewState.shared.display(InAppNotification(localizedTitle: "Notification Registration Failed", localizedMessage: error.localizedDescription, severity: .error, furtherDescription: nil))
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		ServerChatFactory.use { $0?.configureRemoteNotificationsDeviceToken(deviceToken) }
	}

	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		completionHandler(.newData)
	}

	// MARK: - Private

	// Log tag.
	private static let LogTag = "AppDelegate"
}
