//
//  Profile.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore
import PeereeDiscovery

final class Profile: DiscoveryPerson {

	func load() async throws {
		let data = try await Self.userPeer.readProfileFromDisk()
		data.peerInfo.map { self.info = $0 }
		self.picture = data.picture
		self.birthday = data.birthday
		self.biography = data.biography
	}

	override var info: PeerInfo {
		didSet {
			let pi = info
			Task {
				await Self.userPeer.modify(peerInfo: pi)
			}
		}
	}

	var picture: UIImage? = nil {
		didSet {
			//image = picture.map { Image(uiImage: $0) } ?? Image("PortraitPlaceholder")
			cgPicture = picture?.cgImage
			let pi = picture
			Task {
				do {
					try await Self.userPeer.modify(portrait: pi?.cgImage)
				} catch {
					InAppNotificationStackViewState.shared.display(genericError: error)
				}
			}

			syncHasPicture()
		}
	}

	override var biography: String {
		didSet {
			let pi = biography
			Task {
				await Self.userPeer.modify(biography: pi)
			}
		}
	}

	var birthday: Date? {
		didSet {
			let birth = birthday
			guard oldValue != birth else { return }

			Task {
				await Self.userPeer.modify(birthday: birth)
			}

			syncAge()
		}
	}

	init() {
		super.init(peerID: PeerID(), info: PeerInfo(nickname: "", gender: .queer, age: nil, hasPicture: false), lastSeen: Date())
		self.isUser = true
	}

	private static let userPeer = UserPeer()
}

// For SwiftUI
extension Profile {
	/// Bindable property
	var uiBirthday: Date {
		get { return birthday ?? Date() }
		set {
			guard self.birthday != newValue else { return }
			self.birthday = newValue
		}
	}
}

extension Profile {

	/// Writes calculated age from `dateOfBirth` into `peerInfo` and returns whether the value really changed; call only from `queue`.
	@discardableResult private func syncAge() -> Bool {
		let oldValue = info.age
		if let birth = birthday {
			info.age = (Calendar.current as NSCalendar).components(NSCalendar.Unit.year, from: birth, to: Date(), options: []).year
		} else {
			info.age = nil
		}
		return oldValue != info.age
	}

	/// Sets `hasPicture`of `peerInfo` based on `cgPicture` and returns whether the value really changed; call only from `queue`.
	@discardableResult private func syncHasPicture() -> Bool {
		let oldValue = info.hasPicture
		let newValue = picture != nil
		info.hasPicture = newValue
		return oldValue != newValue
	}
}
