//
//  PeereeIdPTests.swift
//  PeereeIdPTests
//
//  Created by Christopher Kobusch on 25.01.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

import Testing
@testable import PeereeIdP

import PeereeCore

final class MockAccountViewModelDelegate: AccountViewModelDelegate {
	var userPeerID: PeereeCore.PeerID?

	var accountExists: PeereeCore.RemoteToggle = .off
}

/// Our underlying Keychain wrapper is shared, so we can't run tests in parallel with different accounts.
@Suite(.serialized) struct IdPTestSuite {

	@MainActor @Suite(.serialized)
	struct AccountTests {

		/// The identifier in the Keychain for the test private key.
		private let privateTag = "PeereeSocialTests.AccountTests.\(UUID().uuidString)"

		private let viewModelDelegate: MockAccountViewModelDelegate = .init()

		private let factory: AccountControllerFactory

		init() throws {
			self.factory = AccountControllerFactory(
				config: .testing(.init(privateKeyTag: self.privateTag)),
				viewModel: viewModelDelegate)
		}

		@Test func testCreateDeleteAccount() async throws {
			let (ac, ca) = try await self.factory
				.createOrRecoverAccount(using: nil)

			defer {
				Task { await ac.clearLocalData() }
				sleep(1)
			}

			#expect(ca.userID != "")
			#expect(ca.accessToken != "")
			#expect(ca.homeServer != "")
			#expect(ca.deviceID != "")
			#expect(ca.initialPassword != "")

			let up = self.viewModelDelegate.userPeerID
			let acPeerID = await ac.peerID

			#expect(viewModelDelegate.accountExists == .on)
			#expect(up == acPeerID)

			await #expect(throws: Never.self) {
				try await ac.getAccessToken()
			}

			await #expect(throws: Never.self) {
				try await ac.getIdentityToken(of: ac.peerID)
			}

			try await self.factory.deleteAccount()

			#expect(self.viewModelDelegate.accountExists == .off)
			#expect(self.viewModelDelegate.userPeerID == nil)
		}
	}

	@MainActor @Suite(.serialized)
	final class IdPTests {

		/// The identifier in the Keychain for the test private key.
		private let privateTag = "PeereeSocialTests.IdPTests.\(UUID().uuidString)"

		private let viewModelDelegate: MockAccountViewModelDelegate = .init()

		private let factory: AccountControllerFactory

		private let accountController: AccountController

		init() async throws {
			self.factory = AccountControllerFactory(
				config: .testing(.init(privateKeyTag: self.privateTag)),
				viewModel: viewModelDelegate)

			let (ac, _) = try await self.factory.createOrRecoverAccount(using: nil)
			self.accountController = ac
		}

		deinit {
			let f = self.factory
			let ac = self.accountController

			Task {
				try? await f.deleteAccount()
				await ac.clearLocalData()
			}

			sleep(2)
		}

		@Test func testAccessToken() async throws {
			let at = try await self.accountController.getAccessToken()

			#expect(!at.isEmpty)
		}

		@Test func testAccessTokenContent() async throws {
			let accessTokenData = try await self.factory.accessToken()

			#expect(!accessTokenData.accessToken.isEmpty)
			#expect(accessTokenData.expiresAt > Date())
		}
	}
}
