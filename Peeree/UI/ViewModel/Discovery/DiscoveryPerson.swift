//
//  DiscoveryPerson.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 14.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeDiscovery

/// View model of a person in the discovery module.
class DiscoveryPerson: ObservableObject {

	/// The PeerID identifying this view model.
	let peerID: PeerID

	@Published var info: PeerInfo

	/// Last Bluetooth encounter.
	@Published var lastSeen: Date

	@Published var biography = ""

	@Published var pictureProgress: Double = 0.0

	var isUser = false

	var cgPicture: CGImage?

	private(set) var pictureHash = Data()

	func set(portrait: CGImage?, hash: Data) {
		cgPicture = portrait
		pictureHash = hash
	}

	init(peerID: PeerID, info: PeerInfo, lastSeen: Date) {
		self.peerID = peerID
		self.info = info
		self.lastSeen = lastSeen
	}
}

extension DiscoveryPerson: DiscoveryPersonAspect {

}

extension DiscoveryPerson {

	convenience init(peerID: PeerID, info: PeerInfo, lastSeen: Date, imageName: String = "PortraitPlaceholder") {
		self.init(peerID: peerID, info: info, lastSeen: lastSeen)
		self.cgPicture = UIImage(named: imageName)?.cgImage
	}

	var image: Image {
		if let pic = cgPicture {
			return Image(pic, scale: 1.0, label: Text("A person."))
		} else {
			return Image("PortraitPlaceholder")
		}
	}

	var genderText: String {
		switch info.gender {
		case PeerInfo.Gender.male:
			NSLocalizedString("Male", comment: "Gender")
		case PeerInfo.Gender.female:
			NSLocalizedString("Female", comment: "Gender")
		case PeerInfo.Gender.queer:
			NSLocalizedString("Queer", comment: "Gender")
		}
	}

	/// User-friendly textual representation of the `lastSeen` property.
	var lastSeenText: String {
		let now = Date()
		if now < lastSeen || now.timeIntervalSince1970 - lastSeen.timeIntervalSince1970 < DiscoveryPerson.NowThreshold {
			return NSLocalizedString("now", comment: "Last Seen Text")
		} else {
			if #available(iOS 13, macOS 10.15, *) {
				return DiscoveryPerson.lastSeenFormatter2.localizedString(for: lastSeen, relativeTo: now)
			} else {
				return DiscoveryPerson.lastSeenFormatter.string(from: lastSeen, to: now) ?? "⏱"
			}
		}
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
}

extension DiscoveryPerson: Hashable {
	public static func == (lhs: DiscoveryPerson, rhs: DiscoveryPerson) -> Bool {
		return lhs.peerID == rhs.peerID
	}


	public func hash(into hasher: inout Hasher) {
		hasher.combine(peerID)
	}
}
