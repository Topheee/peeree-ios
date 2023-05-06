//
//  ServerChatViewModelController.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import PeereeCore

/// This class is intended for use on the main thread only!
public final class ServerChatViewModelController: ServerChatConversationDelegate {

	// MARK: - Public and Internal

	// MARK: Static Variables

	/// The singleton instance.
	public static let shared = ServerChatViewModelController()

	/// All information available for a PeerID.
	public private (set) var viewModels = [PeerID : ServerChatViewModel]()

	// MARK: Static Methods

	/// Retrieves the view model of `peerID`; possibly filled with empty data.
	public func viewModel(of peerID: PeerID) -> ServerChatViewModel {
		return viewModels[peerID, default: ServerChatViewModel(peerID: peerID)]
	}

	/// Makes modifications to the view model of `peerID`.
	public func modify(peerID: PeerID, modifier: (inout ServerChatViewModel) -> ()) {
		modifier(&viewModels[peerID, default: ServerChatViewModel(peerID: peerID)])
	}

	/// Removes the view model of `peerID`.
	public func remove(peerID: PeerID) {
		viewModels.removeValue(forKey: peerID)
	}

	/// Removes all view models.
	public func clear() {
		viewModels.removeAll()
	}

	/// Clears all cached transcripts.
	public func clearTranscripts() {
		viewModels.keys.forEach { peerID in
			viewModels[peerID]?.clearTranscripts()
		}
	}

	// MARK: ServerChatConversationDelegate

	public func received(message: String, at: Date, from peerID: PeerID) {
		modify(peerID: peerID) { $0.received(message: message, at: at) }
	}

	public func didSend(message: String, at: Date, to peerID: PeerID) {
		modify(peerID: peerID) { $0.didSend(message: message, at: at) }
	}

	public func catchUp(messages: [Transcript], unreadCount: Int, with peerID: PeerID) {
		modify(peerID: peerID) { $0.catchUp(messages: messages, unreadCount: unreadCount) }
	}
}
