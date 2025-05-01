//
//  PeereeSocialTests.swift
//  PeereeSocialTests
//
//  Created by Christopher Kobusch on 25.01.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import Testing
@testable import PeereeSocial

import PeereeCore
import PeereeIdP

import KeychainWrapper

struct DummyAuthenticator: PeereeCore.Authenticator {
	func accessToken() async throws -> PeereeCore.AccessTokenData {
		return .init(accessToken: "", expiresAt: Date())
	}
}

final class SocialPerson: ObservableObject {

	/// The PeerID identifying this view model.
	public let peerID: PeerID

	@Published
	public var pinState: PinState

	init(peerID: PeerID, pinState: PinState = .unpinned) {
		self.peerID = peerID
		self.pinState = pinState
	}
}

extension SocialPerson: SocialPersonAspect {}

final class MockSocialViewModelDelegate: SocialViewModelDelegate {
	func addPersona(of peerID: PeereeCore.PeerID, with data: PeereeSocial.PinState) -> SocialPerson {
		let result = SocialPerson(peerID: peerID, pinState: data)
		people[peerID] = result
		return result
	}
	
	func persona(of peerID: PeereeCore.PeerID) -> SocialPerson {
		return people[peerID] ?? addPersona(of: peerID, with: .unpinned)
	}
	
	private(set) var people: [PeerID : SocialPerson] = [:]

	/// Social personas must have a `PinState`.
	typealias RequiredData = PinState
	
	var userPeerID: PeereeCore.PeerID?

	var accountExists: PeereeCore.RemoteToggle = .off

	var objectionableImageHashes: Set<Data> = []

	var pendingObjectionableImageHashes: [Data : Date] = [:]

	func removePersona(of peerID: PeereeCore.PeerID) {
		// noop
	}

	func clear() {
		// noop
	}
}

final class MockAccountViewModelDelegate: AccountViewModelDelegate {
	var userPeerID: PeereeCore.PeerID?

	var accountExists: PeereeCore.RemoteToggle = .off
}

@MainActor
final class IdentityHolder {

	/// The identifier in the Keychain for the test private key.
	private let privateTag = "PeereeSocialTests.\(UUID().uuidString)"
		.data(using: .utf8, allowLossyConversion: true)!

	/// A freshly created account per test.
	private let peerID = PeerID()

	/// The key pair of the test account; initialized in `setUp()`.
	private let keyPair: KeyPair

	let factory = AccountControllerFactory(
		viewModel: MockAccountViewModelDelegate(), isTest: true)

	let accountController: AccountController

	let chatAccount: ChatAccount

	init() async throws {
		self.keyPair = try KeyPair(
			tag: self.privateTag, algorithm: .ec, size: PeereeIdentity.KeySize)

		let result = try await factory.createOrRecoverAccount(using: nil)

		self.accountController = result.0
		self.chatAccount = result.1
	}

	deinit {
		try? self.keyPair.removeFromKeychain()
	}
}

@MainActor
@Suite(.serialized) struct PeereeSocialTests : ~Copyable {

	private let identityHolder: IdentityHolder

	private let mockViewModel = MockSocialViewModelDelegate()

	private let socialController: SocialNetworkController

	init() async throws {

		self.identityHolder = try await IdentityHolder()

		self.socialController = SocialNetworkController(
			authenticator: identityHolder.factory,
			viewModel: mockViewModel, isTest: true)
	}

	@Test func testUnpinnedPeersEmpty() async throws {
		let emptySet = await socialController.unpinnedPeers([PeereeIdentity(
			peerID: PeerID(), publicKeyData: Data())])
		#expect(!emptySet.isEmpty)
	}

	@Test func matchesInitiallyEmpty() async throws {
		let emptySet = await socialController.pinMatches
		#expect(emptySet.isEmpty)
	}

	@Test func unknownPeer() async throws {
		await #expect(throws: Error.self) {
			try await socialController.id(of: PeerID())
		}
	}

	@Test func unknownPeerPinned() async throws {
		let unknownID = PeereeIdentity(peerID: PeerID(), publicKeyData: Data())
		#expect(await socialController.isPinned(unknownID) == false)
	}

	@Test func unknownPeerPinning() async throws {
		#expect(await socialController.isPinning(PeerID()) == false)
	}

	@Test func pinNewPeer() async throws {
		let newID = PeereeIdentity(peerID: PeerID(), publicKeyData: Data())

		try await socialController.pin(newID)

		#expect(mockViewModel.people[newID.peerID]?.pinState == .pinned)
	}
}
