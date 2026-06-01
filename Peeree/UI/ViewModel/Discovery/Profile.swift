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

@MainActor
final class Profile: DiscoveryPerson {

	/// Call ``load(data:)`` with the result of this function.
	func loadAsync(_ completion: (@Sendable @escaping (Result<ProfileData, Error>) -> Void)) {
		self.isLoading = true
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
		defer { self.isLoading = false }

		data.peerInfo.map { self.info = $0 }
		self.cgPicture = data.picture
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

	func set(image: UIImage?) -> UIImage? {
		guard let image else {
			self.cgPicture = nil
			self.syncHasPicture()
			return nil
		}

		guard let squaredImage = image.centerSquared() else {
			assertionFailure()
			return nil
		}

		let scaledSquaredUIImage = UIImage(
			cgImage: squaredImage, scale: image.scale,
			orientation: image.imageOrientation)
			.scaled(to: CGSize(squareEdgeLength: Self.MaxProfileEdgeLength))

		guard let scaledSquaredImage = scaledSquaredUIImage.cgImage else {
			assertionFailure()
			return nil
		}

		self.cgPicture = scaledSquaredImage

		self.syncHasPicture()

		guard !self.isLoading else { return nil }

		let up = userPeer
		Task {
			do {
				try await up.modify(portrait: scaledSquaredImage)
			} catch {
				InAppNotificationStackViewState.shared.display(
					genericError: error)
			}
		}

		return scaledSquaredUIImage
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

	// MARK: - Private

	/// Maximum amount of pixels in each direction of the profile image.
	private static let MaxProfileEdgeLength: CGFloat = 256

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
		let oldValue = self.info.hasPicture
		let newValue = self.cgPicture != nil
		self.info.hasPicture = newValue
		return oldValue != newValue
	}
}
