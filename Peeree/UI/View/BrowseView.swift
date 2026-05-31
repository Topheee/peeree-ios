//
//  BrowseView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 02.11.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform dependencies
import SwiftUI

// Project dependencies
import PeereeCore
import PeereeDiscovery

struct BrowseView: View {

	@EnvironmentObject private var discoveryViewState: DiscoveryViewState

	@EnvironmentObject private var socialViewState: SocialViewState

	@State private var lookingOutPaneHeight: CGFloat = 0.0

	@GestureState private var dragOffset: CGFloat = 0.0

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	@Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

	private static let dummyPeerID = PeerID()

	private let dummyDiscoveryPerson = DiscoveryPerson(
		peerID: Self.dummyPeerID,
		info: PeerInfo(nickname: "Unknown Peereer",
					   gender: .queer, age: nil, hasPicture: false),
		lastSeen: Date.distantPast)

	/// Necessary for layout placeholder view.
	private let dummySocialPerson = SocialPerson(peerID: Self.dummyPeerID)

	var body: some View {
		VStack {
			ScrollViewReader { proxy in
				ScrollView(.horizontal, showsIndicators: false) {
					HStack {
						var index = 0
						ForEach(discoveryViewState.peopleInFilter, id: \.id) { discoveryPersona in
							PortraitView(socialPersona: socialViewState.persona(of: discoveryPersona.peerID), discoveryPersona: discoveryPersona) { showingDetail in
								withAnimation {
									proxy.scrollTo(discoveryPersona.id, anchor: .bottom)
								}
							}
							.id(discoveryPersona.id)
							.padding()
							.offset(x: 0, y: discoveryViewState.peering ? 0 : 200)
							.animation(.ripple(index: advancing(&index)), value: discoveryViewState.peering)
						}

						if self.discoveryViewState.browseFilter.displayFilteredPeople {
							var index = 0
							ForEach(discoveryViewState.peopleOutFilter, id: \.id) { discoveryPersona in
								PortraitView(socialPersona: socialViewState.persona(of: discoveryPersona.peerID), discoveryPersona: discoveryPersona) { showingDetail in
									withAnimation {
										proxy.scrollTo(discoveryPersona.id)
									}
								}
								.id(discoveryPersona.id)
								.padding()
								.offset(x: 0, y: discoveryViewState.peering ? 0 : 200)
								.animation(.ripple(index: advancing(&index)), value: discoveryViewState.peering)
							}
						}

						// only for layout
						PortraitView(socialPersona: dummySocialPerson, discoveryPersona: dummyDiscoveryPerson)
							.hidden()
					}
					.frame(
						maxHeight: discoveryViewState.peering
						? (verticalSizeClass == .compact
							? 120
							: (dynamicTypeSize.isAccessibilitySize ? 260 : 180))
						: 0)
				}
			}

			if !discoveryViewState.peering || verticalSizeClass == .regular {
				Text(discoveryViewState.peering ? "Online – Looking for people." : "Offline")
					.fontWeight(discoveryViewState.peering ? .light : .thin)
					.lineLimit(1)
					.padding([.bottom], discoveryViewState.peering ? 8 : 6)
					.accessibilityHint(
						discoveryViewState.peering ?
							"Tap to go offline" : "Tap to go online")
					.accessibilityAddTraits(.isButton)
			}
		}
		.onTapGesture {
			self.discoveryViewState.backend?
				.togglePeering(on: !discoveryViewState.peering)
		}
		.overlay(
			GeometryReader(content: { geometry in
				Color.clear
					.onAppear(perform: {
						self.lookingOutPaneHeight = max(geometry.frame(in: .local).size.height, self.lookingOutPaneHeight)
					})
			})
		)
		.frame(minHeight: discoveryViewState.peering ? self.lookingOutPaneHeight : self.lookingOutPaneHeight - max(self.dragOffset, 0.0))
		.background(DiscoveryBackgroundView(lookingOut: discoveryViewState.peering))
		.modify {
			if #available(iOS 26.0, *) {
				$0.glassEffect(in: .rect(cornerRadius: 16.0))
			} else {
				$0
			}
		}
		.padding()
		.shadow(radius: 10)
		.offset(x: 0, y: discoveryViewState.peering ? max(dragOffset, 0.0) : 0.0)
		.animation(.snappy, value: discoveryViewState.peering)
	}
}
