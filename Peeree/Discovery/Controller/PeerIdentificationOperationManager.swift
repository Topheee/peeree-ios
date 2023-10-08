//
//  PeerIdentificationOperationManager.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 01.07.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//


import Foundation
import CoreBluetooth

import PeereeCore
import KeyValueTree
import KeyValueTreeCoding
import BLEPeripheralOperations

/// Provides updates on peer identification tasks.
protocol PeerIdentificationOperationManagerDelegate: AnyObject {
	/// All available information of a peer has been read successfully.
	func foundPeer(_ peerID: PeerID, lastChangedDate: Date, of peripheral: CBPeripheral)

	/// Something went wrong during the discovery.
	func peerIdentificationFailed(_ error: Error, of peripheral: CBPeripheral)
}

/// Controls the initial identification of a peripheral, i.e., which PeerID they have; plus some more initial connection setup.
final class PeerIdentificationOperationManager: PeripheralOperationTreeManagerDelegate {

	/// Informed party of the identification process.
	weak var delegate: PeerIdentificationOperationManagerDelegate?

	/// Create the identifaction process manager.
	init(dQueue: DispatchQueue) {
		self.opManager = PeripheralOperationTreeManager(operationTrees: [self.opTreeGraph], queue: dQueue)
	}

	/// Begin the identification process for a specific peripheral. Only one operation may be started at a time.
	public func begin(on peripheral: CBPeripheral) {
		assert(self.peripheral == nil)

		self.peripheral = peripheral
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

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, beganMultiWrite characteristicID: CBUUID, with progress: Progress) {
		// ignored
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, beganMultiRead characteristicID: CBUUID, with progress: Progress) {
		// ignored
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, encounteredUnrecoverableError error: BLEPeripheralOperations.PeripheralOperationUnrecoverableError) {
		guard let peripheral = self.peripheral else {
			preconditionFailure()
		}

		delegate?.peerIdentificationFailed(error, of: peripheral)
	}

	func peripheralOperation(_ operation: BLEPeripheralOperations.PeripheralOperation, encounteredRecoverableError error: BLEPeripheralOperations.PeripheralOperationRecoverableError) -> Bool {
		failures += 1
		return failures < Self.MaxFailures
	}

	func peripheralOperation(_ operation: PeripheralOperation, writeDataFor characteristicID: CBUUID, of peripheral: CBPeripheral) throws -> Data {
		switch characteristicID {
		case CBUUID.ConnectBackCharacteristicID:
			return true.binaryRepresentation

		default:
			throw createApplicationError(localizedDescription: "unknown peripheral identification write operation")
		}
	}

	func peripheralOperationFinished(_ operation: PeripheralOperation, model: KeyValueTree<CBUUID, Data>, of peripheral: CBPeripheral) {
		switch operation.id {
		case Self.idOpTreeIdentification:
			guard let peripheral = self.peripheral else {
				preconditionFailure()
			}
			guard let modelNode = model.directSubNode(with: CBUUID.PeereeServiceID) else {
				self.delegate?.peerIdentificationFailed(createApplicationError(localizedDescription: "malformed model"), of: peripheral)
				return
			}

			do {
				Self.decoder.stringDecodingStrategy = .fixed(.utf8)
				let identificationData = try Self.decoder.decode(IdentificationData.self, from: modelNode.mapTypes({ CBUUIDCodingKey($0) }, { $0 }))

				delegate?.foundPeer(identificationData.peerID, lastChangedDate: identificationData.lastChanged, of: peripheral)
			} catch {
				self.delegate?.peerIdentificationFailed(error, of: peripheral)
			}

		default:
			assertionFailure("unknown peripheral operation \(operation.id.uuidString) finished.")
		}
	}

	/// Maximum amount of failed 'recoverable' Bluetooth operations, before the process is aborted.
	private static let MaxFailures = 3

	/// The Decoder to unmarshal the results of the sub-operations.
	private static let decoder = KeyValueTreeCoding.DataTreeDecoder()

	/// The root ID of the identifaction operation tree.
	private static let idOpTreeIdentification = CBUUID(nsuuid: UUID())

	/// The operation tree to identify a remote peer.
	private static let opTreeIdentification = KeyValueTree<CBUUID, CharacteristicOperation>.branch(key: idOpTreeIdentification, nodes: [
		.branch(key: CBUUID.PeereeServiceID, nodes: [
			.leaf(key: CBUUID.LocalPeerIDCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.LastChangedCharacteristicID, value: CharacteristicOperation(task: .read, mandatory: true)),
			.leaf(key: CBUUID.ConnectBackCharacteristicID, value: CharacteristicOperation(task: .write, mandatory: false))
		])
	])

	/// The operation tree graph.
	///
	/// Must not be static, because `PeripheralOperation` is a reference type!
	private let opTreeGraph = KeyValueTree<PeripheralOperation, Void>.leaf(key: PeripheralOperation(characteristicOperationTree: opTreeIdentification), value: ())

	/// The operation manager handling the process.
	private let opManager: PeripheralOperationTreeManager

	/// Amount of recoverable failures encountered.
	private var failures = -1

	/// The peripheral this process was started for.
	private var peripheral: CBPeripheral?
}

fileprivate struct IdentificationData: Codable {
	let peerID: PeerID
	let lastChanged: Date

	enum CodingKeys: String, CodingKey {
		case peerID = "52FA3B9A-59E8-41AD-BEBE-19826589116A"
		case lastChanged = "6F443A3C-F799-4DC1-A02A-72F2D8EA8B24"
	}
}
