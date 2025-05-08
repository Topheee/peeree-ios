//
//  PeereeChatTests.swift
//  PeereeChatTests
//
//  Created by Christopher Kobusch on 03.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import Testing
@testable import PeereeServerChat

import PeereeCore
import PeereeIdP

private final class ServerChatDataSourceMock: ServerChatDataSource {
	func hasPinMatch(with peerID: PeereeCore.PeerID, forceCheck: Bool) async throws -> Bool {
		// shoulda do somin
		return false
	}
	
	func pinMatches() async -> Set<PeereeCore.PeerID> {
		// shoulda do somin
		return []
	}
	
}

private final class MockAccountViewModelDelegate: AccountViewModelDelegate {
	var userPeerID: PeereeCore.PeerID?

	var accountExists: PeereeCore.RemoteToggle = .off
}

/// View model of a person in the server chat module.
final class ServerChatPerson: ServerChatPersonAspect {
	func insert(messages: [PeereeServerChat.ChatMessage], sorted: Bool) {
		// shoulda do somin
	}
	
	func set(lastReadDate: Date) {
		// shoulda do somin
	}
	
	init(peerID: PeerID) {
		self.peerID = peerID
	}

	public let peerID: PeerID

	public var readyToChat: Bool = false

	public var unreadMessages: Int = 0

	public var technicalInfo: String = ""

	public var roomError: Error?

	/// Chronological message thread with this peer.
	public private(set) var messagesPerDay = [ChatDay]()
}

final class MockServerChatViewModelDelegate: ServerChatViewModelDelegate {

	/// Single source of truth of domain data.
	var people = [PeerID : ServerChatPerson]()

	/// Register a new person.
	func addPersona(of peerID: PeerID, with data: Void) -> ServerChatPerson {
		if let result = self.people[peerID] { return result }
		let result = ServerChatPerson(peerID: peerID)
		self.people[peerID] = result
		return result
	}

	/// Retrieve a person.
	func persona(of peerID: PeerID) -> ServerChatPerson {
		self.addPersona(of: peerID, with: ())
	}

	/// Removes the view model of `peerID`.
	func removePersona(of peerID: PeerID) {
		// shoulda do somin
	}

	/// Removes all view models.
	func clear() {
		// shoulda do somin
	}

	func new(
		message: PeereeServerChat.ChatMessage,
		inChatWithConversationPartner peerID: PeereeCore.PeerID) {
		// shoulda do somin
	}

	func catchUp(
		messages: [PeereeServerChat.ChatMessage], sorted: Bool,
		unreadCount: Int, with peerID: PeereeCore.PeerID) {
		// shoulda do somin
	}
}

final class MockServerChatDelegate: ServerChatDelegate {
	func configurePusherFailed(_ error: any Error) async {
		// shoulda do somin
	}
	
	func cannotJoinRoom(_ error: any Error) async {
		// shoulda do somin
	}
	
	func serverChatCertificateIsInvalid() async {
		// shoulda do somin
	}
	
	func serverChatClosed(error: (any Error)?) async {
		// shoulda do somin
	}
	
	func serverChatInternalErrorOccured(_ error: any Error) async {
		// shoulda do somin
	}
	
	func decodingPersistedChatDataFailed(with error: any Error) async {
		// shoulda do somin
	}
	
	func encodingPersistedChatDataFailed(with error: any Error) async {
		// shoulda do somin
	}
}

@MainActor
@Suite(.serialized) struct PeereeChatAccountTests {

	/// The identifier in the Keychain for the test private key.
	private let privateTag = "PeereeChatAccountTests.\(UUID().uuidString)"

	private let viewModelMock = MockServerChatViewModelDelegate()

	private let delegateMock = MockServerChatDelegate()

	@Test func createDeleteAccount() async throws {
		let factory = AccountControllerFactory(
			config: .testing(.init(privateKeyTag: self.privateTag)),
			viewModel: MockAccountViewModelDelegate())

		let (ac, ca) = try await factory.createOrRecoverAccount(using: nil)

		#expect(ca.initialPassword != "")
		#expect(ca.homeServer != "")
		#expect(ca.accessToken != "")
		#expect(ca.deviceID != "")
		#expect(ca.userID != "")

		let sca = ServerChatAccount(
			userID: ca.userID, accessToken: ca.accessToken,
			homeServer: ca.homeServer, deviceID: ca.deviceID,
			initialPassword: ca.initialPassword)

		let scFactory = try await ServerChatFactory(
			account: sca, ourPeerID: ac.peerID, delegate: self.delegateMock,
			conversationDelegate: self.viewModelMock)

		// we need to call use() to initiate the ServerChatController
		// TODO: refactor s.t. this is not longer necessary

		let _ = try await scFactory.use(with: ServerChatDataSourceMock())

		try await scFactory.deleteAccount()
	}

//	@Test func logoutLogin() async throws {
//		let factory = AccountControllerFactory(
//			config: .testing(.init(privateKeyTag: self.privateTag)),
//			viewModel: MockAccountViewModelDelegate())
//
//		let (ac, ca) = try await factory.createOrRecoverAccount(using: nil)
//
//		#expect(ca.initialPassword != "")
//		#expect(ca.homeServer != "")
//		#expect(ca.accessToken != "")
//		#expect(ca.deviceID != "")
//		#expect(ca.userID != "")
//
//		let sca = ServerChatAccount(
//			userID: ca.userID, accessToken: ca.accessToken,
//			homeServer: ca.homeServer, deviceID: ca.deviceID,
//			initialPassword: ca.initialPassword)
//
//		let scFactory = try await ServerChatFactory(
//			account: sca, ourPeerID: ac.peerID, delegate: self.delegateMock,
//			conversationDelegate: self.viewModelMock)
//
//		let scc = try await scFactory.use(with: <#T##any ServerChatDataSource#>)
//
//		try await scc.logout()
//	}

}
