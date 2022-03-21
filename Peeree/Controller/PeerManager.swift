//
//  PeerManager.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.01.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CoreBluetooth
import CoreGraphics

/// An approximisation of the distance to the peer's phone.
public enum PeerDistance {
	case unknown, close, nearby, far
}

/// This class is the interface between the Bluetooth and the UI part of the application.
class PeerManager: PeeringDelegate, PeerInteraction, ServerChatManager {
	// MARK: - Public and Internal

	init(peerID: PeerID, remotePeerManager: RemotePeerManager) {
		self.peerID = peerID
		self.remotePeerManager = remotePeerManager
	}

	// MARK: Constants
	
	let peerID: PeerID

	// MARK: Methods

	// MARK: PeerInteraction

	public func range(_ block: @escaping (PeerID, PeerDistance) -> Void) {
		rangeBlock = block
		remotePeerManager.range(peerID)
	}

	public func stopRanging() {
		rangeBlock = nil
	}

	public func loadLocalPicture() {
		PeeringController.shared.loadPortraitFromDisk(of: peerID)
	}

	public func loadPicture(callback: @escaping (Progress?) -> ()) {
		remotePeerManager.loadResource(of: peerID, characteristicID: CBUUID.PortraitCharacteristicID, signatureCharacteristicID: CBUUID.PortraitSignatureCharacteristicID, callback: callback)
	}

	public func loadBio(callback: @escaping (Progress?) -> ()) {
		remotePeerManager.loadResource(of: peerID, characteristicID: CBUUID.BiographyCharacteristicID, signatureCharacteristicID: CBUUID.BiographySignatureCharacteristicID, callback: callback)
	}

	public func verify() {
		remotePeerManager.verify(peerID)
	}

	public func send(message: String, completion: @escaping (Error?) -> Void) {
		ServerChatController.getOrSetupInstance { instanceResult in
			switch instanceResult {
			case .failure(let error):
				completion(error)
			case .success(let serverChat):
				serverChat.send(message: message, to: self.peerID) { completion($0.error) }
			}
		}
	}

	// MARK: PeeringDelegate
	// all these methods come from one single queue

	public func indicatePinMatch() {
		guard AccountController.shared.hasPinMatch(peerID) else { return }
		remotePeerManager.reliablyWrite(data: true.binaryRepresentation, to: CBUUID.PinMatchIndicationCharacteristicID, of: peerID, callbackQueue: DispatchQueue.global()) { _error in
			// TODO handle failure
			if let error = _error { NSLog("ERROR: indicating pin match failed: \(error)"); return }
		}
	}

	func didRange(rssi: NSNumber?, error: Error?) {
		guard error == nil else {
			NSLog("Error updating range: \(error!.localizedDescription)")
			rerange(timeInterval: 7.0, tolerance: 2.5, distance: .unknown)
			return
		}
		switch rssi!.intValue {
		case -60 ... Int.max:
			rerange(timeInterval: 3.0, tolerance: 1.0, distance: .close)
		case -80 ... -60:
			rerange(timeInterval: 4.0, tolerance: 1.5, distance: .nearby)
		case -100 ... -80:
			rerange(timeInterval: 5.0, tolerance: 2.0, distance: .far)
		default:
			rerange(timeInterval: 7.0, tolerance: 2.5, distance: .unknown)
		}
	}
	
	func loaded(picture: CGImage, hash: Data, classification: AccountController.ContentClassification) {
		self.publish { model in
			model.loadedAndClassified(portrait: picture, hash: hash, classification: classification)
		}
	}

	func loaded(biography: String) {
		publish { model in
			model.biography = biography
		}
	}

	func failedVerification(error: Error) {
		verified = false
		publish { model in
			model.verified = false
		}
	}

	func didVerify() {
		verified = true
		publish { model in
			model.verified = true
		}
		if receivedUnverifiedPinMatchIndication {
			receivedPinMatchIndication()
		}
	}

	func didRemoteVerify() {}

	func receivedPinMatchIndication() {
		guard verified else {
			// update pin status later when peer is verified
			receivedUnverifiedPinMatchIndication = true
			return
		}

		receivedUnverifiedPinMatchIndication = false
		remotePeerManager.authenticate(peerID)

		DispatchQueue.main.async {
			guard let model = PeerViewModelController.viewModels[self.peerID] else { return }

			AccountController.shared.updatePinStatus(of: model.peer.id, force: false)
		}
	}

	// MARK: ServerChatManager

	func received(message: String, at: Date) {
		publish { model in
			model.received(message: message, at: at)
		}
	}

	public func didSend(message: String, at: Date) {
		publish { model in
			model.didSend(message: message, at: at)
		}
	}

	func catchUp(messages: [Transcript], unreadCount: Int) {
		publish { model in
			model.catchUp(messages: messages, unreadCount: unreadCount)
		}
	}

	// MARK: - Private

	// MARK: Constants

	private let remotePeerManager: RemotePeerManager

	// MARK: Variables

	private var verified = false

	private var rangeBlock: ((PeerID, PeerDistance) -> Void)? = nil

	private var receivedUnverifiedPinMatchIndication: Bool = false

	// MARK: Methods

	@objc func callRange(_ timer: Timer) {
		remotePeerManager.range(timer.userInfo as! PeerID)
	}

	private func rerange(timeInterval: TimeInterval, tolerance: TimeInterval, distance: PeerDistance) {
		guard rangeBlock != nil else { return }

		let timer: Timer
		if #available(iOS 10.0, *) {
			timer = Timer(timeInterval: timeInterval, repeats: false) { _ in
				self.remotePeerManager.range(self.peerID)
			}
		} else {
			timer = Timer(timeInterval: timeInterval, target: self, selector: #selector(callRange(_:)), userInfo: peerID, repeats: false)
		}
		timer.tolerance = tolerance

		RunLoop.main.add(timer, forMode: RunLoop.Mode.default)

		rangeBlock?(peerID, distance)
	}

	/// publish changes to the model on the main thread
	private func publish(completion: @escaping (inout PeerViewModel) -> ()) {
		DispatchQueue.main.async {
			PeerViewModelController.modify(peerID: self.peerID, modifier: completion)
		}
	}
}
