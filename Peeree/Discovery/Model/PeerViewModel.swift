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
		case message
	}

	/// Names of notifications sent by `PeerViewModel`.
	public enum NotificationName: String {
		case verified, verificationFailed
		case pictureLoaded, biographyLoaded
		case messageQueued, messageSent, messageReceived, unreadMessageCountChanged

		func post(_ peerID: PeerID, message: String = "") {
			let userInfo: [AnyHashable : Any]
			if message != "" {
				userInfo = [PeerID.NotificationInfoKey : peerID, NotificationInfoKey.message.rawValue : message]
			} else {
				userInfo = [PeerID.NotificationInfoKey : peerID]
			}
			postAsNotification(object: nil, userInfo: userInfo)
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

	/// Message thread with this peer.
	public private (set) var transcripts: [Transcript]

	/// Amount of messages received, which haven't been seen yet by the user.
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
	public mutating func loaded(portrait: CGImage, hash: Data) {
		cgPicture = portrait
		pictureHash = hash

		post(.pictureLoaded)
	}

	/// Removes the portrait from the UI.
	public mutating func deletePortrait() {
		cgPicture = nil
		pictureHash = nil

		post(.pictureLoaded)
	}

	/// A message was received from this peer.
	public mutating func received(message: String, at date: Date) {
		transcripts.append(Transcript(direction: .receive, message: message, timestamp: date))
		unreadMessages += 1

		post(.messageReceived, message: message)
	}

	/// A message was successfully sent to this peer.
	public mutating func didSend(message: String, at date: Date) {
		transcripts.append(Transcript(direction: .send, message: message, timestamp: date))
		post(.messageSent)
	}

	/// Mass-append messages. Only fires Notifications.unreadMessageCountChanged. Does not produce notifications.
	public mutating func catchUp(messages: [Transcript], unreadCount: Int) {
		transcripts.append(contentsOf: messages)
		unreadMessages = unreadCount
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
	private func post(_ notification: NotificationName, message: String = "") {
		notification.post(peerID, message: message)
	}
}

extension PeerViewModel {
	// MARK: Variables

	public var verificationStatus: String {
		if verified {
			return NSLocalizedString("verified", comment: "Verification status of peer")
		} else {
			return NSLocalizedString("not verified", comment: "Verification status of peer")
		}
	}
}
