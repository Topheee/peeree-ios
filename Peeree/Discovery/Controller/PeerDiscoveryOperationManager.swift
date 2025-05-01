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
import CryptoKit

import PeereeCore
import KeychainWrapper
import KeyValueTree
import KeyValueTreeCoding
import BLEPeripheralOperations
import CSProgress

/// Provides a means to react on key steps of the discovery process.
protocol PeerDiscoveryOperationManagerDelegate: AnyObject {

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

	/// The PeerID of the remote peer we are discovering.
	let peerID: PeerID

	/// The account of the user, if available.
	private(set) var userIdentity: (PeerID, KeyPair)? = nil

	/// Informed party of the discovery process.
	weak var delegate: PeerDiscoveryOperationManagerDelegate?

	/// Current state including information necessary to process further steps.
	private(set) var state: PeerDiscoveryState

	/// Create an the operation manager. Start it by using `beginDiscovery()`.
	init(peerID: PeerID, lastChanged: Date, dQueue: DispatchQueue,
		 userIdentity: (PeerID, KeyPair)?) {
		self.peerID = peerID
		self.state = .discovered(lastChanged)
		self.dQueue = dQueue
		self.userIdentity = userIdentity

		self.opManager = PeripheralOperationTreeManager(
			operationTrees: [self.opTreeGraph], queue: dQueue)
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
		switch error {
		case .parallelUse:
			break
		default:
			wlog(Self.LogTag, "peripheral operation \(operation.id)"
				 + " encountered recoverable error \(error.localizedDescription)"
				 + " (failures: \(failures)).")

			failures += 1
		}

		return failures < Self.MaxFailures
	}

	func peripheralOperation(_ operation: PeripheralOperation, writeDataFor characteristicID: CBUUID, of peripheral: CBPeripheral) throws -> Data {
		switch characteristicID {
		case CBUUID.RemoteUUIDCharacteristicID:
			guard let userPeerID = self.userIdentity?.0 else {
				throw unexpectedNilError()
			}

			return userPeerID.encode()

		default:
			throw createApplicationError(localizedDescription: "unknown peripheral write operation")
		}
	}

	func peripheralOperationFinished(_ operation: PeripheralOperation, model: KeyValueTree<CBUUID, Data>, of peripheral: CBPeripheral) {
		switch operation.id {

		case Self.idOpTreePeerData:
			guard case let .identified(identified) = self.state else {
				assertionFailure("wrong state \(self.state) after retrieving idOpTreePeerData.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsistency."))
				return
			}

			let peerData: PeerData
			let identity: PeereeIdentity
			do {
				peerData = try self.decoder
					.decode(PeerData.self, from: sub(model: model))

				try identified.publicKey.verify(message: peerData.aggregateData, signature: peerData.aggregateDataSignature)
				try identified.publicKey.verify(message: peerData.nickname, signature: peerData.nicknameSignature)

				identity = try PeereeIdentity(peerID: self.peerID, publicKey: identified.publicKey)
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

			delegate?.loaded(info: peerInfo, of: identity)

		case Self.idOpTreeBio:
			guard case let .scraping(identified) = self.state else {
				assertionFailure("wrong state \(self.state) after retrieving idOpTreeBio.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsisteny."))
				return
			}

			do {
				let subModel = try sub(model: model)
				let bioData = try self.decoder
					.decode(BioData.self, from: subModel)

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
				assertionFailure("wrong state \(self.state) after retrieving idOpTreePortrait.")
				delegate?.peerDiscoveryFailed(createApplicationError(localizedDescription: "Internal state inconsisteny."))
				return
			}

			let portraitData: PortraitData
			do {
				portraitData = try self.decoder
					.decode(PortraitData.self, from: sub(model: model))

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

			let hash = Data(SHA256.hash(data: portraitData.portrait))
			delegate?.loaded(picture: image, of: self.peerID,
							 hash: hash)

		default:
			assertionFailure("unknown peripheral operation \(operation.id.uuidString) finished.")
		}
	}

	// MARK: - Private

	// Log tag.
	private static let LogTag = "PeerDiscoveryOperationManager"

	/// Maximum amount of failed 'recoverable' Bluetooth operations, before the process is aborted.
	private static let MaxFailures = 3

	/// The Decoder to unmarshal the results of the sub-operations.
	private let decoder = KeyValueTreeCoding.DataTreeDecoder()

	/// The ID of the first remote authentication step.
	private static let idOpTreeRemoteAuth1UUID = UUID()
	private static
	var idOpTreeRemoteAuth1: CBUUID { CBUUID(nsuuid: idOpTreeRemoteAuth1UUID) }

	/// The ID of the second remote authentication step.
	private static let idOpTreeRemoteAuth2UUID = UUID()
	private static
	var idOpTreeRemoteAuth2: CBUUID { CBUUID(nsuuid: idOpTreeRemoteAuth2UUID) }

	/// The ID of the main information retrieval step.
	private static let idOpTreePeerDataUUID = UUID()
	private static
	var idOpTreePeerData: CBUUID { CBUUID(nsuuid: idOpTreePeerDataUUID) }

	/// The ID of the portrait retrieval step.
	private static let idOpTreePortraitUUID = UUID()
	private static
	var idOpTreePortrait: CBUUID { CBUUID(nsuuid: idOpTreePortraitUUID) }

	/// The ID of the biography retrieval step.
	private static let idOpTreeBioUUID = UUID()
	private static
	var idOpTreeBio: CBUUID { CBUUID(nsuuid: idOpTreeBioUUID) }

	/// The main information retrieval step.
	private static
	var opTreePeerInfo: KeyValueTree<CBUUID, CharacteristicOperation> {
		KeyValueTree<CBUUID, CharacteristicOperation>
			.branch(key: idOpTreePeerData, nodes: [
				.branch(key: CBUUID.PeereeServiceID, nodes: [
					.leaf(key: CBUUID.AggregateCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true)),
					.leaf(key: CBUUID.NicknameCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true)),
					.leaf(key: CBUUID.AggregateSignatureCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true)),
					.leaf(key: CBUUID.NicknameSignatureCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true))
				])
			])
	}

	/// The portrait retrieval step.
	private static
	var opTreePortrait: KeyValueTree<CBUUID, CharacteristicOperation> {
		KeyValueTree<CBUUID, CharacteristicOperation>
			.branch(key: idOpTreePortrait, nodes: [
				.branch(key: CBUUID.PeereeServiceID, nodes: [
					.leaf(key: CBUUID.PortraitCharacteristicID,
						  value: CharacteristicOperation(task: .multiRead,
														 mandatory: false)),
					.leaf(key: CBUUID.PortraitSignatureCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: false))
				])
			])
	}

	/// The biography retrieval step.
	private static
	var opTreeBio: KeyValueTree<CBUUID, CharacteristicOperation> {
		KeyValueTree<CBUUID, CharacteristicOperation>
			.branch(key: idOpTreeBio, nodes: [
				.branch(key: CBUUID.PeereeServiceID, nodes: [
					.leaf(key: CBUUID.BiographyCharacteristicID,
						  value: CharacteristicOperation(task: .multiRead,
														 mandatory: false)),
					.leaf(key: CBUUID.BiographySignatureCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: false))
				])
			])
	}

	/// Dependencies of the operations. The root node is the start state. Once all leaf nodes finish, the connection is closed.
	///
	/// Must not be static, because `PeripheralOperation` is a reference type!
	private let opTreeGraph = KeyValueTree<PeripheralOperation, Void>
		.leaf(key: PeripheralOperation(
			characteristicOperationTree: PeerDiscoveryOperationManager
				.opTreePeerInfo), value: ())

	/// The callback dispatch queue of the `CBCentralManager`.
	private let dQueue: DispatchQueue

	/// The operation manager handling the process.
	private var opManager: PeripheralOperationTreeManager

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
