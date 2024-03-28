//
//  MainView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeDiscovery

struct MainView: View {

	@EnvironmentObject private var chatViewState: ServerChatViewState

	@EnvironmentObject private var discoveryViewState: DiscoveryViewState

	@EnvironmentObject private var serverChatViewState: ServerChatViewState

	@EnvironmentObject private var socialViewState: SocialViewState

	@GestureState private var dragOffset: CGFloat = 0.0

	@State private var lookingOutPaneHeight: CGFloat = 0.0
	@State private var lookingOutHeaderHeight: CGFloat = 0.0

	@State private var showingProfile = false
	@State private var showingFilter = false

	private static let dummyPeerID = PeerID()

	private let dummyDiscoveryPerson = DiscoveryPerson(peerID: Self.dummyPeerID, info: PeerInfo(nickname: "Unknown Peereer", gender: .queer, age: nil, hasPicture: false), lastSeen: Date.distantPast)

	/// Necessary for layout placeholder view.
	private let dummySocialPerson = SocialPerson(peerID: Self.dummyPeerID)

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	var body: some View {
		let lookoutDragGesture = DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
			.updating($dragOffset, body: { value, state, transaction in
				state = value.translation.height
			})
			.onEnded { value in
				guard abs(abs(value.startLocation.y - value.location.y)) > 42 else { return }

				Mediator.shared.togglePeering(on: !discoveryViewState.peering)
			}

		NavigationView {
			ZStack(alignment: .bottom) {
				VStack {
					if chatViewState.matchedPeople.isEmpty {
						Spacer()
						OnboardingView(peering: $discoveryViewState.peering)
						Spacer(minLength: lookingOutHeaderHeight + 36)
					} else {
						List(chatViewState.matchedPeople, id: \.id) { chatPersona in
							let discoveryPersona = discoveryViewState.persona(of: chatPersona.peerID)
							NavigationLink(tag: chatPersona.peerID, selection: $serverChatViewState.displayedPeerID) {
								ChatView(discoveryPersona: discoveryPersona, chatPersona: chatPersona)
							} label: {
								//ChatTableCell(portrait: discoveryPersona.image, personName: discoveryPersona.info.nickname, lastMessage: chatPersona.lastMessage?.message ?? "", unreadMessageCount: chatPersona.unreadMessages)
								ChatTableCell2(chatPersona: chatPersona, discoveryPersona: discoveryPersona)
							}
						}
						.listStyle(.inset)

						Rectangle()
							.fill(Color.clear)
							.frame(height: discoveryViewState.peering ? lookingOutPaneHeight : lookingOutHeaderHeight)

//						List {
//							ForEach(chatViewState.matchedPeople) { chatPersona in
//								let discoveryPersona = discoveryViewState.persona(of: chatPersona.peerID)
//								NavigationLink {
//									ChatView(discoveryPersona: discoveryPersona, chatPersona: chatPersona)
//								} label: {
//									//ChatTableCell(portrait: discoveryPersona.image, personName: discoveryPersona.info.nickname, lastMessage: chatPersona.lastMessage?.message ?? "", unreadMessageCount: chatPersona.unreadMessages)
//									ChatTableCell2(chatPersona: chatPersona, discoveryPersona: discoveryPersona)
//								}
//							}
//
//							Rectangle()
//								.fill(Color.clear)
//								.frame(height: discoveryViewState.peering ? lookingOutPaneHeight : lookingOutHeaderHeight)
//						}
//						.listStyle(.inset)
					}
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
					.offset(y: discoveryViewState.peering ? 0.0 : (max(dragOffset, -self.lookingOutPaneHeight + self.lookingOutHeaderHeight) / 2.0))
					.onTapGesture {
						Mediator.shared.togglePeering(on: !discoveryViewState.peering)
					}
					.gesture(lookoutDragGesture)

					ScrollViewReader { proxy in
						ScrollView(.horizontal, showsIndicators: false) {
							HStack {
								var index = 0
								ForEach(discoveryViewState.peopleInFilter, id: \.id) { discoveryPersona in
									PortraitView(socialPersona: socialViewState.persona(of: discoveryPersona.peerID), discoveryPersona: discoveryPersona) { showingDetail in
										if #available(iOS 15, *) {
											withAnimation {
												proxy.scrollTo(discoveryPersona.id)
											}
										}
									}
									.modify {
										if #available(iOS 15, *) {
											$0.id(discoveryPersona.id)
										}
									}
									.offset(x: 0, y: discoveryViewState.peering ? 0 : 200)
									.animation(.ripple(index: advancing(&index)), value: discoveryViewState.peering)
								}

								if self.discoveryViewState.browseFilter.displayFilteredPeople {
									var index = 0
									ForEach(discoveryViewState.peopleOutFilter, id: \.id) { discoveryPersona in
										PortraitView(socialPersona: socialViewState.persona(of: discoveryPersona.peerID), discoveryPersona: discoveryPersona) { showingDetail in
											if #available(iOS 15, *) {
												withAnimation {
													proxy.scrollTo(discoveryPersona.id)
												}
											}
										}
										.modify {
											if #available(iOS 15, *) {
												$0.id(discoveryPersona.id)
											}
										}
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
				.overlay(
					GeometryReader(content: { geometry in
						Color.clear
							.onAppear(perform: {
								self.lookingOutPaneHeight = max(geometry.frame(in: .local).size.height, self.lookingOutPaneHeight)
							})
					})
				)
				.frame(minHeight: discoveryViewState.peering ? self.lookingOutPaneHeight : min(0.0 - self.dragOffset + self.lookingOutHeaderHeight, self.lookingOutPaneHeight))
				.background(DiscoveryBackgroundView(lookingOut: discoveryViewState.peering))
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
			.navigationTitle("Pinboard")
			.modify {
				if #available(iOS 16, *) {
					$0.toolbarRole(.navigationStack)
				} else { $0 }
			}
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button {
						showingProfile.toggle()
					} label: {
						Label("Profile", systemImage: "person.crop.circle")
					}
				}

				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						showingFilter.toggle()
					} label: {
						Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
					}
				}
			}
			.sheet(isPresented: $showingProfile) {
				ProfileView() {
					self.showingProfile.toggle()
				}
			}
			.sheet(isPresented: $showingFilter) {
				FilterView(filter: $discoveryViewState.browseFilter) {
					self.showingFilter.toggle()
				}
			}
			.popover(item: $discoveryViewState.displayedPersona) { displayedPersona in
				let socialPersona = socialViewState.persona(of: displayedPersona.peerID)
				PersonView(socialPersona: socialPersona, discoveryPersona: displayedPersona)
					.toolbar {
						ToolbarItem(placement: .navigationBarLeading) {
							Button {
								discoveryViewState.displayedPersona = nil
							} label: {
								Label("Done", systemImage: "checkmark.circle")
							}
						}
					}
			}
		}
	}
}

#Preview {
	let people = [
		PeerInfo(nickname: "Lea", gender: .female, age: 28, hasPicture: true),
		PeerInfo(nickname: "Anna", gender: .female, age: 27, hasPicture: true),
		PeerInfo(nickname: "Ingrid sadf fadf baeg", gender: .female, age: 22, hasPicture: true),
		PeerInfo(nickname: "Lea", gender: .female, age: 28, hasPicture: true),
		PeerInfo(nickname: "Anna", gender: .female, age: 27, hasPicture: true),
		PeerInfo(nickname: "Ingrid", gender: .female, age: 22, hasPicture: true)
	]

	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let ns = InAppNotificationStackViewState()

//	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .info, furtherDescription: "Ich war hier"))
//
//	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .error, furtherDescription: "Oh shit 1"))
//
//	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .warning, furtherDescription: "Oh shit 2"))
//
//	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .warning, furtherDescription: "Oh shit 3"))
//
//	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .warning, furtherDescription: "Oh shit 4"))

	var index = 0
	for p in people {
		let peerID = PeerID()
		let dp = ds.addPersona(of: peerID, with: p)
		dp.set(portrait: UIImage(named: "p\((advancing(&index) % 3) + 1)")?.cgImage, hash: Data())
		dp.lastSeen = Date().advanced(by: TimeInterval(-120 * index))
		dp.biography = "Hi from \(index)"
		let sp = ss.demo(peerID)
		if sp.pinState == .pinMatch {
			let cp = cs.persona(of: peerID)
			cp.readyToChat = index % 2 == 0
			cp.unreadMessages = cp.readyToChat ? 3 : 0
		}
	}

	//return MainView(profile: .constant(Profile(socialPersona: ss.demo(ownPeerID), discoveryPersona: DiscoveryPerson(peerID: ownPeerID, info: PeerInfo(nickname: "Bartholomaeus Didactus Mechanicus", gender: .queer, age: nil, hasPicture: false), lastSeen: Date()))))
	return MainView()
		.environmentObject(ds)
		.environmentObject(cs)
		.environmentObject(ss)
		.environmentObject(ns)
}

#Preview {
	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let ns = InAppNotificationStackViewState()

	return MainView()
		.environmentObject(ds)
		.environmentObject(cs)
		.environmentObject(ss)
		.environmentObject(ns)
}

// if not sufficient: https://stackoverflow.com/a/66175501
