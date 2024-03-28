//
//  SocialViewModelDelegate.swift
//  PeereeServer
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import KeychainWrapper

import PeereeCore

/// Interface between the social module and the UI.
@MainActor
public protocol SocialViewModelDelegate: PersonAspectState where Aspect: SocialPersonAspect, RequiredData == PinState {

	var userPeerID: PeerID? { get set }

	/// Hashes of known inappropriate photos.
	var objectionableImageHashes: Set<Data> { get set }

	/// Hashes and timestamps of inappropriate content reports.
	var pendingObjectionableImageHashes: [Data : Date] { get set }
}

