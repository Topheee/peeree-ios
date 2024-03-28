//
//  InAppNotificationStackViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

@MainActor
final class InAppNotificationStackViewState: ObservableObject {
	static let shared = InAppNotificationStackViewState()

	@Published private (set) var notifications: [InAppNotification] = []

	var timeRemaining: TimeInterval {
		guard let target = self.timer?.fireDate else { return -1 }

		let now = Date()
		return target.timeIntervalSince(now)
	}

//	func display(localizedTitle: String, localizedMessage: String, severity: InAppNotification.Severity, furtherDescription: String? = nil) {
//		notifications.append(InAppNotification(localizedTitle: localizedTitle, localizedMessage: localizedMessage, severity: severity, furtherDescription: furtherDescription))
//	}

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
		self.display(InAppNotification(localizedTitle: NSLocalizedString("Unexpected Error", comment: "Title of alert"), localizedMessage: error.localizedDescription, severity: .error, furtherDescription: nil))
	}
}
