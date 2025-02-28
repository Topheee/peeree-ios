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
				let translation = value.startLocation.y - value.location.y
				let peering = discoveryViewState.peering
				guard peering ? translation < -82 : translation > 82 else { return }

				//TODO: dis Mediator.shared.togglePeering(on: !peering)
			}

		NavigationView {
			ZStack(alignment: .bottom) {
				if chatViewState.matchedPeople.isEmpty {
					VStack {
						Spacer()
						OnboardingView(peering: $discoveryViewState.peering)
						Spacer(minLength: lookingOutHeaderHeight + 36)
					}
				} else {
					List(chatViewState.matchedPeople, id: \.id) { chatPersona in
						let discoveryPersona = discoveryViewState.persona(of: chatPersona.peerID)
						NavigationLink(tag: chatPersona.peerID, selection: $serverChatViewState.displayedPeerID) {
							ChatView(discoveryPersona: discoveryPersona, chatPersona: chatPersona)
						} label: {
							ChatTableCell(chatPersona: chatPersona, discoveryPersona: discoveryPersona)
						}
					}
					.listStyle(.inset)
					.padding(.bottom, (discoveryViewState.peering ? lookingOutPaneHeight : lookingOutHeaderHeight) + 12)
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
				NavigationView {
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
}

// for previews only
import PeereeServerChat

#Preview("In-App Notifications") {
	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let ns = InAppNotificationStackViewState()

	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .info, furtherDescription: "Ich war hier"))

	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .error, furtherDescription: "Oh shit 1"))

	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .warning, furtherDescription: "Oh shit 2"))

	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .warning, furtherDescription: "Oh shit 3"))

	ns.display(InAppNotification(localizedTitle: "A title", localizedMessage: "Huhu", severity: .warning, furtherDescription: "Oh shit 4"))

	return MainView()
		.environmentObject(ds)
		.environmentObject(cs)
		.environmentObject(ss)
		.environmentObject(ns)
		.overlay(alignment: .top) {
			InAppNotificationStackView(controller: ns)
		}
}

#Preview("App Store Scene 1") {
	// change to desired language
	let language = "en"
	let path = Bundle.main.path(forResource: language, ofType: "lproj")
	let bundle = Bundle(path: path!)!

	let people = [
		PeerInfo(nickname: "Lea", gender: .female, age: 28, hasPicture: true),
		PeerInfo(nickname: "Anna", gender: .female, age: 27, hasPicture: true),
		PeerInfo(nickname: "Ingrid", gender: .female, age: 28, hasPicture: true),
		PeerInfo(nickname: "Sarah", gender: .female, age: 22, hasPicture: true)
	]

	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let ns = InAppNotificationStackViewState()

	let unsplashAuthors = ["Rowan Kyle", "Avdalyan", "Dmitry Vechorko", "Andrei Caliman"]

	ds.peering = true

	var index = 0
	for p in people {
		let peerID = PeerID()
		let dp = ds.addPersona(of: peerID, with: p)
		dp.set(portrait: UIImage(named: "p\((advancing(&index) % 4) + 1)")?.cgImage, hash: Data())
		let bioFormat = bundle.localizedString(forKey: "Photo from Unsplash by %@.", value: nil, table: nil)
		dp.biography = String(format: bioFormat, unsplashAuthors[(index - 1) % 4])
		let sp = ss.demo(peerID)
		sp.pinState = dp.info.nickname == "Sarah" ? .unpinned : .pinMatch
		if sp.pinState == .pinMatch {
			let cp = cs.persona(of: peerID)
			cp.unreadMessages = dp.info.nickname == "Ingrid" ? 1 : 0
			switch dp.info.nickname {
			case "Ingrid":
				cp.insert(messages: [
					demoMessage(sent: false, message: bundle.localizedString(forKey: "Working on it ...", value: nil, table: nil), timestamp: Date().advanced(by: -120))
				], sorted: true)
			case "Anna":
				cp.insert(messages: [
					demoMessage(sent: false, message: bundle.localizedString(forKey: "I'll be there.", value: nil, table: nil), timestamp: Date().advanced(by: -120))
				], sorted: true)
			case "Lea":
				cp.insert(messages: [
					demoMessage(sent: true, message: bundle.localizedString(forKey: "Sounds good, count me in!", value: nil, table: nil), timestamp: Date().advanced(by: -120))
				], sorted: true)
			default:
				break
			}
		} else {
			dp.lastSeen = Date().advanced(by: TimeInterval(-120 * index))
		}
	}

	ds.calculateViewLists()

	return MainView()
		.environmentObject(ds)
		.environmentObject(cs)
		.environmentObject(ss)
		.environmentObject(ns)
		.environment(\.locale, .init(identifier: language))
}

#Preview("App Store Scene 2") {
	// change to desired language
	let language = "en"
	let path = Bundle.main.path(forResource: language, ofType: "lproj")
	let bundle = Bundle(path: path!)!

	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let ns = InAppNotificationStackViewState()

	let peerID = PeerID()
	let p = PeerInfo(nickname: "Sarah", gender: .female, age: 22, hasPicture: true)

	let dp = ds.addPersona(of: peerID, with: p)
	dp.set(portrait: UIImage(named: "p1")?.cgImage, hash: Data())
	let bioFormat = bundle.localizedString(forKey: "Photo from Unsplash by %@.", value: nil, table: nil)
	dp.biography = String(format: bioFormat, "Andrei Caliman")

	let sp = ss.demo(peerID)
	sp.pinState = .pinMatch
	let cp = cs.persona(of: peerID)

	cp.readyToChat = true

	cp.insert(messages: [
		demoMessage(sent: true, message: bundle.localizedString(forKey: "Vicki Vale, Vicki Vale, Vicki Vale, …", value: nil, table: nil), timestamp: Date().advanced(by: 60)),
		demoMessage(sent: false, message: bundle.localizedString(forKey: "I hope I'm not interrupting.", value: nil, table: nil), timestamp: Date()),
		demoMessage(sent: true, message: bundle.localizedString(forKey: "No, not at all.", value: nil, table: nil), timestamp: Date().advanced(by: -60)),
		demoMessage(sent: true, message: bundle.localizedString(forKey: "It’s from Batman.", value: nil, table: nil), timestamp: Date().advanced(by: -120)),
		demoMessage(sent: false, message: bundle.localizedString(forKey: "Because that makes it better.", value: nil, table: nil), timestamp: Date().advanced(by: -240))
	], sorted: true)

	return MainView()
		.environmentObject(ds)
		.environmentObject(cs)
		.environmentObject(ss)
		.environmentObject(ns)
		.environment(\.locale, .init(identifier: language))
}

#Preview("Normal") {
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

	return MainView()
		.environmentObject(ds)
		.environmentObject(cs)
		.environmentObject(ss)
		.environmentObject(ns)
}

#Preview("Onboarding") {
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
