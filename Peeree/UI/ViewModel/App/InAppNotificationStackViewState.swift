//
//  InAppNotificationStackViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

// Platform Dependencies
import SwiftUI

// Internal Dependencies
import PeereeCore

@MainActor
final class InAppNotificationStackViewState: ObservableObject {
	private static let LogTag = "InAppNotificationStackViewState"

	static let shared = InAppNotificationStackViewState()

	@Published private(set) var notifications: [InAppNotification] = []

	var timeRemaining: TimeInterval {
		guard let target = self.timer?.fireDate else { return -1 }

		let now = Date()
		return target.timeIntervalSince(now)
	}

	func display(_ notification: InAppNotification) {
		notifications.append(notification)

		if timer == nil {
			startTimer()
		}
	}

	func pauseRemoval() {
		self.timer?.invalidate()
		self.timer = nil
	}

	func resumeRemoval() {
		guard timer == nil else { return }
		startTimer()
	}

	/// Dismisses the notification at the top of the stack.
	func dismiss() {
		pauseRemoval()
		removeFirst()
		resumeRemoval()
	}

	private func startTimer() {
		let t = Timer.scheduledTimer(timeInterval: Self.PresentationDuration, target: self, selector: #selector(removeFirst), userInfo: nil, repeats: true)
		t.tolerance = Self.PresentationDuration / 10
		self.timer = t
	}

	/*private*/ static let PresentationDuration: TimeInterval = 12.2

	private var timer: Timer? = nil

	@objc
	private func removeFirst() {
		if !notifications.isEmpty {
			notifications.removeFirst()
		} else {
			pauseRemoval()
		}
	}
}

extension InAppNotificationStackViewState {
	func display(genericError error: Error) {
		elog(Self.LogTag, "Displaying \(error)")
		self.display(InAppNotification(
			localizedTitle: NSLocalizedString("Unexpected Error",
											  comment: "Title of alert"),
			localizedMessage: error.localizedDescription,
			severity: .error, furtherDescription: nil))
	}
}
