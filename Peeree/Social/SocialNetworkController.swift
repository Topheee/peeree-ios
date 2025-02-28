//
//  SocialNetworkController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 10.01.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform Dependencies
import CoreGraphics

// Internal Dependencies
import PeereeCore

// External Dependencies
import OpenAPIURLSession
import OpenAPIRuntime

/// Names of notifications sent by `SocialNetworkController`.
extension Notification.Name {

		/// Notifications regarding pins.
	public static
	let pinFailed = Notification.Name("de.peeree.pinFailed"),
		unpinFailed = Notification.Name("de.peeree.unpinFailed"),
		pinMatch = Notification.Name("de.peeree.pinMatch"),
		unmatch = Notification.Name("de.peeree.unmatch"),
		unpinned = Notification.Name("de.peeree.unpinned")

	/// Notification when a picture was reported as inappropriate.
	public static
	let peerReported = Notification.Name("de.peeree.peerReported")
}

// https://swiftpackageindex.com/apple/swift-openapi-generator/1.6.0/tutorials/swift-openapi-generator/clientxcode
public actor SocialNetworkController: PeereeCore.Authenticator {

	public var viewModel: any SocialViewModelDelegate

	public var pinMatches: Set<PeerID> { return self.pinnedByPeers }

	public init(authenticator: PeereeCore.Authenticator,
				viewModel: any SocialViewModelDelegate, isTest: Bool) {
		self.isTest = isTest
		self.viewModel = viewModel
		self.authenticator = authenticator

		let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(Self.PinnedByPeersKey, containing: [NSUUID.self])
		self.pinnedByPeers = nsPinnedBy as? Set<PeerID> ?? Set()

		let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(Self.PinnedPeersKey, containing: [NSUUID.self, NSData.self])
		self.pinnedPeers = nsPinned as? [PeerID : Data] ?? [PeereeCore.PeerID : Data]()

		let lastRefreshInterval = UserDefaults.standard.double(forKey: Self.ObjectionableContentRefreshKey)
		self.lastObjectionableContentRefresh = Date(timeIntervalSinceReferenceDate: lastRefreshInterval)

		let models: [PeerID] = pinnedPeers.map { (peerID, _) in
			peerID
		}

		Task {
			await self.updateModels(of: models)
		}
	}

	/// Retrieves the full known public key of `peerID`, if available.
	public func publicKey(of peerID: PeereeCore.PeerID) -> Data? { return pinnedPeers[peerID] }

	/// Retrieves the full known identity of `peerID`.
	public func id(of peerID: PeereeCore.PeerID) throws -> PeereeIdentity {
		guard let publicKeyData = pinnedPeers[peerID] else {
			throw createApplicationError(localizedDescription: NSLocalizedString("Unknown peer.", comment: "Requested information about an unknown peer."))
		}

		return PeereeIdentity(peerID: peerID, publicKeyData: publicKeyData)
	}

	/// Returns whether we have a pin match with that specific PeerID.
	private func hasPinMatch(_ peerID: PeereeCore.PeerID) -> Bool {
		// it is enough to check whether we are pinned by peerID, as we only know that if we matched
		return pinnedByPeers.contains(peerID)
	}

	/// Returns whether we pinned that specific PeerIdentity.
	public func isPinned(_ id: PeereeIdentity) -> Bool {
		return pinnedPeers[id.peerID] == id.publicKeyData
	}

	/// Checks whether the pinning process is (already) running for `peerID`.
	public func isPinning(_ peerID: PeereeCore.PeerID) -> Bool {
		return pinningPeers.contains(peerID)
	}

	/// Pins a person and checks for a pin match.
	public func pin(_ id: PeereeIdentity) async throws {
		let userID = id.peerID.uuidString
		guard !isPinned(id) && !isPinning(id.peerID) else { return }

		pinningPeers.insert(id.peerID)
		updateModels(of: [id.peerID])

		let result = try await client().postPin(.init(path: .init(userID: userID)))

		self.pinningPeers.remove(id.peerID)

		switch result {
		case .ok(let ok):
			// TODO: test: this is probably always false, since plainText is not a string
			let isPinMatch = try ok.body.plainText == "true"
			self.pin(id: id, isPinMatch: isPinMatch)
			self.updateModels(of: [id.peerID])
		case .badRequest(let clientSideError):
			try await handle(clientSideError, logTag: Self.LogTag)
		case .unauthorized(let error):
			try handle(error, logTag: Self.LogTag)
		case .undocumented(let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		}
	}

	/// Removes the pin from a person.
	public func unpin(_ peerID: PeerID) async throws {
		guard let id: PeereeIdentity = try? self.id(of: peerID),
			  !unpinningPeers.contains(peerID) && isPinned(id) else { return }

		let userID = id.peerID.uuidString

		unpinningPeers.insert(peerID)
		updateModels(of: [peerID])

		let result = try await client().deletePin(.init(path: .init(userID: userID)))

		self.unpinningPeers.remove(peerID)

		switch result {
		case .ok(_):
			self.removePin(from: id)
			self.updateModels(of: [id.peerID])
		case .badRequest(let clientSideError):
			try await handle(clientSideError, logTag: Self.LogTag)
		case .unauthorized(let error):
			try handle(error, logTag: Self.LogTag)
		case .undocumented(let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		}
	}

	/// Reports the picture of a person as inappropriate.
	public func report(peerID: PeereeCore.PeerID, portrait: CGImage,
					   portraitHash: Data, hashSignature: Data) async throws {
		let jpgData = try portrait.jpgData(compressionQuality: Self.UploadCompressionQuality)

		let userID = peerID.uuidString

		let result = try await self.client().postContentFilterPortraitReport(
			.init(path: .init(userID: userID),
				  query: .init(signature: Base64EncodedData(hashSignature)),
				  body: .jpeg(.init(jpgData))))
		switch result {
		case .accepted(_):
			let vm = self.viewModel

			Task { @MainActor in
				vm.pendingObjectionableImageHashes[portraitHash] = Date()

				let save = vm.pendingObjectionableImageHashes
				//self.dQueue.async {
				archiveObjectInUserDefs(save as NSDictionary, forKey: Self.PendingObjectionableImageHashesKey)
				//}

				Notification.Name.peerReported.post(for: peerID)
			}
		case .badRequest(let clientSideError):
			try await handle(clientSideError, logTag: Self.LogTag)
		case .unauthorized(let error):
			try handle(error, logTag: Self.LogTag)
		case .undocumented(let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		}
	}

	/// Downloads objectionable content hashes.
	public func refreshBlockedContent() async throws {
		guard self.lastObjectionableContentRefresh
			.addingTimeInterval(Self.ObjectionableContentRefreshThreshold) < Date() else { return }

		let result = try await self.client().getContentFilterPortraitHashes(
			.init(query: .init(startDate: self.lastObjectionableContentRefresh)))

		switch result {
		case .ok(let ok):
			let hexHashes = try ok.body.json

			let hashesAsData = Set<Data>(hexHashes.compactMap { Data(hexString: $0) })

			let nsPendingObjectionableImageHashes: NSDictionary? = unarchiveObjectFromUserDefs(Self.PendingObjectionableImageHashesKey, containing: [NSData.self, NSDate.self])
			let pendingObjectionableImageHashes = (nsPendingObjectionableImageHashes as? Dictionary<Data,Date> ?? Dictionary<Data,Date>()).filter { element in
				return !hashesAsData.contains(element.key)
			}

			archiveObjectInUserDefs(hashesAsData as NSSet, forKey: Self.ObjectionableImageHashesKey)
			archiveObjectInUserDefs(pendingObjectionableImageHashes as NSDictionary, forKey: Self.PendingObjectionableImageHashesKey)

			self.lastObjectionableContentRefresh = Date()
			UserDefaults.standard.set(self.lastObjectionableContentRefresh.timeIntervalSinceReferenceDate, forKey: Self.ObjectionableContentRefreshKey)

			let vm = self.viewModel

			Task { @MainActor in
				vm.objectionableImageHashes = hashesAsData
				vm.pendingObjectionableImageHashes = pendingObjectionableImageHashes
			}

		case .undocumented(let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		}
	}

	/// Persists the pin.
	private func pin(id: PeereeIdentity, isPinMatch: Bool) {
		let peerID = id.peerID

		if pinnedPeers[peerID] != id.publicKeyData {
			pinnedPeers[peerID] = id.publicKeyData
			archiveObjectInUserDefs(pinnedPeers as NSDictionary, forKey: Self.PinnedPeersKey)
		}

		// check whether the pin match state changed
		guard pinnedByPeers.contains(peerID) != isPinMatch else { return }

		if isPinMatch {
			// this is a pin match we weren't aware of
			pinnedByPeers.insert(peerID)

			// post this on the main queue
			Notification.Name.pinMatch.post(for: peerID)
		} else {
			// the opposite removed the pin (unmatched us)
			pinnedByPeers.remove(peerID)

			// post this on the main queue
			Notification.Name.unmatch.post(for: peerID)
		}

		archiveObjectInUserDefs(pinnedByPeers as NSSet, forKey: Self.PinnedByPeersKey)
	}

	/// Persists the pin removal.
	private func removePin(from id: PeereeIdentity) {
		let peerID = id.peerID

		pinnedPeers.removeValue(forKey: peerID)
		archiveObjectInUserDefs(pinnedPeers as NSDictionary, forKey: Self.PinnedPeersKey)

		if pinnedByPeers.remove(peerID) != nil {
			archiveObjectInUserDefs(pinnedByPeers as NSSet, forKey: Self.PinnedByPeersKey)
		}

		Notification.Name.unpinned.post(for: peerID)
	}

	/// Retrieve the pin (matched) status from the server. If `force` is `false`, do not update if we believe we have a pin match.
	public func updatePinStatus(of id: PeereeIdentity, force: Bool) async throws -> PinState {
		guard force || !hasPinMatch(id.peerID) else {
			return .pinMatch
		}

		let userID = id.peerID.uuidString

		let result = try await self.client().getPin(
			.init(path: .init(userID: userID)))

		switch result {
		case .ok(let ok):
			defer {
				self.updateModels(of: [id.peerID])
			}

			let pinStatus = try ok.body.json
			switch pinStatus {
			case .pinned:
				self.pin(id: id, isPinMatch: false)
				return .pinned
			case .matched:
				self.pin(id: id, isPinMatch: true)
				return .pinMatch
			case .unpinned:
				self.removePin(from: id)
				return .unpinned
			@unknown default:
				break
			}

		case .badRequest(let clientSideError):
			try await handle(clientSideError, logTag: Self.LogTag)
		case .unauthorized(let error):
			try handle(error, logTag: Self.LogTag)
		case .undocumented(let statusCode, let payload):
			try await handle(statusCode, payload, logTag: Self.LogTag)
		}
	}

	/// Wipes all data after the account was deleted.
	public func clearLocalData() {
		pinningPeers.removeAll()
		unpinningPeers.removeAll()

		pinnedPeers.removeAll()
		archiveObjectInUserDefs(pinnedPeers as NSDictionary, forKey: Self.PinnedPeersKey)

		pinnedByPeers.removeAll()
		archiveObjectInUserDefs(pinnedByPeers as NSSet, forKey: Self.PinnedByPeersKey)

		cachedAccessToken = nil

		let vm = self.viewModel

		Task { @MainActor in
			vm.clear()
		}
	}

	// MARK: Authenticator

	public func accessToken() async throws -> String {
		if let (token, expiry) = self.cachedAccessToken, expiry > Date() {
			return token
		}

		let token = try await authenticator.accessToken()

		let parts = token.split(
			separator: Character("."), omittingEmptySubsequences: false
		)

		let expires: Date

		if parts.count == 3,
		   let json = Data(base64Encoded: String(parts[1])),
		   let values = try? JSONDecoder().decode(AccessTokenJWT.self, from: json) {
			// TODO: test
			expires = values.exp
		} else {
			wlog(Self.LogTag, "Failed to parse access token.")
			expires = Date.distantPast
		}

		cachedAccessToken = (token, expires)
		return token
	}

	// MARK: - Private

	/// Logging tag.
	private static let LogTag = "SocialNetworkController"

	/// User defaults key for pinned peers dictionary
	private static let PinnedPeersKey = "PinnedPeers"
	/// User defaults key for pinned by peers dictionary
	private static let PinnedByPeersKey = "PinnedByPeers"
	/// User defaults key for objectionable image hashes
	private static let ObjectionableImageHashesKey = "ObjectionableImageHashes"
	/// User defaults key for reported and not yet objectionable image hashes
	private static let PendingObjectionableImageHashesKey = "PendingObjectionableImageHashesKey"
	/// User defaults key for objectionable content refresh timestamp
	private static let ObjectionableContentRefreshKey = "ObjectionableContentRefresh"
	/// JPEG compression quality for portrait report uploads.
	private static let UploadCompressionQuality: CGFloat = 0.3

	/// Refresh objectionable content every day at most (or when the app is killed).
	private static let ObjectionableContentRefreshThreshold: TimeInterval = 60 * 60 * 24

	// MARK: Constants

	private let isTest: Bool

	/// Delegate to provide a fresh access token.
	private let authenticator: PeereeCore.Authenticator

	// MARK: Variables

	/*
	 store pinned public key along with peerID as
	 1. Alice pins Bob
	 2. Eve advertises Bob's peerID with her public key
	 3. Alice validates Bob's peerID with Eve's public key and thinks she met Bob again
	 4. Eve convinced Alice successfully that she is Bob
	*/

	/// Pinned peers and their public keys.
	private var pinnedPeers: [PeerID : Data]
	/// Pin matched peers.
	private var pinnedByPeers: Set<PeerID>

	/// Peers with underway requests to pin.
	private var pinningPeers = Set<PeerID>()

	/// Peers with underway requests to unpin from.
	private var unpinningPeers = Set<PeerID>()

	/// Timestamp of last successful refresh of objectionable content.
	private var lastObjectionableContentRefresh: Date

	/// The last issued access token and its expiration date.
	private var cachedAccessToken: (String, Date)?

	// MARK: Methods

	private func client() throws -> Client {
		Client(
			serverURL: isTest ? try Servers.Server2.url() :
				try Servers.Server1.url(),
			transport: URLSessionTransport(),
			middlewares: [AuthenticationMiddleware(authenticator: self)]
		)
	}

	/// Calculates the current pin state machine state for `peerID`.
	private func pinState(of peerID: PeerID) -> PinState {
		if pinningPeers.contains(peerID) {
			return .pinning
		} else if unpinningPeers.contains(peerID) {
			return .unpinning
		} else if pinnedByPeers.contains(peerID) {
			return .pinMatch
		} else if pinnedPeers[peerID] != nil {
			return .pinned
		} else {
			return .unpinned
		}
	}

	/// Populate changes in `ids` to the appropriate view models.
	private func updateModels(of ids: [PeerID]) {
		let models = ids.map { id in
			SocialPersonData(peerID: id, pinState: self.pinState(of: id))
		}

		let vm = self.viewModel

		Task { @MainActor in
			for model in models {
				_ = vm.addPersona(of: model.peerID, with: model.pinState)
			}
		}
	}
}

extension SocialNetworkController {
	public func unpinnedPeers(_ identities: [PeereeIdentity]) async -> [PeerID] {
		return identities.filter { !self.isPinned($0) }.map { $0.peerID }
	}
}

