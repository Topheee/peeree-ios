//
//  PeereeIdPTests.swift
//  PeereeIdPTests
//
//  Created by Christopher Kobusch on 25.01.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import Testing
@testable import PeereeIdP

import KeychainWrapper
import PeereeCore

final class DummyAccountViewModelDelegate: AccountViewModelDelegate {
	var userPeerID: PeereeCore.PeerID?

	var accountExists: PeereeCore.RemoteToggle = .off
}

@MainActor
struct PeereeIdPTests {

	/// The number added to the current sequence number after each server chat operation.
	private let privateTag = "PeereeServerAPITests.Identity.Private"
		.data(using: .utf8, allowLossyConversion: true)!

	/// The number added to the current sequence number after each server chat operation.
	private let publicTag = "PeereeServerAPITests.Identity.Public"
		.data(using: .utf8, allowLossyConversion: true)!

	/// The PeerID of the test account in the local database. See `testCreateTestAccount()` on how to obtain this.
	private let peerID = PeerID(uuidString: "DC20BF4B-02BF-4146-A84E-F6D740DBCFDF")!

	/// The key pair of the test account; initialized in `setUp()`.
	private let keyPair: KeyPair

	private let factory = AccountControllerFactory(
		viewModel: DummyAccountViewModelDelegate(), isTest: true)

	init() throws {
		self.keyPair = try KeyPair(privateTag: self.privateTag,
								   publicTag: self.publicTag,
								   algorithm: .ec,
								   size: PeereeIdentity.KeySize,
								   persistent: true)
	}

	@Test func testUnfunctions() async throws {
		#expect(try await factory.use() == nil)
		await #expect(throws: Error.self) {
			try await factory.accessToken()
		}

	}

	@Test func testCreateAccount() async throws {
		let ac = try await factory.createAccount()

		await #expect(throws: Never.self) {
			try await ac.getAccessToken()
		}

		try await ac.deleteAccount()
	}

}
