//
//  PortraitView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeDiscovery

@MainActor
struct PortraitView: View {
	init(peerID: PeerID, socialViewState: SocialViewState, discoveryViewState: DiscoveryViewState, onShowingDetail: ( (Bool) -> Void )? = nil) {
		self.peerID = peerID
		self.onShowingDetail = onShowingDetail
		self.discoveryPersona = discoveryViewState.persona(of: peerID)
		self.socialPersona = socialViewState.persona(of: peerID)
	}

	init(socialPersona: SocialPerson, discoveryPersona: DiscoveryPerson, onShowingDetail: ( (Bool) -> Void )? = nil) {
		self.peerID = socialPersona.peerID
		self.onShowingDetail = onShowingDetail
		self.socialPersona = socialPersona
		self.discoveryPersona = discoveryPersona
	}

	let peerID: PeerID

	var onShowingDetail: ((Bool) -> Void)? = nil

	@ObservedObject private var discoveryPersona: DiscoveryPerson

	@ObservedObject private var socialPersona: SocialPerson

	@State private var expanded = false

	@State private var showingDetail = false

	@EnvironmentObject private var socialViewState: SocialViewState

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	var body: some View {
		VStack {
			HStack {
				Text(discoveryPersona.info.nickname)
					.frame(maxWidth: 120)

				if discoveryPersona.biography != "" {
					Text(Image(systemName: "text.bubble"))
				}
			}
			.font(.body)
			.lineLimit(1)
			.offset(x: expanded ? 0 : 12)

			HStack {
				discoveryPersona.image
					.resizable()
					.aspectRatio(contentMode: .fit)
					.clipShape(Circle())
					.overlay(Circle().stroke(.white, lineWidth: 4))
					.onTapGesture {
						showingDetail.toggle()
					}
					.onLongPressGesture {
						withAnimation(reduceMotion ? .none : .bouncy()) {
							expanded.toggle()
						}
						onShowingDetail?(expanded)
					}
					.popover(isPresented: $showingDetail) {
						NavigationView {
							PersonView(socialPersona: socialPersona, discoveryPersona: discoveryPersona)
								.toolbar {
									ToolbarItem(placement: .navigationBarLeading) {
										Button {
											showingDetail = false
										} label: {
											Label("Done", systemImage: "checkmark.circle")
										}
									}
								}
						}
					}

				if expanded {
					PinButton(pinState: socialPersona.pinState, font: .headline) {
						guard !discoveryPersona.isUser else { return }
						socialViewState.delegate?.pinToggle(peerID: peerID)
					}
					.padding()
					.transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
				}
			}

			if verticalSizeClass == .regular {
				HStack {
					TimeTagView(text: discoveryPersona.lastSeenText)
						.font(.caption)

					if expanded {
//						TagView(text: discoveryPersona.genderText)
//							.transition(AnyTransition.identity)
//							.font(.caption)
						if let age = discoveryPersona.info.age {
							TagView(text: "\(age)")
								.transition(AnyTransition.identity)
								.font(.caption)
						}
					}
				}
			}
		}
		.transition(AnyTransition.move(edge: .top))
		.padding(2)
	}
}

#Preview {
	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	let info = PeerInfo(nickname: "Lea", gender: .male, age: 28, hasPicture: true)
	let person = ds.addPersona(of: PeerID(), with: info)
	person.set(portrait: UIImage(named: "p1")?.cgImage, hash: Data())
	person.lastSeen = Date()
	person.biography = "Ich war hier"
	ss.demo(person.peerID)
	return PortraitView(peerID: person.peerID, socialViewState: ss, discoveryViewState: ds)
}

#Preview {
	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	let info = PeerInfo(nickname: "Anna", gender: .queer, age: nil, hasPicture: true)
	let person = ds.addPersona(of: PeerID(), with: info)
	person.set(portrait: UIImage(named: "p2")?.cgImage, hash: Data())
	person.lastSeen = Date().advanced(by: -130)
	ss.demo(person.peerID)
	return PortraitView(peerID: person.peerID, socialViewState: ss, discoveryViewState: ds)
}

#Preview {
	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	let info = PeerInfo(nickname: "Ingrid", gender: .female, age: 21, hasPicture: true)
	let person = ds.addPersona(of: PeerID(), with: info)
	person.set(portrait: UIImage(named: "p3")?.cgImage, hash: Data())
	person.lastSeen = Date().advanced(by: -160)
	ss.demo(person.peerID)
	return PortraitView(peerID: person.peerID, socialViewState: ss, discoveryViewState: ds)
}
