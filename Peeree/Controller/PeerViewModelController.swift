//
//  PeerViewModelController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// This class is intended for use on the main thread only!
public class PeerViewModelController {
	// MARK: - Public and Internal

	// MARK: Static Variables

	/// All information available for a PeerID.
	public static private (set) var viewModels = [PeerID : PeerViewModel]()

	// MARK: Static Methods

	/// Update or set the view model of `Peer`.
	public static func update(peer: Peer, lastSeen: Date) {
		viewModels[peer.id.peerID, default: PeerViewModel(peer: peer, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: lastSeen, cgPicture: nil, pictureClassification: .none, pictureHash: nil)].peer = peer
		viewModels[peer.id.peerID, default: PeerViewModel(peer: peer, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: lastSeen, cgPicture: nil, pictureClassification: .none, pictureHash: nil)].lastSeen = lastSeen
	}

	/// Retrieves the view model of `peerID`; possibly filled with empty data.
	public static func viewModel(of peerID: PeerID) -> PeerViewModel {
		let clos: () -> PeerViewModel = {
			NSLog("WRN: From somewhere in the code PeerID \(peerID.uuidString) appeared, before it was filled by the Bluetooth application part.")

			let peer = Peer(peerID: peerID, publicKey: bogusKey, nickname: peerID.uuidString, gender: .queer, age: nil, hasPicture: false)
			return PeerViewModel(isAvailable: false, peer: peer, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: Date.distantPast, cgPicture: nil, pictureClassification: .none)
		}

		return viewModels[peerID, default: clos()]
	}

	/// Makes modifications to the view model of `peerID`.
	public static func modify(peerID: PeerID, modifier: (inout PeerViewModel) -> ()) {
		let clos: () -> PeerViewModel = {
			NSLog("WRN: From somewhere in the code PeerID \(peerID.uuidString) appeared, before it was filled by the Bluetooth application part.")

			let peer = Peer(peerID: peerID, publicKey: bogusKey, nickname: peerID.uuidString, gender: .queer, age: nil, hasPicture: false)
			return PeerViewModel(isAvailable: false, peer: peer, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: Date.distantPast, cgPicture: nil, pictureClassification: .none)
		}

		modifier(&viewModels[peerID, default: clos()])
	}

	/// Removes the view model of `peerID`.
	public static func remove(peerID: PeerID) {
		viewModels.removeValue(forKey: peerID)
	}

	/// Removes all view models.
	public static func clear() {
		viewModels.removeAll()
	}

	// MARK: - Private

	// MARK: Static Variables

	/// Generates a fake crypto key; probably crashes!
	private static var bogusKey: AsymmetricPublicKey {
		return try! KeyPair(label: "PeerViewModelController", privateTag: Data(repeating: 42, count: 2), publicTag: Data(repeating: 42, count: 3), type: PeereeIdentity.KeyType, size: PeereeIdentity.KeySize, persistent: false).publicKey
	}
}
