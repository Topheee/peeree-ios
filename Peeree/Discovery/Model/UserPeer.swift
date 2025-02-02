//
//  UserPeer.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import UIKit
import CoreGraphics

import PeereeCore
import PeereeDiscovery

struct ProfileData {

	var peerInfo: PeerInfo?

	var picture: UIImage?

	var biography: String

	var birthday: Date?
}

/// Names of notifications sent by ``UserPeer``.
extension Notification.Name {

	/// One of the properties of UserPeer's ``PeerInfo`` changed.
	static let userPeerChanged = Notification.Name("de.peeree.userPeerChanged")
}

// Note: This actor could still has a race condition, since the file system is a shared domain, and if multiple instances of this actor are created, they may access the file system simultaneously. However, the FileManager docs state that its shared object is thread-safe.

/// Serializes the profile information of the user.
final actor UserPeer {
	// MARK: - Public and Internal

	// MARK: Static Variables

	/// The URL of the user's picture.
	static var pictureResourceURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent(UserPeer.PortraitFileName, isDirectory: false)
	}

	// MARK: Methods

	/// Persists `peerInfo`; call only from `queue`.
	func modify(peerInfo: PeerInfo?) {
		defer {
			Notification.Name.userPeerChanged.post(on: self)
		}

		guard let info = peerInfo else {
			UserDefaults.standard.removeObject(forKey: UserPeer.PrefKey)
			return
		}
		do {
			try archiveInUserDefs(info, forKey: UserPeer.PrefKey)
		} catch let error {
			flog(Self.LogTag, "could not persist UserPeer: \(error.localizedDescription)")
		}
	}

	/// Sets the user's portrait.
	func modify(portrait: CGImage?) throws {
		defer {
			Notification.Name.userPeerChanged.post(on: self)
		}

		if let pic = portrait {
			try pic.save(to: UserPeer.pictureResourceURL, compressionQuality: StandardPortraitCompressionQuality)
		} else {
			try FileManager.default.deleteFile(at: UserPeer.pictureResourceURL)
		}
	}

	/// Sets the user's birthday.
	func modify(birthday: Date?) {
		defer {
			Notification.Name.userPeerChanged.post(on: self)
		}

		if let birth = birthday {
			UserDefaults.standard.set(birth.timeIntervalSince1970, forKey: UserPeer.DateOfBirthKey)
		} else {
			UserDefaults.standard.removeObject(forKey: UserPeer.DateOfBirthKey)
		}
	}

	/// Sets the user's biography.
	func modify(biography: String) {
		defer {
			Notification.Name.userPeerChanged.post(on: self)
		}

		UserDefaults.standard.set(biography, forKey: UserPeer.BiographyKey)
	}

	/// Reads all properties of the user from disk.
	func readProfileFromDisk() throws -> ProfileData {
		let biography = UserDefaults.standard.string(forKey: UserPeer.BiographyKey) ?? ""

		var peerInfo = try unarchiveFromUserDefs(PeerInfo.self, UserPeer.PrefKey)

		let dateOfBirth: Date?
		if UserDefaults.standard.object(forKey: UserPeer.DateOfBirthKey) != nil {
			let birth = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: UserPeer.DateOfBirthKey))
			dateOfBirth = birth
			// if the user leveled up we need to update it in our PeerInfo as well (this is not very accurate but suffices for now)
			peerInfo?.age = (Calendar.current as NSCalendar).components(NSCalendar.Unit.year, from: birth, to: Date(), options: []).year
		} else {
			dateOfBirth = nil
			peerInfo?.age = nil
		}

		let image: UIImage?
		if peerInfo?.hasPicture ?? false,
		   let provider = CGDataProvider(url: UserPeer.pictureResourceURL as CFURL) {
			let cgPicture = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
			image = cgPicture.map { UIImage(cgImage: $0) }
		} else {
			image = nil
		}

		return ProfileData(peerInfo: peerInfo, picture: image, biography: biography, birthday: dateOfBirth)
	}

	/// Wipes all persisted data.
	func clear() {
		defer {
			Notification.Name.userPeerChanged.post(on: self)
		}

		UserDefaults.standard.removeObject(forKey: UserPeer.PrefKey)
		UserDefaults.standard.removeObject(forKey: UserPeer.DateOfBirthKey)
		UserDefaults.standard.removeObject(forKey: UserPeer.BiographyKey)
		do {
			try FileManager.default.deleteFile(at: UserPeer.pictureResourceURL)
		} catch let error {
			elog(Self.LogTag, "could not delete UserPeer portrait: \(error.localizedDescription)")
		}
	}

	// MARK: - Private

	// MARK: Static Constants

	// Log tag.
	private static let LogTag = "UserPeer"

	private static let PrefKey = "UserPeer"
	private static let PortraitFileName = "UserPortrait.jpg"
	private static let DateOfBirthKey = "UserPeer.dateOfBirth"
	private static let BiographyKey = "UserPeer.biography"
}
