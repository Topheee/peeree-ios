//
//  PeereeIdentityViewModelController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// This class is intended for use on the main thread only!
public final class PeereeIdentityViewModelController {
	// MARK: - Public and Internal

	// MARK: Static Variables

	/// All information available for a `PeerID`.
	public static private (set) var viewModels = [PeerID : PeereeIdentityViewModel]()

	/// The `PeerID` of the local user, if available.
	public static var userPeerID: PeerID? = nil

	/// Whether the user has create a `PeereeIdentity`.
	public static var accountExists: Bool { return userPeerID != nil }

	/// Hashes of known inappropriate photos.
	public static var objectionableImageHashes = Set<Data>()

	/// Hashes and timestamps of inappropriate content reports.
	public static var pendingObjectionableImageHashes = [Data : Date]()

	// MARK: Static Methods

	/// Sets the view model of `Peer`; does not trigger any notifications.
	public static func insert(model: PeereeIdentityViewModel) {
		viewModels[model.peerID] = model
	}

	/// Makes modifications to the view model of `peerID`, or adds `insert`, if no model is available.
	public static func upsert(peerID: PeerID, insert: @autoclosure () -> PeereeIdentityViewModel, modifier: (inout PeereeIdentityViewModel) -> ()) {
		modifier(&viewModels[peerID, default: insert()])
	}

	/// Retrieves the view model of `peerID`; possibly filled with empty data.
	public static func viewModel(of peerID: PeerID) -> PeereeIdentityViewModel {
		let clos: () -> PeereeIdentityViewModel = {
			wlog("From somewhere in the code PeerID \(peerID.uuidString) appeared, before it was filled by the Account application part.")

			return PeereeIdentityViewModel(id: PeereeIdentity(peerID: peerID, publicKey: bogusKey))
		}

		return viewModels[peerID, default: clos()]
	}

	/// Removes the view model of `peerID`.
	public static func remove(peerID: PeerID) {
		viewModels.removeValue(forKey: peerID)
	}

	/// Removes all view models.
	public static func clear() {
		userPeerID = nil
		viewModels.removeAll()
	}

	/// Retrieves whether the image represented by `imageHash` contains objectionable content to our knowledge.
	public static func classify(imageHash: Data) -> ContentClassification {
		objectionableImageHashes.contains(imageHash) ? .objectionable : (pendingObjectionableImageHashes[imageHash] != nil ? .pending : .none)
	}

	// MARK: - Private

	// MARK: Static Variables

	/// Generates a fake crypto key; using it most likely crashes the app!
	private static var bogusKey: AsymmetricPublicKey {
		return try! KeyPair(label: "PeereeIdentityViewModelController", privateTag: Data(repeating: 42, count: 2), publicTag: Data(repeating: 42, count: 3), type: PeereeIdentity.KeyType, size: PeereeIdentity.KeySize, persistent: false).publicKey
	}
}

extension PeerViewModel {
	/// Objectionable content classification required by the App Store.
	public var pictureClassification: ContentClassification {
		return pictureHash.map { PeereeIdentityViewModelController.classify(imageHash: $0) } ?? .none
	}
}
