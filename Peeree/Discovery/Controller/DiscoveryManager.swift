//
//  DiscoveryManager.swift
//  PeereeDiscovery
//
//  Created by Christopher Kobusch on 10.06.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth

import KeychainWrapper
import PeereeCore
import BLEPeripheralOperations

/// Central delegate for discovery operations.
protocol DiscoveryManagerDelegate: PeerDiscoveryOperationManagerDelegate,
								   PeerVerificationOperationManagerDelegate {
	/// Bluetooth network state change indicator.
	///
	/// - Parameter isReady: If `true`, Bluetooth is up and we have permission to access it, otherwise `false`.
	/// You may call ``DiscoveryManager/scan()``, if `isReady`.
	func discoveryManager(isReady: Bool)

	/// The scan process stopped.
	///
	/// Either ``DiscoveryManager/stopScan()`` was called directly, or Bluetooth was turned of, or permissions where revoked.
	func scanningStopped()

	/// An earlier discovered person was again encountered.
	func peerAppearedAgain(_ peerID: PeerID)

	/// Bluetooth connection was disconnected.
	func peerDisappeared(_ peerID: PeerID, cbPeerID: UUID)
}

/// Retrieves information from remote peers.
final class DiscoveryManager: NSObject, CBCentralManagerDelegate, PeerIdentificationOperationManagerDelegate {

	/// The account of the user.
	private(set) var userIdentity: (PeerID, KeyPair)? = nil

	/// Needed for writing nonces; `16` is a good estimation.
	private(set) var blockSize = 16

	/// Main informed party of the discovery process.
	weak var delegate: DiscoveryManagerDelegate?

	/// Create the main discovery class.
	override init() {
		centralManager = nil
		super.init()
		centralManager = CBCentralManager(delegate: self, queue: dQueue, options: [CBCentralManagerOptionShowPowerAlertKey : 1])
	}

	/// Initiate the discovery process.
	func scan() {
		self.centralManager
			.scanForPeripherals(withServices: [CBUUID.PeereeServiceID])
	}

	/// Stop the discovery process.
	func stopScan(turnOff: Bool = true) {
		if turnOff {
			self.centralManager.stopScan()
		}

		// We may NOT do `self.encounteredPeripherals.removeAll()` here,
		// as this deallocates the CBPeripheral and thus didDisconnect is never
		// invoked (and the central manager does not even recognize that we
		// disconnected internally)!
		for (peripheral, _) in self.encounteredPeripherals {
			self.disconnect(peripheral)
		}

		self.delegate?.scanningStopped()
	}

	/// Defines the values of our Peeree Identity.
	func set(userIdentity: (peerID: PeerID, keyPair: KeyPair)?) {
		self.userIdentity = userIdentity
		self.blockSize =
		(try? userIdentity?.keyPair.privateKeyBlockSize) ?? self.blockSize
	}

	/// Call this at best immediately from `PeerDiscoveryOperationManagerDelegate.peerDiscoveryFinished(peerLastChangedDate:, of:)`.
	func discoveryCompleted(of peerID: PeerID, lastChanged: Date) {
		self.peripheralPeerIDs[peerID].map {
			_ = self.knownPeripheralIDs.insert($0.identifier)
		}

		self.completedPeerDiscoveries[peerID] = lastChanged
	}

	/// Start the operation tree for additional, large info retrieval.
	func loadAdditionalInfo(of peerID: PeerID, loadPortrait: Bool) {
		guard let peripheral = self.peripheralPeerIDs[peerID] else { return }

		do {
			try self.discoveryOperations[peerID]?
				.beginLoadAdditionalInfo(on: peripheral,
										 loadPortrait: loadPortrait)
		} catch {
			elog(Self.LogTag, "error when loading add. info: \(error)")
		}
	}

	/// Begin measuring the distance to a peer.
	func range(_ peerID: PeerID) {
		self.peripheralPeerIDs[peerID]?.readRSSI()
	}

	/// Cancel all ongoing operations (if any) and close the connection to a peer.
	func closeConnection(with peerID: PeerID) {
		self.peripheralPeerIDs[peerID].map { self.disconnect($0) }
	}

	// MARK: PeerIdentificationOperationManagerDelegate

	func foundPeer(_ peerID: PeereeCore.PeerID, lastChangedDate: Date, of peripheral: CBPeripheral) {
		self.encounteredPeripherals[peripheral] = peerID
		self.peripheralPeerIDs[peerID] = peripheral

		if let syncedDate = self.completedPeerDiscoveries[peerID], syncedDate >= lastChangedDate {
			// if the advertised changed data is not newer than our last known state, immediately disconnect
			self.disconnect(peripheral)
			delegate?.peerAppearedAgain(peerID)
			return
		}

		// TODO: test if we can delete this if statement
//		if let peereeService = peripheral.peereeService {
//			// This characteristic is optional (only present on Android).
//			// Since the operation tree does not yet support optional characteristics, we handle this exception here by hand.
//			peripheral.discoverCharacteristics([CBUUID.ConnectBackCharacteristicID], for: peereeService)
//		}

		let opManager: PeerVerificationOperationManager
		if let opm = self.verifyOperations[peerID] {
			opManager = opm
		} else {
			opManager = PeerVerificationOperationManager(
				peerID: peerID, nonceLength: self.blockSize,
				dQueue: self.dQueue)
			self.verifyOperations[peerID] = opManager
		}

		opManager.delegate = self.delegate
		opManager.begin(on: peripheral)
	}

	func beginDiscovery(on peerID: PeereeCore.PeerID,
						publicKey: KeychainWrapper.AsymmetricPublicKey) {
		guard let peripheral = self.peripheralPeerIDs[peerID] else { return }

		let opManager: PeerDiscoveryOperationManager
		if let opm = self.discoveryOperations[peerID] {
			opManager = opm
		} else {
			opManager = PeerDiscoveryOperationManager(
				peerID: peerID,
				// hack: to not pass around the last changed date, just use now
				lastChanged: Date(), publicKey: publicKey,
				dQueue: self.dQueue, userIdentity: self.userIdentity)
			self.discoveryOperations[peerID] = opManager
		}

		opManager.delegate = self.delegate
		opManager.beginDiscovery(on: peripheral)
	}

	func peerIdentificationFailed(_ error: Error, of peripheral: CBPeripheral) {
		if let pError = error as? PeripheralOperationUnrecoverableError {
			if case .cancelled = pError { } else {
				elog(Self.LogTag, "peer identification failed \(pError)")
			}
		} else {
			elog(Self.LogTag, "peer identification failed \(error)")
		}
		self.disconnect(peripheral)
	}

	// MARK: - Private

	// Log tag.
	private static let LogTag = "DiscoveryManager"

	/// Central queue for discovery operations.
	private let dQueue = DispatchQueue(label: "com.peeree.DiscoveryManager", qos: .default, attributes: [])

	/// Used to ignore discovered peripherals that we already completed discovery with.
	private var knownPeripheralIDs = Set<UUID>()

	/// All readable remote peers the app is currently connected to.
	///
	/// The keys are updated immediately when a new peripheral shows up, as we have to keep a reference to it. However, the values are not filled until the peripheral tell's us their ID.
	private var encounteredPeripherals = [CBPeripheral : PeerID?]()

	/// Maps the identifiers of peripherals to the IDs of the peers they represent.
	private var peripheralPeerIDs = [PeerID : CBPeripheral]()

	/// First operation carried out when a peer is encountered.
	private var identifyOperations = [CBPeripheral : PeerIdentificationOperationManager]()

	/// First operation carried out when a peer is encountered.
	private
	var verifyOperations = [PeerID : PeerVerificationOperationManager]()

	/// Manager to retrieve data from a peer.
	private var discoveryOperations = [PeerID : PeerDiscoveryOperationManager]()

	/// The last changed data of each completely discovered peer.
	private var completedPeerDiscoveries = [PeerID : Date]()

	/// The main class to interact with the Bluetooth subsystem.
	private var centralManager: CBCentralManager!

	/// Whether the underlying `CBCentralManager` is scanning for peripherals.
	var isScanning: Bool {
		if #available(macOS 10.13, iOS 6.0, *) {
			return centralManager.isScanning
		} else {
			return true // shitty shit is not available on mac - what the fuck?
		}
	}

	/// Retrieve the PeerID of a peripheral, if we already know it.
	private func peerID(of peripheral: CBPeripheral) -> PeerID? {
		guard let peerID = encounteredPeripherals[peripheral] else { return nil }
		return peerID
	}

	/// Close the connection to `peripheral`.
	private func disconnect(_ peripheral: CBPeripheral) {
		self.identifyOperations[peripheral]?.cancel()
		self.encounteredPeripherals[peripheral]?.map {
			self.discoveryOperations[$0]?.cancel()
			self.verifyOperations[$0]?.cancel()
		}
		centralManager.cancelPeripheralConnection(peripheral)
	}

	// MARK: CBCentralManagerDelegate

	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		// needed for state restoration as we may not have a "clean" state here anymore
		switch central.state {
		case .unknown, .resetting:
			// just wait
			break
		case .poweredOff, .unsupported, .unauthorized:
			stopScan(turnOff: false)
		case .poweredOn:
			break
			// TODO: resume opManager
//			for (peripheral, opManager) in encounteredPeripherals {
//			}
		default:
			break
		}

		delegate?.discoveryManager(isReady: central.state == .poweredOn)
	}

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		wlog(Self.LogTag, "Failed to connect to \(peripheral) (\(error?.localizedDescription ?? "")).")
		disconnect(peripheral)
	}

	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
		//dlog(Self.LogTag, "Discovered peripheral \(peripheral) with advertisement data \(advertisementData).")

		guard !self.knownPeripheralIDs.contains(peripheral.identifier) else {
			return
		}

		if encounteredPeripherals[peripheral] == nil {
			encounteredPeripherals.updateValue(nil, forKey: peripheral)
		}

		if peripheral.state == .disconnected {
			central.connect(peripheral, options: nil)
		}
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		dlog(Self.LogTag, "Connected peripheral \(peripheral)")
		let opManager: PeerIdentificationOperationManager
		if let opm = self.identifyOperations[peripheral] {
			opManager = opm
		} else {
			opManager = PeerIdentificationOperationManager(dQueue: self.dQueue)
			self.identifyOperations[peripheral] = opManager
		}

		opManager.delegate = self
		opManager.begin(on: peripheral)
	}

	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		dlog(Self.LogTag, "Disconnected peripheral \(peripheral) \(error?.localizedDescription ?? "")")
		// error is set when the peripheral disconnected without us having called disconnectPeripheral before, so in almost all cases...

		self.identifyOperations.removeValue(forKey: peripheral)
		guard let peerID = encounteredPeripherals.removeValue(forKey: peripheral), let peerID else { return }
		self.peripheralPeerIDs.removeValue(forKey: peerID)
		self.discoveryOperations.removeValue(forKey: peerID)
		self.verifyOperations.removeValue(forKey: peerID)
		delegate?.peerDisappeared(peerID, cbPeerID: peripheral.identifier)
	}
}
