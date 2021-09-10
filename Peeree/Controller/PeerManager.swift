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
		case pictureLoaded, biographyLoaded
		case messageQueued, messageSent, messageReceived, unreadMessageCountChanged
		
		func post(_ peerID: PeerID) {
			postAsNotification(object: nil, userInfo: [NotificationInfoKey.peerID.rawValue : peerID])
		}
	}

	private var pictureResourceURL: URL {
		// Create a file path to our documents directory
		let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
		return URL(fileURLWithPath: paths[0]).appendingPathComponent("\(peerID.uuidString).jpeg", isDirectory: false)
	}

	public let peerID: PeerID
	private let remotePeerManager = PeeringController.shared._remote
	private let localPeerManager = PeeringController.shared._local
	
	init(peerID: PeerID) {
		self.peerID = peerID
	}
	
	private var rangeBlock: ((PeerID, PeerDistance) -> Void)? = nil
	
	private var receivedUnverifiedPinMatchIndication: Bool = false

	/// thread-safety: write-synced (only writes are guaranteed to be on the same thread)
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
	/// access from main thread *only*!
	public var pendingMessages = [(message: String, completion: (Error?) -> Void)]()
	
	public var peerInfo: PeerInfo? {
		return remotePeerManager.getPeerInfo(of: peerID) ?? PinMatchesController.shared.peerInfo(for: peerID)
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

	public func loadLocalPicture(completion: @escaping (_ loaded: Bool) -> Void) {
		DispatchQueue.global(qos: .background).async {
			if let provider = CGDataProvider(url: self.pictureResourceURL as CFURL),
			   let decodedPicture = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent),
			   let data = provider.data as Data? {
				self.loaded(picture: decodedPicture, of: self.peerID, hash: data.sha256())
				completion(true)
			} else {
				completion(false)
			}
		}
	}

	public func loadPicture() -> Progress? {
		guard let peer = peerInfo, peer.hasPicture && cgPicture == nil else { return nil }
		return remotePeerManager.loadResource(of: peerID, characteristicID: CBUUID.PortraitCharacteristicID, signatureCharacteristicID: CBUUID.PortraitSignatureCharacteristicID)
	}

	public func loadBio() -> Progress? {
		return remotePeerManager.loadResource(of: peerID, characteristicID: CBUUID.BiographyCharacteristicID, signatureCharacteristicID: CBUUID.BiographySignatureCharacteristicID)
	}

	/// loads battery-intense characteristics
	public func loadResources() -> (pictureProgress: Progress?, bioProgress: Progress?) {
		return (loadPicture(), loadBio())
	}

	public func indicatePinMatch() {
		guard peerInfo?.pinMatched ?? false else { return }
		savePicture()
		remotePeerManager.reliablyWrite(data: true.binaryRepresentation, to: CBUUID.PinMatchIndicationCharacteristicID, of: peerID, callbackQueue: DispatchQueue.global()) { _error in
			// TODO handle failure
			if let error = _error { NSLog("ERROR: indicating pin match failed: \(error)"); return }
		}
	}
	
	public func verify() {
		verified = false
		remotePeerManager.verify(peerID)
	}

	/// call from main thread only!
	private func dequeueMessage() {
		guard let (message, completion) = self.pendingMessages.first, self.isAvailable else { return }
		guard let data = message.data(prefixedEncoding: message.smallestEncoding) else {
			completion(NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Could not encode message.", comment: "Error during bluetooth message sending")]))
			return
		}
		self.remotePeerManager.reliablyWrite(data: data, to: CBUUID.MessageCharacteristicID, of: self.peerID, callbackQueue: DispatchQueue.main) { error in
			if let error = error {
				switch error {
				case .bleError(let bleError):
					NSLog("WARN: Sending Message Failed with BLE error: \(bleError.localizedDescription)")
				case .valueTooLong:
					// split first message into two submessages and retry
					let (tooLongMessage, completion) = self.pendingMessages.removeFirst()
					let middleIndex = tooLongMessage.middleIndex
					let middleWhitespace = tooLongMessage[middleIndex...].firstIndex { $0.isWhitespace } ?? middleIndex
					let firstHalf = String(tooLongMessage[..<middleWhitespace])
					let secondHalf = String(tooLongMessage[middleWhitespace...])
					self.pendingMessages.insert((secondHalf, completion), at: 0)
					self.pendingMessages.insert((firstHalf, completion), at: 0)
					self.dequeueMessage()
				default:
					NSLog("WARN: Sending Message Failed: \(error.localizedDescription)")
				}
			} else {
				self.pendingMessages.removeFirst()
				self.transcripts.append(Transcript(direction: .send, message: message))
				Notifications.messageSent.post(self.peerID)
				self.dequeueMessage()
				completion(error)
			}
		}
	}

	/// calls <code>completion</code> on main thread always
	public func send(message: String, completion: @escaping (Error?) -> Void) {
		ServerChatController.withInstance { _serverChatController in
			// we are now on the main queue
/*
			if self.isAvailable || _serverChatController == nil {
				// always prefer sending via Bluetooth
				self.pendingMessages.append((message, completion))
				Notifications.messageQueued.post(self.peerID)
				self.dequeueMessage()
			} else */
			if let serverChatController = _serverChatController {
				serverChatController.send(message: message, to: self.peerID) { result in
					switch result {
					case .success(_):
						completion(nil)
					case .failure(let error):
						completion(error)
					}
				}
			}
		}
	}

	public func didSend(message: String) {
		DispatchQueue.main.async {
			self.transcripts.append(Transcript(direction: .send, message: message))
			Notifications.messageSent.post(self.peerID)
		}
	}

	/// Mass-append messages. Only fires Notifications.unreadMessageCountChanged. Does not produce notifications.
	func catchUp(messages: [Transcript]) {
		DispatchQueue.main.async {
			self.transcripts.append(contentsOf: messages)
			Notifications.unreadMessageCountChanged.post(self.peerID)
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

	// call only from main thread!
	private func savePicture() {
		guard let picture = cgPicture else { return }

		DispatchQueue.global(qos: .background).async {
			// TODO use compression quality from original image
			do {
				try picture.save(to: self.pictureResourceURL, compressionQuality: 1.0)
			} catch let error {
				NSLog("ERROR: Saving portrait failed: \(error.localizedDescription)")
			}
		}
	}

	public func deletePicture() {
		DispatchQueue.global(qos: .background).async {
			let fileManager = FileManager.default
			if fileManager.fileExists(atPath: self.pictureResourceURL.path) {
				do {
					try fileManager.removeItem(at: self.pictureResourceURL)
				} catch let error {
					NSLog("ERROR: Couldn't delete portrait: \(error.localizedDescription)")
				}
			}
		}
	}
	
	func loaded(picture: CGImage, of peerID: PeerID, hash: Data) {
		// TODO PERFORMANCE: we save here again even if its the same image
		AccountController.shared.containsObjectionableContent(imageHash: hash) { containsObjectionableContent in
			self.cgPicture = picture
			self.pictureHash = hash
			self.pictureClassification = containsObjectionableContent
			if AccountController.shared.hasPinMatch(peerID) {
				self.savePicture()
			}
			Notifications.pictureLoaded.post(peerID)
		}
	}

	func loaded(biography: String, of peerID: PeerID) {
		Notifications.biographyLoaded.post(peerID)
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

	func didRemoteVerify(_ peerID: PeerID) {
		DispatchQueue.main.async { self.dequeueMessage() }
	}

	// MARK: LocalPeerDelegate
	
	func receivedPinMatchIndication() {
		guard verified, let peer = peerInfo else {
			// update pin status later when peer is verified
			receivedUnverifiedPinMatchIndication = true
			return
		}

		remotePeerManager.authenticate(peer.peerID)
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
