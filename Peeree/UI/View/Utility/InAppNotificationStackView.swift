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

	@GestureState private var dragOffset: CGFloat = 0.0

	@State private var secondsRemaining: Int = -1

	private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

	private var drag: some Gesture {
		DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
			.updating($dragOffset, body: { value, state, transaction in
				state = value.translation.height
			})
			.onEnded { value in
				let translation = value.startLocation.y - value.location.y
				guard translation > 22 else { return }

				controller.dismiss()
				secondsRemaining = Int(controller.timeRemaining)
			}
	}

	/// Careful, this is not updated!
	private var displayCount: Int { min(controller.notifications.count, Self.Cap) }

	@State private var stackLeft: Int = 0

	private func reversedIndex(_ index: Int) -> Int {
		return displayCount - index
	}

	var body: some View {
		// Cache for performance.
		let stackHeight = displayCount

		ZStack(alignment: .topLeading) {
			ForEachIndexed(controller.notifications.prefix(Self.Cap).reversed()) { index, notification in
				InAppNotificationView(notification: notification)
					.offset(y: (index == stackHeight - 1) ? min(dragOffset, 0.0) : 0.0)
					.padding(CGFloat((reversedIndex(index) + stackHeight) * 12) / 2.0)
					.disabled(index != stackHeight - 1)
					.animation(.easeInOut(duration: 0.4))
					.gesture(drag)
			}
		}
		.overlay(alignment: .topTrailing) {
			Text("\(self.secondsRemaining)")
				.font(.caption2)
				.padding(4)
				.background(Circle().fill(Color("ColorBackground")))
				.padding(CGFloat(12 + (stackLeft > 0 ? stackLeft : displayCount) * 6))
				.padding(.trailing, 2)
				.offset(y: min(dragOffset, 0.0))
				.onReceive(timer) { _ in
					stackLeft = displayCount
					if secondsRemaining <= 0 {
						secondsRemaining = Int(controller.timeRemaining)
//						if stackLeft == 0 {
//							timer.upstream.connect().cancel()
//						}
					} else {
						secondsRemaining -= 1
					}
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
