//
//  PeerVerificationOperationManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.03.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//

// Platform Dependencies
import Foundation
import CoreBluetooth

// Internal Dependencies
import PeereeCore

// External Dependencies
import KeychainWrapper
import KeyValueTree
import KeyValueTreeCoding
import BLEPeripheralOperations
import CSProgress

/// Provides updates on peer identification tasks.
protocol PeerVerificationOperationManagerDelegate: AnyObject {

	/// Verify that this identity is actually part of the Peeree network.
	func proof(_ peerID: PeerID, publicKey: AsymmetricPublicKey,
			   identityToken: Data?)

	/// Something went wrong during the discovery.
	func peerVerificationFailed(_ error: Error, of peerID: PeerID)
}

/// Controls the initial identification of a peripheral, i.e., which PeerID they have; plus some more initial connection setup.
final class PeerVerificationOperationManager: PeripheralOperationTreeManagerDelegate {

	/// The PeerID of the remote peer we are discovering.
	let peerID: PeerID

	/// Length of our challenge.
	let nonceLength: Int

	/// Informed party of the identification process.
	weak var delegate: PeerVerificationOperationManagerDelegate?

	/// Create the identifaction process manager.
	init(peerID: PeerID, nonceLength: Int, dQueue: DispatchQueue) {
		self.peerID = peerID
		self.nonceLength = nonceLength
		self.opManager = PeripheralOperationTreeManager(operationTrees: [self.opTreeGraph], queue: dQueue)
	}

	/// Begin the identification process for a specific peripheral. Only one operation may be started at a time.
	public func begin(on peripheral: CBPeripheral) {
		self.opManager.delegate = self
		self.opManager.begin(on: peripheral)
	}

	/// Cancel the identification process.
	public func cancel() {
		self.opManager.cancel()
	}

	// MARK: PeripheralOperationTreeManagerDelegate

	func peripheralOperationTreeFinished(_ manager: BLEPeripheralOperations.PeripheralOperationTreeManager) {
	}

	// MARK: PeripheralOperationManagerDelegate

	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		// ignored
	}

	func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
		// ignored
	}

	// MARK: PeripheralOperationDelegate

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, beganMultiWrite characteristicID: CBUUID, with progress: CSProgress) {
		// ignored
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, beganMultiRead characteristicID: CBUUID, with progress: CSProgress) {
		// ignored
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, encounteredUnrecoverableError error: BLEPeripheralOperations.PeripheralOperationUnrecoverableError) {
		self.delegate?.peerVerificationFailed(error, of: self.peerID)
		self.cancel()
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, encounteredRecoverableError error: BLEPeripheralOperations.PeripheralOperationRecoverableError) -> Bool {
		failures += 1
		return failures < Self.MaxFailures
	}

	func peripheralOperation(
		_ operation: BLEPeripheralOperations.PeripheralOperation,
		encounteredWarning warning: BLEPeripheralOperations.PeripheralOperationUnrecoverableError,
		on characteristicID: CBUUID) {
			elog(
				PeereeDiscovery.LogTag,
				"PeerVerificationOperationManager.peripheralOperation encounteredWarning: \(warning) on characteristic: \(characteristicID.uuidString)")
	}

	func peripheralOperation(_ operation: PeripheralOperation, writeDataFor characteristicID: CBUUID, of peripheral: CBPeripheral) throws -> Data {
		switch characteristicID {

		case CBUUID.AuthenticationCharacteristicID:
			let writeType = CBCharacteristicWriteType.withResponse
			let randomByteCount = min(peripheral.maximumWriteValueLength(for: writeType), self.nonceLength)
			let nonce = try generateRandomData(length: randomByteCount)
			self.nonce = nonce
			return nonce

		default:
			throw createApplicationError(localizedDescription: "unknown peripheral identification write operation")
		}
	}

	func peripheralOperationFinished(_ operation: PeripheralOperation, model: KeyValueTree<CBUUID, Data>, of peripheral: CBPeripheral) {
		switch operation.id {

		case Self.idOpTreeAuth1:
			self.identityToken = try? self.decoder
				.decode(IdentityData.self, from: sub(model: model))
				.identityTokenData

		case Self.idOpTreeAuth2:

			// verify that the peer is in possession of the private key

			let identity: PeereeIdentity
			let pubKey: AsymmetricPublicKey
			do {
				let verificationData = try self.decoder
					.decode(VerificationData.self, from: sub(model: model))

				identity = PeereeIdentity(peerID: self.peerID, publicKeyData: verificationData.publicKeyData)

				pubKey = try identity.publicKey()
				try pubKey.verify(message: nonce, signature: verificationData.nonceSignature)
				try pubKey.verify(message: self.peerID.encode(), signature: verificationData.oldPeerIDSignature)
			} catch {
				delegate?.peerVerificationFailed(error, of: self.peerID)
				self.cancel()
				return
			}

			// verify that the peer is part of the Peeree network

			self.delegate?.proof(self.peerID, publicKey: pubKey,
								  identityToken: self.identityToken)

		default:
			assertionFailure("unknown peripheral operation \(operation.id.uuidString) finished.")
		}
	}

	/// Maximum amount of failed 'recoverable' Bluetooth operations, before the process is aborted.
	private static let MaxFailures = 3

	/// The Decoder to unmarshal the results of the sub-operations.
	// This could be static.
	private let decoder = KeyValueTreeCoding.DataTreeDecoder()

	/// The identity token if the remote user, if available.
	private var identityToken: Data? = nil

	/// Challenge sent during the authentication process.
	private var nonce = Data()

	/// The root ID of the identifaction operation tree.
	private static let idOpTreeVerificationUUID = UUID()
	private static var idOpTreeVerification: CBUUID {
		CBUUID(nsuuid: idOpTreeVerificationUUID)
	}

	/// The ID of the first authentication step.
	private static let idOpTreeAuth1UUID = UUID()
	private static
	var idOpTreeAuth1: CBUUID { CBUUID(nsuuid: idOpTreeAuth1UUID) }

	/// The ID of the second authentication step.
	private static let idOpTreeAuth2UUID = UUID()
	private static
	var idOpTreeAuth2: CBUUID { CBUUID(nsuuid: idOpTreeAuth2UUID) }

	/// The first authentication step.
	private static
	var opTreeAuth1: KeyValueTree<CBUUID, CharacteristicOperation> {
		KeyValueTree<CBUUID, CharacteristicOperation>
			.branch(key: idOpTreeAuth1, nodes: [
				.branch(key: CBUUID.PeereeServiceID, nodes: [
					.leaf(key: CBUUID.AuthenticationCharacteristicID,
						  value: CharacteristicOperation(task: .write,
														 mandatory: true)),
					.leaf(key: CBUUID.IdentityTokenCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: false))
				])
			])
	}

	/// The second authentication step.
	private static
	var opTreeAuth2: KeyValueTree<CBUUID, CharacteristicOperation> {
		KeyValueTree<CBUUID, CharacteristicOperation>
			.branch(key: idOpTreeAuth2, nodes: [
				.branch(key: CBUUID.PeereeServiceID, nodes: [
					.leaf(key: CBUUID.AuthenticationCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true)),
					.leaf(key: CBUUID.PublicKeyCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true)),
					.leaf(key: CBUUID.OldPeerIDSignatureCharacteristicID,
						  value: CharacteristicOperation(task: .read,
														 mandatory: true))
				])
			])
	}

	/// The operation tree graph.
	///
	/// Must not be static, because `PeripheralOperation` is a reference type!
	private let opTreeGraph = KeyValueTree<PeripheralOperation, Void>
		.branch(key: PeripheralOperation(characteristicOperationTree: PeerVerificationOperationManager.opTreeAuth1),
				nodes: [
					.branch(key: PeripheralOperation(characteristicOperationTree: PeerVerificationOperationManager.opTreeAuth2),
							nodes: [])
				])

	/// The operation manager handling the process.
	private let opManager: PeripheralOperationTreeManager

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

fileprivate struct IdentityData: Codable {
	let identityTokenData: Data?

	enum CodingKeys: String, CodingKey {
		case identityTokenData = "02CDB809-9FC4-4F30-9C46-DD6E7B2A1808"
	}
}

fileprivate struct VerificationData: Codable {
	let nonceSignature: Data
	let publicKeyData: Data
	let oldPeerIDSignature: Data

	enum CodingKeys: String, CodingKey {
		case nonceSignature = "79427315-3071-4EA1-AD76-3FF04FCD51CF"
		case publicKeyData = "2EC65417-7DE7-459B-A9CC-67AD01842A4F"
		case oldPeerIDSignature = "D05A4FA4-F203-4A76-A6EA-560152AD74A5"
	}
}

