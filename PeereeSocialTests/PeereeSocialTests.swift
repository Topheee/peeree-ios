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

struct DummyAuthenticator: PeereeCore.Authenticator {
	func accessToken() async throws -> String {
		return ""
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

final class DummySocialViewModelDelegate: SocialViewModelDelegate {
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

@MainActor
struct PeereeSocialTests {

	let socialController = SocialNetworkController(
		authenticator: DummyAuthenticator(),
		viewModel: DummySocialViewModelDelegate())

	@Test func testUnpinnedPeersEmpty() async throws {
		let emptySet = await socialController.unpinnedPeers([PeereeIdentity(
			peerID: PeerID(), publicKeyData: Data())])
		#expect(emptySet.isEmpty)
	}

}
