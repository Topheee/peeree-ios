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
	@State private var lookingOutHeaderHeight: CGFloat = 0.0

	@GestureState private var dragOffset: CGFloat = 0.0

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	private static let dummyPeerID = PeerID()

	private let dummyDiscoveryPerson = DiscoveryPerson(
		peerID: Self.dummyPeerID,
		info: PeerInfo(nickname: "Unknown Peereer",
					   gender: .queer, age: nil, hasPicture: false),
		lastSeen: Date.distantPast)

	/// Necessary for layout placeholder view.
	private let dummySocialPerson = SocialPerson(peerID: Self.dummyPeerID)

	var body: some View {
		let lookoutDragGesture = DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
			.updating($dragOffset, body: { value, state, transaction in
				state = value.translation.height
			})
			.onEnded { value in
				let translation = value.startLocation.y - value.location.y
				let peering = discoveryViewState.peering
				guard peering ? translation < -82 : translation > 82 else { return }

				//TODO: dis Mediator.shared.togglePeering(on: !peering)
			}

		VStack {
			VStack {
				RoundedRectangle(cornerRadius: 5.0)
					.padding(.top, 8)
					.padding(.bottom, 2)
					.frame(width: 100, height: 16)

				if !discoveryViewState.peering || verticalSizeClass == .regular {
					Text(discoveryViewState.peering ? "Online – Looking for people." : "Offline")
						.fontWeight(discoveryViewState.peering ? .light : .thin)
						.lineLimit(1)
				}
			}
			.overlay(
				GeometryReader(content: { geometry in
					Color.clear
						.onAppear(perform: {
							self.lookingOutHeaderHeight = max(geometry.frame(in: .local).size.height, self.lookingOutHeaderHeight)
						})
				})
			)
			.offset(y: discoveryViewState.peering ? 0.0 : min(max(dragOffset, -self.lookingOutPaneHeight + self.lookingOutHeaderHeight), 0.0))

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
							.padding([.bottom, .leading, .trailing])
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
								.padding([.bottom, .leading, .trailing])
								.offset(x: 0, y: discoveryViewState.peering ? 0 : 200)
								.animation(.ripple(index: advancing(&index)), value: discoveryViewState.peering)
							}
						}

						// only for layout
						PortraitView(socialPersona: dummySocialPerson, discoveryPersona: dummyDiscoveryPerson)
							.hidden()
					}
					.frame(maxHeight: discoveryViewState.peering ? (verticalSizeClass == .compact ? 120 : 180) : 0)
				}
			}
		}
		.onTapGesture {
			self.discoveryViewState.backend?
				.togglePeering(on: !discoveryViewState.peering)
		}
		.gesture(lookoutDragGesture)
		.overlay(
			GeometryReader(content: { geometry in
				Color.clear
					.onAppear(perform: {
						self.lookingOutPaneHeight = max(geometry.frame(in: .local).size.height, self.lookingOutPaneHeight)
					})
			})
		)
		.frame(minHeight: discoveryViewState.peering ? self.lookingOutPaneHeight : min(self.lookingOutHeaderHeight - max(self.dragOffset, 0.0), self.lookingOutPaneHeight))
		.background(DiscoveryBackgroundView(lookingOut: discoveryViewState.peering))
		.modify {
			if #available(iOS 26.0, *) {
				$0.glassEffect(in: .rect(cornerRadius: 16.0))
			}
		}
		.padding()
		.shadow(radius: 10)
		.offset(x: 0, y: discoveryViewState.peering ? max(dragOffset, 0.0) : 0.0)
		.animation(.snappy, value: discoveryViewState.peering)
		.onAppear {
			discoveryViewState.browsing = true
		}
		.onDisappear {
			discoveryViewState.browsing = false
		}
	}
}
