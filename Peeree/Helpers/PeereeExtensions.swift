//
//  PeereeExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import Foundation

/// The main bundle's identifier.
public let BundleID = Bundle.main.bundleIdentifier ?? "de.peeree"

/// The datatype for the identifier of people on the Peeree network.
public typealias PeerID = UUID

extension PeerID {
	/// Key in the `userInfo` dictionary of `Notification`.
	public static let NotificationInfoKey = "peerID"

	/// The encoding to use when serializing PeerIDs.
	private static let uuidEncoding = String.Encoding.ascii

	/// De-serializes from a String-encoded UUID.
	public init?(data: Data) {
		guard let string = String(data: data, encoding: PeerID.uuidEncoding) else {
			assertionFailure()
			return nil
		}
		self.init(uuidString: string)
	}

	/// Serializes to a String-encoded UUID.
	public func encode() -> Data {
		return uuidString.data(using: PeerID.uuidEncoding)!
	}
}

extension RawRepresentable where Self.RawValue == String {
	/// Post a notification on the main thread and add `PeerID.NotificationInfoKey` with value `peerID` to the `userInfo`.
	public func post(for peerID: PeerID, userInfo: [AnyHashable : Any]? = nil) {
		if let ui = userInfo {
			postAsNotification(object: nil, userInfo: ui.merging([PeerID.NotificationInfoKey : peerID]) { a, _ in a })
		} else {
			postAsNotification(object: nil, userInfo: [PeerID.NotificationInfoKey : peerID])
		}
	}

	/// Observes notifications with a `name` equal to the `rawValue` of this notification and extracts the `PeerID` from any notification before calling `block`.
	public func addAnyPeerObserver(peerIDKey: String = "peerID", _ block: @escaping (PeerID, Notification) -> Void) -> NSObjectProtocol {
		return NotificationCenter.addObserverOnMain(self.rawValue) { (notification) in
			if let peerID = notification.userInfo?[peerIDKey] as? PeerID {
				block(peerID, notification)
			}
		}
	}

	/// Observes notifications with a `name` equal to the `rawValue` of this notification and the value of the entry with key `peerIDKey` equal to `observedPeerID`.
	public func addPeerObserver(for observedPeerID: PeerID, _ block: @escaping @MainActor (Notification) -> Void) -> NSObjectProtocol {
		return NotificationCenter.addObserverOnMain(self.rawValue) { (notification) in
			if let peerID = notification.userInfo?[PeerID.NotificationInfoKey] as? PeerID, observedPeerID == peerID {
				block(notification)
			}
		}
	}
}
