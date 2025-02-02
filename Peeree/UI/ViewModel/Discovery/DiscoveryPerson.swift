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

	// TODO: shitty performance keeping this for every object
	/// Formatter for `lastSeenText`.
	private let lastSeenFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		// only for screenshots: formatter.locale = Locale(identifier: "en")
		formatter.unitsStyle = .short
		formatter.formattingContext = .standalone
		return formatter
	}()
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

	var genderText: LocalizedStringKey {
		switch info.gender {
		case PeerInfo.Gender.male:
			"Male"
		case PeerInfo.Gender.female:
			"Female"
		case PeerInfo.Gender.queer:
			"Queer"
		}
	}

	/// User-friendly textual representation of the `lastSeen` property.
	var lastSeenText: String {
		let now = Date()
		if now < lastSeen || now.timeIntervalSince1970 - lastSeen.timeIntervalSince1970 < DiscoveryPerson.NowThreshold {
			return NSLocalizedString("now", comment: "Last Seen Text")
		} else {
			return lastSeenFormatter.localizedString(for: lastSeen, relativeTo: now)
		}
	}

	// MARK: - Private

	// MARK: Static Constants

	/// Seconds to disregard when showing `lastSeenText`.
	private static let NowThreshold: TimeInterval = 5.0
}

extension DiscoveryPerson: Hashable {
	public static func == (lhs: DiscoveryPerson, rhs: DiscoveryPerson) -> Bool {
		return lhs.peerID == rhs.peerID
	}


	public func hash(into hasher: inout Hasher) {
		hasher.combine(peerID)
	}
}
