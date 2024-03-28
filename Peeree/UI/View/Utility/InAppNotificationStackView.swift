//
//  InAppNotificationStackView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

struct InAppNotificationStackView: View {
	@ObservedObject var controller: InAppNotificationStackViewState

	private static let Cap = 3

	private var displayCount: Int { min(controller.notifications.count, Self.Cap) }

	private func reversedIndex(_ index: Int) -> Int {
		return displayCount - index
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			ForEachIndexed(controller.notifications.prefix(Self.Cap).reversed()) { index, notification in
				InAppNotificationView(notification: notification,
									  time: controller.timeRemaining - 1.0 + (InAppNotificationStackViewState.PresentationDuration * Double(reversedIndex(index) - 1)))
					.padding(CGFloat((reversedIndex(index) + displayCount) * 12) / 2.0)
					.disabled(index != displayCount - 1)
					.animation(.easeInOut(duration: 0.4))
			}
		}
	}
}

#Preview {
	let controller = InAppNotificationStackViewState()
	let notifications = [
		InAppNotification(localizedTitle: "Severe Error in Sector 1", localizedMessage: "Please remain calm and proceed to the exits. Then do what you want to.", severity: .error, furtherDescription: nil),
		InAppNotification(localizedTitle: "Some Warning in Sector 2", localizedMessage: "huhu", severity: .info, furtherDescription: "nöa dsfadshlf lajksdhf lkasdjfh lakdsjfh laksjdfhlaksdfjh adsf asdf asdf"),
		InAppNotification(localizedTitle: "Some Warning in Sector 3", localizedMessage: "huhu", severity: .warning, furtherDescription: "nö adsffadsfladkjs fhalskfjh klewaf h;k jh ende"),
		InAppNotification(localizedTitle: "Some title 3", localizedMessage: "huhu", severity: .info, furtherDescription: nil)
	]

	for n in notifications {
		controller.display(n)
	}

	return InAppNotificationStackView(controller: controller)
}
