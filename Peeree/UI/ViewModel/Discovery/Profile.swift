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

	/// Call ``load(data:)`` with the result of this function.
	func loadAsync(_ completion: (@Sendable @escaping (Result<ProfileData, Error>) -> Void)) {
		let up = self.userPeer
		Task {
			do {
				let data = try await up.readProfileFromDisk()
				completion(.success(data))
			} catch {
				completion(.failure(error))
			}
		}
	}

	/// Call with the result from ``loadAsync(_:)``.
	func load(data: ProfileData) {
		self.isLoading = true

		defer { self.isLoading = false }

		data.peerInfo.map { self.info = $0 }
		self.picture = data.picture
		self.birthday = data.birthday
		self.biography = data.biography
	}

	override var info: PeerInfo {
		didSet {
			guard !self.isLoading else { return }

			let pi = info
			let up = userPeer
			Task {
				await up.modify(peerInfo: pi)
			}
		}
	}

	var picture: UIImage? = nil {
		didSet {

			//image = picture.map { Image(uiImage: $0) } ?? Image("PortraitPlaceholder")
			self.cgPicture = self.picture?.cgImage

			self.syncHasPicture()

			guard !self.isLoading, let pi = picture else { return }

			let up = userPeer
			Task {
				do {
					try await up.modify(portrait: pi.cgImage)
				} catch {
					await InAppNotificationStackViewState.shared.display(genericError: error)
				}
			}
		}
	}

	override var biography: String {
		didSet {
			guard !self.isLoading else { return }

			let pi = biography
			let up = userPeer
			Task {
				await up.modify(biography: pi)
			}
		}
	}

	var birthday: Date? {
		didSet {
			guard !self.isLoading else { return }

			let birth = birthday
			guard oldValue != birth else { return }

			let up = userPeer
			Task {
				await up.modify(birthday: birth)
			}

			syncAge()
		}
	}

	init() {
		super.init(peerID: PeerID(), info: PeerInfo(nickname: "", gender: .queer, age: nil, hasPicture: false), lastSeen: Date())
		self.isUser = true
	}

	private let userPeer = UserPeer()

	/// Whether we are currently loading the profile from disk.
	private var isLoading = false
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
