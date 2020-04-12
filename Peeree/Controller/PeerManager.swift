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

public enum PeerDistance {
	case unknown, close, nearby, far
}

public class PeerManager: RemotePeerDelegate, LocalPeerDelegate {
	public enum NotificationInfoKey: String {
		case peerID, error
	}
	
	public enum Notifications: String {
		case verified, verificationFailed
		case pictureLoaded
		case messageSent, messageReceived, unreadMessageCountChanged
		
		func post(_ peerID: PeerID) {
			postAsNotification(object: nil, userInfo: [NotificationInfoKey.peerID.rawValue : peerID])
		}
	}
	
	public let peerID: PeerID
	private var remotePeerManager: RemotePeerManager { return PeeringController.shared._remote }
	private var localPeerManager: LocalPeerManager { return PeeringController.shared._local }
	
	init(peerID: PeerID) {
		self.peerID = peerID
	}
	
	private var rangeBlock: ((PeerID, PeerDistance) -> Void)? = nil
	
	private var receivedUnverifiedPinMatchIndication: Bool = false
	
	/// thread-safety: write-synced (only writes are assured to be on the same thread
	private(set) var verified = false
	
	public var pictureClassification: AccountController.ContentClassification = .none
	public var pictureHash: Data? = nil
	public var cgPicture: CGImage? = nil
	
	/// access from main thread *only*!
	public var transcripts = [Transcript]()
	/// access from main thread *only*!
	public var unreadMessages = 0 {
		didSet { if oldValue != unreadMessages { Notifications.unreadMessageCountChanged.post(peerID) } }
	}
	
	public var peerInfo: PeerInfo? {
		return remotePeerManager.getPeerInfo(of: peerID)
	}
	
	public var pictureLoadProgress: Progress? {
		return remotePeerManager.loadProgress(for: CBUUID.PortraitCharacteristicID, of: peerID)
	}
	
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
	
	public func range(_ block: @escaping (PeerID, PeerDistance) -> Void) {
		rangeBlock = block
		remotePeerManager.range(peerID)
	}
	
	public func stopRanging() {
		rangeBlock = nil
	}
	
	public func loadPicture() -> Progress? {
		guard let peer = peerInfo, peer.hasPicture && cgPicture == nil else { return nil }
		return remotePeerManager.loadResource(of: peerID, characteristicID: CBUUID.PortraitCharacteristicID, signatureCharacteristicID: CBUUID.PortraitSignatureCharacteristicID)
	}
	
	public func indicatePinMatch() {
		guard peerInfo?.pinMatched ?? false else { return }
		remotePeerManager.reliablyWrite(data: true.binaryRepresentation, to: CBUUID.PinMatchIndicationCharacteristicID, of: peerID, callbackQueue: DispatchQueue.global()) { _error in
			// TODO either handle failure or make non-reliable
			if let error = _error { NSLog("indicated pin match failed: \(error)") }
		}
	}
	
	public func verify() {
		verified = false
		remotePeerManager.verify(peerID)
	}
	
	// calls completion on main thread always
	public func send(message: String, completion: @escaping (Error?) -> Void) {
		guard let data = message.data(prefixedEncoding: message.smallestEncoding) else {
			DispatchQueue.main.async {
				completion(NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Could not encode message.", comment: "Error during bluetooth message sending")]))
			}
			return
		}
		return remotePeerManager.reliablyWrite(data: data, to: CBUUID.MessageCharacteristicID, of: peerID, callbackQueue: DispatchQueue.main) { error in
			if error == nil {
				self.transcripts.append(Transcript(direction: .send, message: message))
				Notifications.messageSent.post(self.peerID)
			}
			completion(error)
		}
	}
	
	// MARK: RemotePeerDelegate
	
	func didRange(_ peerID: PeerID, rssi: NSNumber?, error: Error?) {
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
	
	func loaded(picture: CGImage, of peerID: PeerID, hash: Data) {
		cgPicture = picture
		pictureHash = hash
		AccountController.shared.containsObjectionableContent(imageHash: hash) { containsObjectionableContent in
			self.pictureClassification = containsObjectionableContent
			Notifications.pictureLoaded.post(peerID)
		}
	}
	
	func failedVerification(of peerID: PeerID, error: Error) {
		verified = false
		Notifications.verificationFailed.post(peerID)
	}
	
	func didVerify(_ peerID: PeerID) {
		verified = true
		Notifications.verified.post(peerID)
		localPeerManager.dQueue.async {
			if self.receivedUnverifiedPinMatchIndication {
				self.receivedPinMatchIndication()
			}
		}
	}
	
	// MARK: LocalPeerDelegate
	
	func receivedPinMatchIndication() {
		guard verified, let peer = peerInfo else {
			// update pin status later when peer is verified
			receivedUnverifiedPinMatchIndication = true
			return
		}
		
		AccountController.shared.updatePinStatus(of: peer)
	}
	
	func received(message: String) {
		guard pinState == .pinned else { return }
		
		DispatchQueue.main.async {
			self.transcripts.append(Transcript(direction: .receive, message: message))
			self.unreadMessages += 1
			Notifications.messageReceived.post(self.peerID)
		}
	}
}

extension PeerManager {
	enum PinState {
		case pinned, pinning, notPinned
	}
	
	enum DownloadState {
		case notDownloaded, downloading, downloaded
	}
	
	var isLocalPeer: Bool { return self.peerID == UserPeerManager.instance.peer.peerID }
	var isOnline: Bool { return PeeringController.shared.peering }
	var isAvailable: Bool { return PeeringController.shared.remote.availablePeers.contains(self.peerID) }
	
	var pictureDownloadState: DownloadState {
		if cgPicture == nil {
			return self.pictureLoadProgress != nil ? .downloading : .notDownloaded
		} else {
			return .downloaded
		}
	}
	
	var pictureDownloadProgress: Double {
		return self.pictureLoadProgress?.fractionCompleted ?? 0.0
	}
	
	var pinState: PinState {
		if let peer = peerInfo, peer.pinned {
			return .pinned
		} else {
			return AccountController.shared.isPinning(peerID) ? .pinning : .notPinned
		}
	}
	
	public var verificationStatus: String {
		if verified {
			return NSLocalizedString("verified", comment: "Verification status of peer")
		} else {
			return NSLocalizedString("not verified", comment: "Verification status of peer")
		}
	}
}
