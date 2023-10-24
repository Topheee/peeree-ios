//
//  PeerDiscoveryOperationManager.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 10.06.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth
import CoreGraphics

import PeereeCore
import KeychainWrapper
import KeyValueTree
import KeyValueTreeCoding
import BLEPeripheralOperations
import CSProgress

/// Provides a means to react on key steps of the discovery process.
protocol PeerDiscoveryOperationManagerDelegate: AnyObject {
	/// The person was able to proof that they are in possession of the private key belonging to their public key.
	func verified(_ peereeIdentity: PeereeIdentity)

	/// The portrait transmit process has begun.
	func beganLoadingPortrait(_ progress: CSProgress, of peerID: PeerID)

	/// Retrieved the describing information of a person.
	func loaded(info: PeerInfo, of identity: PeereeIdentity)

	/// Retrieved the biography of a person.
	func loaded(biography: String, of peerID: PeerID)

	/// Retrieved the picture of a person.
	func loaded(picture: CGImage, of peerID: PeerID, hash: Data)

	/// All available information of a peer has been read successfully.
	func peerDiscoveryFinished(peerLastChangedDate: Date, of peerID: PeerID)

	/// Something went wrong during the discovery.
	func peerDiscoveryFailed(_ error: Error)

	/// Estimated the signal strength to a person.
	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?)
}

/// Main class to handle the information retrieval process of a remote peer.
final class PeerDiscoveryOperationManager: PeripheralOperationTreeManagerDelegate {

	/// State of authentication with remote peer.
	public struct AuthenticationStatus: OptionSet {
		public let rawValue: Int

		/// We authenticated ourself to the peer.
		public static let to   = AuthenticationStatus(rawValue: 1 << 0)

		/// The peer authenticated to us.
		public static let from = AuthenticationStatus(rawValue: 1 << 1)

		/// The authentication is mutual.
		public static let full: AuthenticationStatus = [.to, .from]

		/// Create the status from a raw value.
		public init(rawValue: Int) {
			self.rawValue = rawValue
		}
	}

	/// The PeerID of the remote peer we are discovering.
	let peerID: PeerID

	/// The account of the user, if available.
	private(set) var userIdentity: (PeerID, KeyPair)? = nil

	/// Needed for writing nonces.
	let blockSize: Int

	/// The state of authentication.
	var authenticationStatus: AuthenticationStatus = []

	/// Informed party of the discovery process.
	weak var delegate: PeerDiscoveryOperationManagerDelegate?

	/// Current state including information necessary to process further steps.
	private(set) var state: PeerDiscoveryState

	/// Create an the operation manager. Start it by using `beginDiscovery()`.
	init(peerID: PeerID, lastChanged: Date, dQueue: DispatchQueue, blockSize: Int, userIdentity: (PeerID, KeyPair)?) {
		self.peerID = peerID
		self.state = .discovered(lastChanged)
		self.dQueue = dQueue
		self.blockSize = blockSize
		self.userIdentity = userIdentity

		let opTreeGraph: [KeyValueTree<PeripheralOperation, Void>]

		if userIdentity != nil {
			opTreeGraph = [
				.branch(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreeRemoteAuth1), nodes: [
					.leaf(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreeRemoteAuth2), value: ())
				]),
				.branch(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreeAuth1), nodes: [
					.branch(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreeAuth2), nodes: [
						.leaf(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreePeerInfo), value: ())
					])
				])
			]
		} else {
			// omit authenticating ourselves - since we can't without our own identity
			opTreeGraph = [
				.branch(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreeAuth1), nodes: [
					.branch(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreeAuth2), nodes: [
						.leaf(key: PeripheralOperation(characteristicOperationTree: PeerDiscoveryOperationManager.opTreePeerInfo), value: ())
					])
				])
			]
		}

		self.opTreeGraphDiscovery = opTreeGraph

		self.opManager = PeripheralOperationTreeManager(operationTrees: opTreeGraphDiscovery, queue: dQueue)
	}

	/// Begin the discovery process for a given peripheral.
	func beginDiscovery(on peripheral: CBPeripheral) {
		self.opManager.delegate = self
		self.opManager.begin(on: peripheral)
	}

	/// After all mandatory information is retrieved, the optional (and time-consuming) data can be requested using this method.
	func beginLoadAdditionalInfo(on peripheral: CBPeripheral, loadPortrait: Bool) throws {
		guard case let .queried(queried) = self.state else {
			switch self.state {
			case .scraping(_), .finished(_):
				// already done
				return
			default:
				throw createApplicationError(localizedDescription: "wrong state \(self.state)")
			}
		}

		self.state = .scraping(queried)

		self.opManager = PeripheralOperationTreeManager(operationTrees: loadPortrait ?
			[
				.leaf(key: PeripheralOperation(characteristicOperationTree: Self.opTreePortrait), value: ()),
				.leaf(key: PeripheralOperation(characteristicOperationTree: Self.opTreeBio), value: ())
			]
			:
			[.leaf(key: PeripheralOperation(characteristicOperationTree: Self.opTreeBio), value: ())],
			queue: self.dQueue
		)

		self.opManager.delegate = self
		self.opManager.begin(on: peripheral)
	}

	/// Cancel the discovery.
	func cancel() {
		self.opManager.cancel()
	}

	// MARK: PeripheralOperationTreeManagerDelegate

	func peripheralOperationTreeFinished(_ manager: BLEPeripheralOperations.PeripheralOperationTreeManager) {
		guard case let .scraping(scraping) = self.state else {
			return
		}

		self.state = .finished(scraping)

		delegate?.peerDiscoveryFinished(peerLastChangedDate: scraping.lastChanged, of: self.peerID)
	}

	// MARK: PeripheralOperationManagerDelegate

	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		delegate?.didRange(self.peerID, rssi: RSSI, error: error)
	}

	func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
		// ignored
	}

	// MARK: PeripheralOperationDelegate

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, beganMultiWrite characteristicID: CBUUID, with progress: CSProgress) {
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, beganMultiRead characteristicID: CBUUID, with progress: CSProgress) {
		switch characteristicID {
		case CBUUID.PortraitCharacteristicID:
			delegate?.beganLoadingPortrait(progress, of: self.peerID)
		default:
			break
		}
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, encounteredUnrecoverableError error: BLEPeripheralOperations.PeripheralOperationUnrecoverableError) {
		delegate?.peerDiscoveryFailed(error)
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, encounteredRecoverableError error: BLEPeripheralOperations.PeripheralOperationRecoverableError) -> Bool {
		failures += 1
		return failures < Self.MaxFailures
	}

	func peripheralOperation(_ operation: PeripheralOperation, writeDataFor characteristicID: CBUUID, of peripheral: CBPeripheral) throws -> Data {
		switch characteristicID {
		case CBUUID.RemoteUUIDCharacteristicID:
			guard let userPeerID = self.userIdentity?.0 else {
				throw unexpectedNilError()
			}

			return userPeerID.encode()

		case CBUUID.AuthenticationCharacteristicID:
			let writeType = CBCharacteristicWriteType.withResponse
			let randomByteCount = min(peripheral.maximumWriteValueLength(for: writeType), self.blockSize)
			let nonce = try generateRandomData(length: randomByteCount)
			self.nonce = nonce
			return nonce


		case CBUUID.RemoteAuthenticationCharacteristicID:
			guard let keyPair = self.userIdentity?.1 else {
				throw unexpectedNilError()
			}

			return try keyPair.sign(message: self.remoteNonce)

		default:
			throw createApplicationError(localizedDescription: "unknown peripheral write operation")
		}
	}

	func peripheralOperationFinished(_ operation: PeripheralOperation, model: KeyValueTree<CBUUID, Data>, of peripheral: CBPeripheral) {
		switch operation.id {

		case Self.idOpTreeAuth1:
			// no-op
			break

		case Self.idOpTreeAuth2:
			guard case let .discovered(lastChanged) = self.state else {
				assertionFailure("wrong state \(self.state) after retrieving idOpTreeAuth2.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsisteny."))
				return
			}

			let identity: PeereeIdentity
			do {
				let verificationData = try Self.decoder.decode(VerificationData.self, from: sub(model: model))

				identity = try PeereeIdentity(peerID: self.peerID, publicKeyData: verificationData.publicKeyData)

				try identity.publicKey.verify(message: nonce, signature: verificationData.nonceSignature)
				try identity.publicKey.verify(message: self.peerID.encode(), signature: verificationData.peerIDSignature)
			} catch {
				delegate?.peerDiscoveryFailed(error)
				self.opManager.cancel()
				return
			}

			self.state = .identified(Identified(publicKey: identity.publicKey, lastChanged: lastChanged))

			self.authenticationStatus.insert(AuthenticationStatus.from)

			delegate?.verified(identity)

		case Self.idOpTreeRemoteAuth1:
			do {
				let remoteIdentificationData = try Self.decoder.decode(RemoteIdentificationData.self, from: sub(model: model))
				self.remoteNonce = remoteIdentificationData.remoteNonce
			} catch {
				delegate?.peerDiscoveryFailed(error)
				self.opManager.cancel()
				return
			}

		case Self.idOpTreeRemoteAuth2:
			self.authenticationStatus.insert(AuthenticationStatus.to)

		case Self.idOpTreePeerData:
			guard case let .identified(identified) = self.state else {
				assertionFailure("wrong state \(self.state) after retrieving idOpTreePeerData.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsistency."))
				return
			}

			let peerData: PeerData
			do {
				peerData = try Self.decoder.decode(PeerData.self, from: sub(model: model))

				try identified.publicKey.verify(message: peerData.aggregateData, signature: peerData.aggregateDataSignature)
				try identified.publicKey.verify(message: peerData.nickname, signature: peerData.nicknameSignature)
			} catch {
				delegate?.peerDiscoveryFailed(error)
				self.opManager.cancel()
				return
			}

			guard let peerInfo = PeerInfo(aggregateData: peerData.aggregateData, nicknameData: peerData.nickname) else {
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Could not decode peer info."))
				return
			}

			self.state = .queried(identified)

			delegate?.loaded(info: peerInfo, of: PeereeIdentity(peerID: self.peerID, publicKey: identified.publicKey))

		case Self.idOpTreeBio:
			guard case let .scraping(identified) = self.state else {
				assertionFailure("wrong state \(self.state) after retrieving idOpTreePeerData.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsisteny."))
				return
			}

			do {
				let subModel = try sub(model: model)
				let bioData = try Self.decoder.decode(BioData.self, from: subModel)

				guard let rawBio = subModel.value(at: [BioData.CodingKeys.bio]) else {
					throw createApplicationError(localizedDescription: "didn't find bio key")
				}

				try identified.publicKey.verify(message: rawBio, signature: bioData.bioSignature)

				delegate?.loaded(biography: bioData.bio, of: self.peerID)
			} catch {
				delegate?.peerDiscoveryFailed(error)
				self.opManager.cancel()
				return
			}

		case Self.idOpTreePortrait:
			guard case let .scraping(identified) = self.state else {
				assertionFailure("wrong state \(self.state) after retrieving idOpTreePeerData.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsisteny."))
				return
			}

			let portraitData: PortraitData
			do {
				portraitData = try Self.decoder.decode(PortraitData.self, from: sub(model: model))

				try identified.publicKey.verify(message: portraitData.portrait, signature: portraitData.portraitSignature)
			} catch {
				delegate?.peerDiscoveryFailed(error)
				self.opManager.cancel()
				return
			}

			guard let provider = CGDataProvider(data: portraitData.portrait as CFData),
				  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent) else {
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Failed to create image from data."))
				self.opManager.cancel()
				return
			}

			delegate?.loaded(picture: image, of: self.peerID, hash: portraitData.portrait.sha256())

		default:
			assertionFailure("unknown peripheral operation \(operation.id.uuidString) finished.")
		}
	}

	// MARK: - Private

	/// Maximum amount of failed 'recoverable' Bluetooth operations, before the process is aborted.
	private static let MaxFailures = 3

	/// The Decoder to unmarshal the results of the sub-operations.
	private static let decoder = KeyValueTreeCoding.DataTreeDecoder()

	/// The ID of the first authentication step.
	private static let idOpTreeAuth1 = CBUUID(nsuuid: UUID())

	/// The ID of the second authentication step.
	private static let idOpTreeAuth2 = CBUUID(nsuuid: UUID())

	/// The ID of the first remote authentication step.
	private static let idOpTreeRemoteAuth1 = CBUUID(nsuuid: UUID())

	/// The ID of the second remote authentication step.
	private static let idOpTreeRemoteAuth2 = CBUUID(nsuuid: UUID())

	/// The ID of the main information retrieval step.
	private static let idOpTreePeerData = CBUUID(nsuuid: UUID())

	/// The ID of the portrait retrieval step.
	private static let idOpTreePortrait = CBUUID(nsuuid: UUID())

	/// The ID of the biography retrieval step.
	private static let idOpTreeBio = CBUUID(nsuuid: UUID())

	/// The first authentication step.
	private static let opTreeAuth1 = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreeAuth1, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.AuthenticationCharacteristicID, value: CharacteristicOperation(task: .write, mandatory: true))
		])
	])

	/// The second authentication step.
	private static let opTreeAuth2 = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreeAuth2, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.AuthenticationCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.PublicKeyCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.PeerIDSignatureCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true))
		])
	])

	/// The  first remote authentication step.
	private static let opTreeRemoteAuth1 = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreeRemoteAuth1, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.RemoteUUIDCharacteristicID, value: CharacteristicOperation(task: .write, mandatory: false)),
			.leaf(key: CBUUID.RemoteAuthenticationCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: false))
		])
	])

	/// The second remote authentication step.
	private static let opTreeRemoteAuth2 = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreeRemoteAuth2, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.RemoteAuthenticationCharacteristicID, value: CharacteristicOperation(task: .write, mandatory: false))
		])
	])

	/// The main information retrieval step.
	private static let opTreePeerInfo = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreePeerData, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.AggregateCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.NicknameCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.AggregateSignatureCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.NicknameSignatureCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true))
		])
	])

	/// The portrait retrieval step.
	private static let opTreePortrait = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreePortrait, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.PortraitCharacteristicID, value: CharacteristicOperation(task: .multiRead, mandatory: false)),
			.leaf(key: CBUUID.PortraitSignatureCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: false))
		])
	])

	/// The biography retrieval step.
	private static let opTreeBio = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreeBio, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.BiographyCharacteristicID, value: CharacteristicOperation(task: .multiRead, mandatory: false)),
			.leaf(key: CBUUID.BiographySignatureCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: false))
		])
	])

	/// Dependencies of the operations. The root node is the start state. Once all leaf nodes finish, the connection is closed.
	///
	/// Must not be static, because `PeripheralOperation` is a reference type!
	private let opTreeGraphDiscovery: [KeyValueTree<PeripheralOperation, Void>]

	/// The callback dispatch queue of the `CBCentralManager`.
	private let dQueue: DispatchQueue

	/// The operation manager handling the process.
	private var opManager: PeripheralOperationTreeManager

	/// Challenge sent during the authentication process.
	private var nonce = Data()

	/// Challenge received during the authentication process.
	private var remoteNonce = Data()

	/// Amount of recoverable failures encountered.
	private var failures = -1

	/// Strips away the root operation ID.
	private func sub(model: KeyValueTree<CBUUID, Data>) throws -> KeyValueTree<CodingKey, Data> {
		guard let modelNode = model.directSubNode(with: CBUUID.PeereeServiceID) else {
			throw createApplicationError(localizedDescription: "malformed model")
		}

		return modelNode.mapTypes({ CBUUIDCodingKey($0) }, { $0 })
	}
}

fileprivate struct VerificationData: Codable {
	let nonceSignature: Data
	let publicKeyData: Data
	let peerIDSignature: Data

	enum CodingKeys: String, CodingKey {
		case nonceSignature = "79427315-3071-4EA1-AD76-3FF04FCD51CF"
		case publicKeyData = "2EC65417-7DE7-459B-A9CC-67AD01842A4F"
		case peerIDSignature = "D05A4FA4-F203-4A76-A6EA-560152AD74A5"
	}
}

fileprivate struct RemoteIdentificationData: Codable {
	let remoteNonce: Data

	enum CodingKeys: String, CodingKey {
		case remoteNonce = "21AA8B5C-34E7-4694-B3E6-8F51A79811F3"
	}
}

fileprivate struct PeerData: Codable {
	let aggregateData: Data
	let nickname: Data
	let aggregateDataSignature: Data
	let nicknameSignature: Data

	enum CodingKeys: String, CodingKey {
		case aggregateData = "4E0E2DB5-37E1-4083-9463-1AAECABF9179"
		case nickname = "AC5971AF-CB30-4ABF-A699-F13C8E286A91"
		case aggregateDataSignature = "17B23EC4-F543-48C6-A8B8-F806FE035F10"
		case nicknameSignature = "B69EB678-ABAC-4134-828D-D79868A6CB4A"
	}
}

fileprivate struct PortraitData: Codable {
	let portrait: Data
	let portraitSignature: Data

	enum CodingKeys: String, CodingKey {
		case portrait = "DCB9A435-2795-4D6A-BE5D-854CE1EA8890"
		case portraitSignature = "44BFB98E-56AB-4436-9F14-7277C5D6A8CA"
	}
}

fileprivate struct BioData: Codable {
	let bio: String
	let bioSignature: Data

	enum CodingKeys: String, CodingKey {
		case bio = "08EC3C63-CB96-466B-A591-40F8E214BE74"
		case bioSignature = "1198D287-23DD-4F8A-8F08-0EB6B77FBF29"
	}
}
