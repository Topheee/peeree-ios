//
//  OnboardingView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeSocial

/// Descriptive text in onboarding.
fileprivate func onboardingDescription(of state: PinState) -> String {
	switch state {
	case .unpinned:
		return NSLocalizedString("Use this button to pin people.", comment: "")
	case .pinning:
		return NSLocalizedString("Waiting for a response …", comment: "")
		//return "The app is waiting for a response, while the button is pulsing."
	case .pinned:
		return NSLocalizedString("The person is pinned.", comment: "")
		//return "A filled pin on the button indicates that the person is pinned."
	case .unpinning:
		return NSLocalizedString("Trying to remove the pin …", comment: "")
	case .pinMatch:
		return NSLocalizedString("Pin Match! You can now chat with the person.", comment: "")
	}
}

struct OnboardingView: View {
	@Binding var peering: Bool

	@State private var pinState = PinState.unpinned

	@State private var showingExplanation = false

	@State private var hasPinMatch = false

	private let howItWorksExplanations = [
		Explanation(iconName: "SocialColored", title: "Social", content: "Social content"),
		Explanation(iconName: "ConnectedColored", title: "Connected", content: "Connected content"),
		Explanation(iconName: "ClockColored", title: "Temporary", content: "Temporary content"),
		Explanation(iconName: "BatteryColored", title: "Efficient", content: "Efficient content"),
		Explanation(iconName: "LocalInfoColored", title: "Local", content: "Local content"),
		Explanation(iconName: "SecureColored", title: "Private", content: "Private content")
	]

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	var body: some View {
		VStack {
			if verticalSizeClass == .regular {
				HStack(alignment: .top) {
					ArrowShape(from: CGPoint(x: 80, y: 40),
							   to: CGPoint(x: 20, y: 0 ),
							   control: CGPoint(x: 20, y: 70))
					.stroke(Color.primary, lineWidth: 4)
					.frame(maxWidth: 80, maxHeight: 60)
					VStack {
						HStack {
							Text("Create your profile.")
								.padding(.vertical)

							Spacer()
						}
						HStack {
							Spacer()
							Text("Setup filter.")
						}
					}
					.frame(minWidth: 220)
					ArrowShape(from: CGPoint(x: 0 , y: 75),
							   to: CGPoint(x: 40, y: 0 ),
							   control: CGPoint(x: 50, y: 70))
					.stroke(Color.primary, lineWidth: 4)
					.frame(maxWidth: 60, maxHeight: 80)
				}
				.opacity(peering ? 0.0 : 1.0)
			}

			Spacer()

			VStack {
				if !peering {
					if verticalSizeClass == .regular {
						Text("Demo")
							.font(.title3)
					}

					PinButton(pinState: self.pinState, font: .title2) {
						self.pinState.next()
						if self.pinState == .pinMatch {
							hasPinMatch.toggle()
							UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
						}
						if self.pinState.isTransitioning {
							DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(3))) {
								withAnimation {
									self.pinState.next()
								}
							}
						} else {
							UINotificationFeedbackGenerator().notificationOccurred(.success)
						}
					}
					.padding()
					.modify {
						if #available(iOS 17, *) {
							$0.phaseAnimator([PinMatchAnimationPhase.start, PinMatchAnimationPhase.chargingUp, PinMatchAnimationPhase.slamming], trigger: hasPinMatch) { content, phase in
								content.scaleEffect(CGSize(
									width:  phase == .start ? 1.0 : (phase == .chargingUp ? PinMatchAnimationPhase.chargeUpScale : (phase == .slamming ? 0.01 : 1.0)),
									height: phase == .start ? 1.0 : (phase == .chargingUp ? PinMatchAnimationPhase.chargeUpScale : (phase == .slamming ? 0.01 : 1.0))
								))
							} animation: { phase in
								if phase == .chargingUp {
									.bouncy(duration:    PinMatchAnimationPhase.pinPhaseAnimationDuration,
											extraBounce: phase == .chargingUp ? 0.3 : 0.0)
								} else {
									.bouncy(duration:    PinMatchAnimationPhase.pinPhaseAnimationDuration / 2,
											extraBounce: phase == .chargingUp ? 0.3 : 0.0)
								}
							}
						}
					}
				}

				Text(peering ? NSLocalizedString("Lot's of void out here!", comment: "") : onboardingDescription(of: self.pinState))
					.font(.body)

				if verticalSizeClass == .regular {
					Text(peering ? "Visit crowded places to find other Peeree users." : "Peeree is all about Pinning. Pin people who you are interested in. If the pin is mutual, you can start chatting.")
						.font(.footnote)
						.padding(4)
				}
			}
			.padding()
			.background(RoundedRectangle(cornerRadius: 16).fill(peering ? Color.secondary : Color("ColorDivider")))

			Button {
				showingExplanation.toggle()
			} label: {
				Text("Learn more about how Peeree works")
			}
			.sheet(isPresented: $showingExplanation) {
				ExplanationView(explanations: howItWorksExplanations)

				Button {
					showingExplanation.toggle()
				} label: {
					Text("Sounds good!")
						.padding()
				}
			}

			Spacer()

			if verticalSizeClass == .regular {
				VStack {
					HStack(alignment: .bottom) {
						Text("Swipe up or tap to find new people.")

						ArrowShape(from: CGPoint(x: 0 , y: 40),
								   to: CGPoint(x: 46, y: 60),
								   control: CGPoint(x: 48, y: 15))
						.stroke(Color.primary, lineWidth: 4)
						.frame(maxWidth: 60, maxHeight: 60)
					}
					.padding()
					.opacity(peering ? 0.0 : 1.0)
				}
			}
		}
	}
}

#Preview {
	return OnboardingView(peering: Binding.constant(false))
}

#Preview {
	return OnboardingView(peering: Binding.constant(true))
}
