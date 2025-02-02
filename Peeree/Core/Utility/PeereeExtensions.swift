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

extension Notification.Name {
	/// Post a notification and add `PeerID.NotificationInfoKey`
	/// with value `peerID` to the `userInfo`.
	public func post(for peerID: PeerID,
					 on object: (any AnyObject & Sendable)? = nil,
					 userInfo: [AnyHashable : Any]? = nil) {
		if let ui = userInfo {
			self.post(on: object, userInfo: ui
				.merging([PeerID.NotificationInfoKey : peerID]) { a, _ in a })
		} else {
			self.post(on: object, userInfo: userInfo)
		}
	}

	/// Observes for new notifications regarding peers on the `default`
	/// `NotificationCenter`.
	@available(iOS 15, *)
	public func observe<Transformed>(
		transform: @escaping @Sendable (Notification) async -> Transformed
	) -> AsyncCompactMapSequence<NotificationCenter.Notifications,
								 (PeerID, Transformed)> {

		return NotificationCenter.`default`.notifications(named: self)
			.compactMap { notification in
			guard let peerID = notification
				.userInfo?[PeerID.NotificationInfoKey] as? PeerID else {
				return nil
			}
			return (peerID, await transform(notification))
		}
	}

	/// Observes for new notifications regarding specific peers on the `default`
	/// `NotificationCenter`.
	@available(iOS 15, *)
	public func observePeer<Transformed>(
		with peerID: PeerID,
		transform: @escaping @Sendable (Notification) async -> Transformed
	) -> AsyncCompactMapSequence<NotificationCenter.Notifications,
								 Transformed> {

		return NotificationCenter.`default`.notifications(named: self)
			.compactMap { notification in
			guard let pID = notification
				.userInfo?[PeerID.NotificationInfoKey] as? PeerID,
				peerID == pID else {
				return nil
			}
			return await transform(notification)
		}
	}

}
