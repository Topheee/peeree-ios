//
//  PeereeDiscoveryTests.swift
//  PeereeDiscoveryTests
//
//  Created by Christopher Kobusch on 11.05.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform Dependencies
import Testing

// Internal Dependencies
@testable import PeereeDiscovery

private func randomFile() -> String {
	return "PersistedPeersControllerTests.\(UUID().uuidString)"
}

struct PersistedPeersControllerTests {
	/// Test empty peer sets.
	@Test func empty() async throws {
		let subject = PersistedPeersController(filename: randomFile())

		defer { Task { await subject.clear() } }

		await #expect(subject.persistedPeers.isEmpty)

		await subject.clear()

		await #expect(subject.persistedPeers.isEmpty)

		let initialData = try await subject.loadInitialData()

		#expect(initialData.isEmpty)

		await subject.clear()

		await #expect(subject.persistedPeers.isEmpty)
	}

	/// Test adding peers.
	@Test func addPeers() async throws {
		let subject = PersistedPeersController(filename: randomFile())

		defer { Task { await subject.clear() } }

		let peer1: Peer = .init(
			id: .init(peerID: UUID(), publicKeyData: Data()),
			info: .init(
				nickname: "String", gender: .queer, age: nil, hasPicture: false
			))

		try await subject.addPeers(Set([peer1]))

		await #expect(!subject.persistedPeers.isEmpty)

		let outPeer1 = try await #require(subject.persistedPeers.first)

		#expect(outPeer1 == peer1)
	}

	/// Test adding and removing peers.
	@Test func addRemovePeers() async throws {
		let subject = PersistedPeersController(filename: randomFile())

		defer { Task { await subject.clear() } }

		let peer1: Peer = .init(
			id: .init(peerID: UUID(), publicKeyData: Data()),
			info: .init(
				nickname: "String", gender: .queer, age: nil, hasPicture: false
			))

		try await subject.addPeers(Set([peer1]))

		await #expect(!subject.persistedPeers.isEmpty)

		try await subject.removePeers([peer1])

		await #expect(subject.persistedPeers.isEmpty)
	}

	/// Test adding and removing peers.
	@Test func loadBlob() async throws {
		let subject = PersistedPeersController(filename: randomFile())

		defer { Task { await subject.clear() } }

		let peer1: Peer = .init(
			id: .init(peerID: UUID(), publicKeyData: Data()),
			info: .init(
				nickname: "String", gender: .queer, age: nil, hasPicture: false
			))

		try await subject.addPeers(Set([peer1]))

		await #expect(subject.loadBlob(of: peer1.id.peerID) == nil)

//		subject.modify(peerID: peer1.id.peerID) { mPeer in
//			let p = try #require(mPeer)
//		}
	}
}
