//
//  PeerViewModel.swift
//  Peeree
//
//  Created by Christopher Kobusch on 22.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

/// Holds current information of a peer to be used in the UI. Thus, all variables and methods must be accessed from main thread!
public struct PeerViewModel {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	/// Keys in the `userInfo` dict of a notification.
	public enum NotificationInfoKey: String {
		case peerID
	}

	/// Names of notifications sent by `PeerViewModel`.
	public enum NotificationName: String {
		case verified, verificationFailed
		case pictureLoaded, biographyLoaded
		case messageQueued, messageSent, messageReceived, unreadMessageCountChanged

		func post(_ peerID: PeerID) {
			postAsNotification(object: nil, userInfo: [NotificationInfoKey.peerID.rawValue : peerID])
		}
	}

	/// Reduced states of the pinning progress.
	public enum PinState {
		case pinned, pinning, notPinned
	}

	// MARK: Variables

	/// Whether this peer is currently connected via Bluetooth.
	public var isAvailable = false

	/// All mandatory information of the peer.
	public var peer: Peer

	/// Optional self-description of the peer.
	public var biography: String {
		didSet {
			guard oldValue != biography else { return }
			post(.biographyLoaded)
		}
	}

	/// Message thread with this peer.
	public private (set) var transcripts: [Transcript]

	public var unreadMessages: Int {
		didSet {
			guard oldValue != unreadMessages else { return }
			post(.unreadMessageCountChanged)
		}
	}

	/// Whether this peer showed that he in fact is the owner of the PeerID.
	public var verified: Bool {
		didSet {
			guard oldValue != verified else { return }
			if verified {
				post(.verified)
			} else {
				post(.verificationFailed)
			}
		}
	}

	/// Last Bluetooth encounter.
	public var lastSeen: Date

	/// Portrait image.
	public private (set) var cgPicture: CGImage?

	/// Objectionable content classification required by the App Store.
	public var pictureClassification: AccountController.ContentClassification

	/// SHA-256 hash of the image used for objectionable content classification.
	public private (set) var pictureHash: Data? = nil

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
	public mutating func loadedAndClassified(portrait: CGImage, hash: Data, classification: AccountController.ContentClassification) {
		cgPicture = portrait
		pictureHash = hash
		pictureClassification = classification

		post(.pictureLoaded)
	}

	/// Removes the portrait from the UI.
	public mutating func deletePortrait() {
		cgPicture = nil
		pictureHash = nil
		pictureClassification = .none

		post(.pictureLoaded)
	}

	/// A message was received from this peer.
	public mutating func received(message: String, at date: Date) {
		guard pinState == .pinned else { return }

		transcripts.append(Transcript(direction: .receive, message: message, timestamp: date))
		unreadMessages += 1

		post(.messageReceived)
	}

	/// A message was successfully sent to this peer.
	public mutating func didSend(message: String, at date: Date) {
		transcripts.append(Transcript(direction: .send, message: message, timestamp: date))
		post(.messageSent)
	}

	/// Mass-append messages. Only fires Notifications.unreadMessageCountChanged. Does not produce notifications.
	public mutating func catchUp(messages: [Transcript]) {
		transcripts.append(contentsOf: messages)
		post(.unreadMessageCountChanged)
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

extension PeerViewModel {
	// MARK: Variables

	/// Shortcut for `peer.id.peerID`.
	public var peerID: PeerID { return peer.id.peerID }

	/// Whether this is the model of the user's info.
	public var isLocalPeer: Bool { return self.peerID == AccountController.shared.peerID }

	/// State of the pinning progress.
	public var pinState: PinState {
		if peer.id.pinned {
			return .pinned
		} else {
			return AccountController.shared.isPinning(peerID) ? .pinning : .notPinned
		}
	}

	public var verificationStatus: String {
		if verified {
			return NSLocalizedString("verified", comment: "Verification status of peer")
		} else {
			return NSLocalizedString("not verified", comment: "Verification status of peer")
		}
	}
}
