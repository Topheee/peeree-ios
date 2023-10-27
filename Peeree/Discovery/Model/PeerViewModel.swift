//
//  PeerViewModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 22.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics
import PeereeCore
import CSProgress

/// Holds current information of a peer to be used in the UI.
@MainActor
public struct PeerViewModel {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	/// Names of notifications sent by `PeerViewModel`.
	public enum NotificationName: String {
		case pictureLoadBegan, pictureLoaded, biographyLoaded

		func post(_ peerID: PeerID) {
			postAsNotification(object: nil, userInfo: [PeerID.NotificationInfoKey : peerID])
		}
	}

	// MARK: Constants

	/// The PeerID identifying this view model.
	public let peerID: PeerID

	// MARK: Variables

	/// Whether this peer is currently connected via Bluetooth.
	public var isAvailable = false

	/// All mandatory information of the peer.
	public var info: PeerInfo

	/// Optional self-description of the peer.
	public var biography: String {
		didSet {
			guard oldValue != biography else { return }
			post(.biographyLoaded)
		}
	}

	/// Last Bluetooth encounter.
	public var lastSeen: Date

	/// Portrait image.
	public private (set) var cgPicture: CGImage?

	/// SHA-256 hash of the image used for objectionable content classification.
	public private (set) var pictureHash: Data? = nil

	/// The progress of portait transmission, if any.
	public var pictureProgress: CSProgress? {
		didSet {
			if pictureProgress != nil { self.post(.pictureLoadBegan) }
		}
	}

	/// User-friendly textual representation of the `lastSeen` property.
	public var lastSeenText: String {
		let now = Date()
		if now < lastSeen || now.timeIntervalSince1970 - lastSeen.timeIntervalSince1970 < PeerViewModel.NowThreshold {
			return NSLocalizedString("now", comment: "Last Seen Text")
		} else {
			if #available(iOS 13, macOS 10.15, *) {
				return PeerViewModel.lastSeenFormatter2.localizedString(for: lastSeen, relativeTo: now)
			} else {
				return PeerViewModel.lastSeenFormatter.string(from: lastSeen, to: now) ?? "⏱"
			}
		}
	}

	// MARK: Methods

	/// The `portrait` of this peer was retrieved and checked against objectionable content hash list.
	public mutating func loaded(portrait: CGImage, hash: Data) {
		cgPicture = portrait
		pictureHash = hash
		pictureProgress = nil

		post(.pictureLoaded)
	}

	/// Removes the portrait from the UI.
	public mutating func deletePortrait() {
		cgPicture = nil
		pictureHash = nil

		post(.pictureLoaded)
	}

	// MARK: - Private

	// MARK: Static Constants

	/// Seconds to disregard when showing `lastSeenText`.
	private static let NowThreshold: TimeInterval = 5.0

	/// Formatter for `lastSeenText`.
	private static let lastSeenFormatter: DateComponentsFormatter = {
		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .brief
		formatter.allowedUnits = [.hour, .minute]
		formatter.allowsFractionalUnits = true
		formatter.includesApproximationPhrase = true
		formatter.maximumUnitCount = 1
		formatter.formattingContext = .standalone
		return formatter
	}()

	/// Formatter for `lastSeenText`.
	@available(iOS 13.0, macOS 10.15, *)
	private static let lastSeenFormatter2: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .short
		formatter.formattingContext = .standalone
		return formatter
	}()

	// MARK: Methods

	/// Shortcut.
	private func post(_ notification: NotificationName) {
		notification.post(peerID)
	}
}
