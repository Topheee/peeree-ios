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
import PeereeServer
import PeereeDiscovery

@main
struct PeereeApp: App {
	@UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

	@Environment(\.scenePhase) private var scenePhase

	var body: some Scene {
		WindowGroup {
			ZStack(alignment: .top) {
				MainView()
					.environmentObject(DiscoveryViewState.shared)
					.environmentObject(ServerChatViewState.shared)
					.environmentObject(SocialViewState.shared)
					.environmentObject(InAppNotificationStackViewState.shared)
					.environmentObject(AppViewState.shared)

				InAppNotificationStackView(controller: InAppNotificationStackViewState.shared)
			}
				.task {
					do {
						SocialViewState.shared.delegate = Mediator.shared
						try await DiscoveryViewState.shared.load()
					} catch {
						InAppNotificationStackViewState.shared.display(genericError: error)
					}
				}
		}
		.onChange(of: scenePhase) { phase in
			AppViewState.shared.scenePhase = phase

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
		// Configure singletons
		AccountControllerFactory.shared.initialize(viewModel: SocialViewState.shared)

		// start Bluetooth and server chat, but only if account exists
		AccountControllerFactory.shared.use { ac in
			Mediator.shared.setup(ac: ac, errorTitle: NSLocalizedString("Login to Chat Server Failed", comment: "Error message title"))
			Mediator.shared.togglePeering(on: true)
		}

		return true
	}

	/**
	 *  Stops networking and synchronizes preferences
	 */
	func applicationWillTerminate(_ application: UIApplication) {
		ServerChatFactory.use { $0?.closeServerChat() }
		Mediator.shared.togglePeering(on: false)
		UserDefaults.standard.synchronize()
	}

	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		Mediator.shared.togglePeering(on: false)
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
