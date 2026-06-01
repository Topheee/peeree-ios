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

	@State private var showingProfile = false
	@State private var showingFilter = false

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	var body: some View {

		NavigationView {
				ScrollView() {
					if chatViewState.matchedPeople.isEmpty {
						OnboardingView(peering: $discoveryViewState.peering)
							.padding(.horizontal)
					}

					BrowseView()

					if !chatViewState.matchedPeople.isEmpty {
						Text("Chats")
							.font(.subheadline).bold()
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding([.leading, .trailing])
					}

					LazyVStack {
						ForEach(chatViewState.matchedPeople, id: \.id) { chatPersona in
							let discoveryPersona = discoveryViewState.persona(of: chatPersona.peerID)
							NavigationLink(tag: chatPersona.peerID, selection: $serverChatViewState.displayedPeerID) {
								ChatView(discoveryPersona: discoveryPersona, chatPersona: chatPersona)
									.addKeyboardVisibilityToEnvironment()
							} label: {
								ChatTableCell(chatPersona: chatPersona, discoveryPersona: discoveryPersona)
									.foregroundColor(Color(.label))
							}
						}
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
					.tint(.accent)
				}

				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						showingFilter.toggle()
					} label: {
						Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
					}
					.tint(.accent)
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
			.sheet(isPresented: $socialViewState.presentRecoveryCode) {
				RecoveryView(mode: .presenting, letters: $socialViewState.recoveryCodeLetters)
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

	let recoveryCode = "B117D2A8-4446-4268-9764-3B2BDD1153F7"

	ss.recoveryCodeLetters = recoveryCode.unicodeScalars.map { String($0) }
	ss.presentRecoveryCode = true

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
		dp.biography = String.localizedStringWithFormat(
			bioFormat, unsplashAuthors[(index - 1) % 4])

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
	dp.set(portrait: UIImage(named: "portrait")?.cgImage, hash: Data())
	let bioFormat = bundle.localizedString(forKey: "Photo from Unsplash by %@.", value: nil, table: nil)
	dp.biography = String.localizedStringWithFormat(
		bioFormat, "Andrei Caliman")

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
