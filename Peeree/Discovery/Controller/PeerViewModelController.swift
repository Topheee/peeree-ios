//
//  PeerViewModelController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 23.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// This class is intended for use on the main thread only!
public final class PeerViewModelController {
	// MARK: - Public and Internal

	// MARK: Static Variables

	/// All information available for a PeerID.
	public static private (set) var viewModels = [PeerID : PeerViewModel]()

	/// The `PeeringController.peering` state for the main thread.
	public static var peering: Bool = false

	// MARK: Static Methods

	/// Update or set the view model of `Peer`.
	public static func update(_ peerID: PeerID, info: PeerInfo, lastSeen: Date) {
		viewModels[peerID, default: PeerViewModel(peerID: peerID, info: info, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: lastSeen, cgPicture: nil, pictureHash: nil)].info = info
		viewModels[peerID, default: PeerViewModel(peerID: peerID, info: info, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: lastSeen, cgPicture: nil, pictureHash: nil)].lastSeen = lastSeen
	}

	/// Retrieves the view model of `peerID`; possibly filled with empty data.
	public static func viewModel(of peerID: PeerID) -> PeerViewModel {
		let clos: () -> PeerViewModel = {
			wlog("From somewhere in the code PeerID \(peerID.uuidString) appeared, before it was filled by the Bluetooth application part.")

			let info = PeerInfo(nickname: peerID.uuidString, gender: .queer, age: nil, hasPicture: false)
			return PeerViewModel(peerID: peerID, info: info, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: Date.distantPast, cgPicture: nil)
		}

		return viewModels[peerID, default: clos()]
	}

	/// Makes modifications to the view model of `peerID`.
	public static func modify(peerID: PeerID, modifier: (inout PeerViewModel) -> ()) {
		let clos: () -> PeerViewModel = {
			wlog("From somewhere in the code PeerID \(peerID.uuidString) appeared, before it was filled by the Bluetooth application part.")

			let info = PeerInfo(nickname: peerID.uuidString, gender: .queer, age: nil, hasPicture: false)
			return PeerViewModel(peerID: peerID, info: info, biography: "", transcripts: [], unreadMessages: 0, verified: false, lastSeen: Date.distantPast, cgPicture: nil)
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

	/// Clears all cached transcripts.
	public static func clearTranscripts() {
		viewModels.keys.forEach { peerID in
			viewModels[peerID]?.clearTranscripts()
		}
	}
}
