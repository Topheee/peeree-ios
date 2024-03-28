//
//  ChatView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeServerChat
import PeereeDiscovery

struct ChatView: View {
	private static let SceneStorageKeyComposingMessage = "ComposingMessage"

	init(discoveryPersona: DiscoveryPerson, chatPersona: ServerChatPerson) {
		self.peerID = discoveryPersona.peerID
		self.discoveryPersona = discoveryPersona
		self.chatPersona = chatPersona
	}

	init(peerID: PeerID, discoveryViewState: DiscoveryViewState, serverChatViewState: ServerChatViewState) {
		self.init(discoveryPersona: discoveryViewState.persona(of: peerID), chatPersona: serverChatViewState.persona(of: peerID))
	}

	let peerID: PeerID

	@ObservedObject private var discoveryPersona: DiscoveryPerson

	@ObservedObject private var chatPersona: ServerChatPerson

	@SceneStorage(SceneStorageKeyComposingMessage) private var composingMessage: String = ""

	@FocusState private var messageFieldIsFocused: Bool

	@EnvironmentObject private var discoveryViewState: DiscoveryViewState

	@EnvironmentObject private var socialViewState: SocialViewState

	@EnvironmentObject private var inAppNotificationState: InAppNotificationStackViewState

	@EnvironmentObject private var serverChatViewState: ServerChatViewState

	@State private var chatMessageAreaHeight = CGFloat.zero

	var body: some View {
		ZStack(alignment: .bottom) {
			if chatPersona.readyToChat {
				ScrollView() {
					// not state of the art, but it is what it is
					Button("More …") {
						loadOlderMessages()
					}
					.font(.caption)
					LazyVStack {
						ForEach(chatPersona.messagesPerDay) { day in
							Section(day.title) {
								ForEach(day.messages) { message in
									MessageTableCell(message: message)
								}
							}
							.font(.caption)
						}
					}
					.padding(.bottom, chatMessageAreaHeight + 6)
				}
				.modify {
					if #available(iOS 16, *) {
						$0.scrollDismissesKeyboard(.interactively)
					} else {
						$0
					}
				}
				.modify {
					if #available(iOS 17, *) {
						$0.defaultScrollAnchor(.bottom)
					} else {
						$0
					}
				}
				.onTapGesture {
					messageFieldIsFocused.toggle()
				}
			} else {
				VStack {
					Spacer()
					VStack {
						Text(Image(systemName: "exclamationmark.triangle"))
							.font(.title)
						Text("\(discoveryPersona.info.nickname) is not yet ready to chat.")
							.font(.subheadline)
						Text("To ensure the confidentiality of your messages, chat is only available after \(discoveryPersona.info.nickname) opened the app.")
							.font(.caption)
							.padding(.top)
							.padding(.horizontal)
					}
					.padding()
					.background(
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.orange).opacity(0.8)
					)

					Spacer()
				}
			}

			HStack {
				TextField(text: $composingMessage, prompt: Text("Message")) {}
					.focused($messageFieldIsFocused)
					.onSubmit {
						sendMessage()
					}
				Button {
					sendMessage()
				} label: {
					Label("Send", systemImage: composingMessage == "" ? "paperplane" : "paperplane.fill")
						.labelStyle(.iconOnly)
				}
				.disabled(composingMessage == "")
			}
			.disabled(!chatPersona.readyToChat)
			.padding()
			.background(.regularMaterial)
			.overlay(
				GeometryReader { geometry in
					Color.clear
						.onAppear {
							self.chatMessageAreaHeight = geometry.frame(in: .local).size.height
						}
				}
			)
		}
		.toolbar {
			NavigationLink {
				PersonView(socialPersona: socialViewState.persona(of: peerID), discoveryPersona: discoveryPersona)
			} label: {
				discoveryPersona.image
					.resizable()
					.aspectRatio(contentMode: .fit)
					.clipShape(Circle())
					.frame(maxWidth: 88)
			}
		}
		.navigationTitle(discoveryPersona.info.nickname)
		.navigationBarTitleDisplayMode(.inline)
	}

	private func sendMessage() {
		let title = NSLocalizedString("Sending Message Failed", comment: "Title of alert dialog")
		let message = self.composingMessage
		let peerID = self.peerID
		let dvs = self.discoveryViewState
		let nvs = self.inAppNotificationState

		ServerChatFactory.getOrSetupInstance { instanceResult in
			act(on: instanceResult, dvs: dvs, nvs: nvs, localizedErrorTitle: title) { serverChat in
				serverChat.send(message: message, to: peerID) { result in
					act(on: result, dvs: dvs, nvs: nvs, localizedErrorTitle: title) { _ in }
				}
			}
		}

		composingMessage = ""

		// keep the focus on the field
		messageFieldIsFocused = true
	}

	private func loadOlderMessages() {
		ServerChatFactory.chat { sc in
			sc?.fetchMessagesFromStore(peerID: peerID, count: 30)
		}
	}

	/// Declare all messages in this thread as being read.
	private func markRead() {
		let peerID = self.peerID
		ServerChatFactory.chat { sc in
			sc?.set(lastRead: Date(), of: peerID)
		}
	}
}

#Preview {
	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let cvs = ServerChatViewState()

	let discoveryPersona = ds.addPersona(of: PeerID(), with: PeerInfo(nickname: "Sabine", gender: .queer, age: nil, hasPicture: true))
	discoveryPersona.set(portrait: UIImage(named: "p1")?.cgImage, hash: Data())
	discoveryPersona.lastSeen = Date()

	let chatPersona = cs.persona(of: discoveryPersona.peerID)

	chatPersona.readyToChat = true

	chatPersona.insert(messages: [
		demoMessage(sent: true, message: "Hello there!", timestamp: Date().advanced(by: -120)),
		demoMessage(sent: false, message: "General Kenobi.", timestamp: Date().advanced(by: -60)),
		demoMessage(sent: false, message: "It is I, who, with the greatest pleasure of all time.", timestamp: Date())
	], sorted: true)

	return ChatView(peerID: discoveryPersona.peerID, discoveryViewState: ds, serverChatViewState: cs)
		.environmentObject(ss)
		.environmentObject(cvs)
}

#Preview {
	let ds = DiscoveryViewState()
	let cs = ServerChatViewState()
	let ss = SocialViewState()
	let cvs = ServerChatViewState()

	let discoveryPersona = ds.addPersona(of: PeerID(), with: PeerInfo(nickname: "Pia", gender: .queer, age: nil, hasPicture: true))
	discoveryPersona.set(portrait: UIImage(named: "p2")?.cgImage, hash: Data())
	discoveryPersona.lastSeen = Date()

	let chatPersona = cs.persona(of: discoveryPersona.peerID)

	chatPersona.readyToChat = false

	return ChatView(peerID: discoveryPersona.peerID, discoveryViewState: ds, serverChatViewState: cs)
		.environmentObject(ss)
		.environmentObject(cvs)
}
