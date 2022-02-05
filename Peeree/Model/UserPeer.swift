//
//  UserPeer.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.01.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

/// Holds and persists the peer information of the user.
public final class UserPeer {
	// MARK: - Public and Internal

	// MARK: Classes, Structs, Enums

	// MARK: Static Constants

	/// The singleton instance of this class.
	public static let instance = UserPeer()

	// MARK: Static Variables

	/// The URL of the user's picture.
	static var pictureResourceURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent(UserPeer.PortraitFileName, isDirectory: false)
	}

	// MARK: Constants

	// MARK: Variables

	// MARK: Methods

	/// Grants read-only access to all of the user's properties: `peerInfo`, `birthday`, `portrait` and `biography`.
	public func read(on callbackQueue: DispatchQueue? = DispatchQueue.main, completion: @escaping (PeerInfo?, Date?, CGImage?, String) -> ()) {
		queue.async {
			let info = self.peerInfo
			let birthday = self.dateOfBirth
			let pic = self.cgPicture
			let bio = self.biography
			if let callbackQueue = callbackQueue {
				callbackQueue.async {
					completion(info, birthday, pic, bio)
				}
			} else {
				completion(info, birthday, pic, bio)
			}
		}
	}

	/// Modifies or sets the `PeerInfo` part of the user's peer.
	public func modifyInfo(_ query: @escaping (inout PeerInfo?) -> ()) {
		modify {
			query(&self.peerInfo)

			self.syncAge()
			self.syncHasPicture()
			self.savePeerInfo()
		}
	}

	/// Sets the user's portrait.
	public func modify(portrait: CGImage?) {
		modify {
			guard portrait != self.cgPicture else { return }

			do {
				if let pic = portrait {
					try pic.save(to: UserPeer.pictureResourceURL, compressionQuality: PersistedPeersController.StandardPortraitCompressionQuality)
				} else {
					try self.deletePicture()
				}

				self.cgPicture = portrait
				if self.syncHasPicture() { self.savePeerInfo() }
			} catch let error as NSError {
				NSLog("ERROR: could not persist or delete UserPeer portrait: \(error.localizedDescription)")
			}
		}
	}

	/// Sets the user's birthday.
	public func modify(birthday: Date?) {
		modify {
			self.dateOfBirth = birthday
			if let birth = birthday {
				UserDefaults.standard.set(birth.timeIntervalSince1970, forKey: UserPeer.DateOfBirthKey)
			} else {
				UserDefaults.standard.set(nil, forKey: UserPeer.DateOfBirthKey)
			}
			if self.syncAge() { self.savePeerInfo() }
		}
	}

	/// Sets the user's biography.
	public func modify(biography: String) {
		modify {
			self.biography = biography
			UserDefaults.standard.set(biography, forKey: UserPeer.BiographyKey)
		}
	}

	// MARK: - Private

	/// Reads all properties of the user from disk.
	private init() {
		let time: TimeInterval? = UserDefaults.standard.double(forKey: UserPeer.DateOfBirthKey)
		time.map { self.dateOfBirth = Date(timeIntervalSince1970: $0) }
		if UserDefaults.standard.object(forKey: UserPeer.DateOfBirthKey) != nil {
			dateOfBirth = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: UserPeer.DateOfBirthKey))
		}
		biography = UserDefaults.standard.string(forKey: UserPeer.BiographyKey) ?? ""
		do {
			peerInfo = try unarchiveFromUserDefs(PeerInfo.self, UserPeer.PrefKey)
		} catch let error {
			NSLog("ERROR: could not persist UserPeer: \(error.localizedDescription)")
		}

		if peerInfo?.hasPicture ?? false {
			if let provider = CGDataProvider(url: UserPeer.pictureResourceURL as CFURL) {
				cgPicture = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
			} else {
				NSLog("ERROR: could not initialize CGDataProvider.")
			}
		}

		// if the user leveled up we need to update it in our PeerInfo as well (this is not very accurate but suffices for now)
		syncAge()

		observeNotifications()
		queue.async { self.syncToViewModel() }
	}

	// MARK: Classes, Structs, Enums

	// MARK: Static Constants

	private static let PrefKey = "UserPeer"
	private static let PortraitFileName = "UserPortrait.jpg"
	private static let DateOfBirthKey = "UserPeer.dateOfBirth"
	private static let BiographyKey = "UserPeer.biography"

	// MARK: Static Variables

	// MARK: Constants

	/// The queue where the user's data may be accessed on.
	private let queue = DispatchQueue(label: "de.peeree.UserPeer", qos: .userInitiated)

	// MARK: Variables

	/// The concrete birthday of the user, based on which his age is calculated and communicated.
	private var dateOfBirth: Date?
	private var peerInfo: PeerInfo?
	private var cgPicture: CGImage? = nil
	private var biography = ""

	// MARK: Methods

	/// Wipes all persisted data.
	private func clear() {
		UserDefaults.standard.set(nil, forKey: UserPeer.PrefKey)
		UserDefaults.standard.set(nil, forKey: UserPeer.DateOfBirthKey)
		UserDefaults.standard.set(nil, forKey: UserPeer.BiographyKey)
		do {
			try deletePicture()
		} catch let error {
			NSLog("ERROR: could not delete UserPeer portrait: \(error.localizedDescription)")
		}
	}

	/// Deletes the file with the user's picture from disk.
	private func deletePicture() throws {
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: UserPeer.pictureResourceURL.path) {
			try fileManager.removeItem(at: UserPeer.pictureResourceURL)
		}
	}

	/// Writes calculated age from `dateOfBirth` into `peerInfo` and returns whether the value really changed; call only from `queue`.
	@discardableResult private func syncAge() -> Bool {
		let oldValue = peerInfo?.age
		if let birth = dateOfBirth {
			peerInfo?.age = (Calendar.current as NSCalendar).components(NSCalendar.Unit.year, from: birth, to: Date(), options: []).year
		} else {
			peerInfo?.age = nil
		}
		return peerInfo != nil && oldValue != peerInfo?.age
	}

	/// Sets `hasPicture`of `peerInfo` based on `cgPicture` and returns whether the value really changed; call only from `queue`.
	@discardableResult private func syncHasPicture() -> Bool {
		let oldValue = peerInfo?.hasPicture
		peerInfo?.hasPicture = cgPicture != nil
		return peerInfo != nil && oldValue != peerInfo?.hasPicture
	}

	/// Persists `peerInfo`; call only from `queue`.
	private func savePeerInfo() {
		guard let info = self.peerInfo else {
			UserDefaults.standard.set(nil, forKey: UserPeer.PrefKey)
			return
		}
		do {
			try archiveInUserDefs(info, forKey: UserPeer.PrefKey)
		} catch let error {
			NSLog("ERROR: could not persist UserPeer: \(error.localizedDescription)")
		}
	}

	/// Writes all properties to `PeerViewModelController`; call only from `queue`.
	private func syncToViewModel() {
		guard let info = self.peerInfo, let keyPair = AccountController.shared.keyPair else { return }
		let peerID = AccountController.shared.peerID
		// we must access our properties on `queue`
		let bio = self.biography
		let pic = self.cgPicture

		DispatchQueue.main.async {
			PeerViewModelController.update(peer: Peer(id: PeereeIdentity(peerID: peerID, publicKey: keyPair.publicKey), info: info), lastSeen: Date())
			PeerViewModelController.modify(peerID: peerID) { model in
				model.verified = true
				model.isAvailable = true
				model.biography = bio
				if let portrait = pic {
					model.loadedAndClassified(portrait: portrait, hash: Data(), classification: .none)
				} else {
					model.deletePortrait()
				}
			}
		}
	}

	/// Calls `query` on `queue` and `syncToViewModel()` afterwards.
	private func modify(query: @escaping () -> ()) {
		queue.async {
			query()
			self.syncToViewModel()
		}
	}

	/// Adds observer blocks for certain notifications.
	private func observeNotifications() {
		_ = AccountController.Notifications.accountCreated.addObserver { _ in
			self.queue.async { self.syncToViewModel() }
		}
	}
}
