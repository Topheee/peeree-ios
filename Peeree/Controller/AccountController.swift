//
//  AccountController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public protocol AccountControllerDelegate {
    func publicKeyMismatch(of peerID: PeerID)
    func sequenceNumberResetFailed(error: ErrorResponse)
}

/**
 * Central singleton for managing all actions according to communication with the Peeree server.
 * Do NOT use the network calls in DefaultAPI directly, as then the sequence number won't be updated appropriately
 */
public class AccountController: SecurityDataSource {
    /// User defaults key for pinned peers dictionary
    static private let PinnedPeersKey = "PinnedPeers"
    /// User defaults key for pinned by peers dictionary
    static private let PinnedByPeersKey = "PinnedByPeers"
    /// User defaults key for user's email
    static private let EmailKey = "Email"
    /// User defaults key for sequence number
    static private let SequenceNumberKey = "SequenceNumber"
    
    private static var _instance = AccountController()
    
    public static var shared: AccountController {
        _ = AccountController.__once
        
        return _instance
    }
    
    private static var __once: () = { () -> Void in
        SwaggerClientAPI.dataSource = _instance
    }()
    
    public enum Notifications: String {
        public enum UserInfo: String {
            case peerID
        }
        case pinned, pinningStarted, pinFailed, pinMatch
        case accountCreated
        
        func post(_ peerID: PeerID) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: AccountController.shared, userInfo: [UserInfo.peerID.rawValue : peerID])
            }
        }
    }
    
    /*
     store pinned public key along with peerID as
     1. Alice pins Bob
     2. Eve advertises Bob's peerID with her public key
     3. Alice validates Bob's peerID with Eve's public key and thinks she met Bob again
     4. Eve convinced Alice successfully that she is Bob
    */
    
    /// stores acknowledged pinned peers and their public keys
    private var pinnedPeers: SynchronizedDictionary<PeerID, Data>
    // maybe encrypt these on disk so no one can read out their display names
    /// stores acknowledged pin matched peers
    private var pinnedByPeers: SynchronizedSet<PeerID>
    
    private var pinningPeers = SynchronizedSet<PeerID>(queueLabel: "\(Bundle.main.bundleIdentifier!).pinningPeers")
    
    private func resetSequenceNumber() {
        NSLog("WARN: resetting sequence number")
        DefaultAPI.deleteAccountSecuritySequenceNumber { (_sequenceNumberDataCipher, _error) in
            guard let sequenceNumberDataCipher = _sequenceNumberDataCipher else {
                if let error = _error {
                    self.delegate?.sequenceNumberResetFailed(error: error)
                }
                return
            }
            
            self._sequenceNumber = sequenceNumberDataCipher
        }
    }
    
    private var _sequenceNumber: Int32? {
        didSet {
            if let sequenceNumber = _sequenceNumber {
                UserDefaults.standard.set(NSNumber(value: sequenceNumber), forKey: AccountController.SequenceNumberKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AccountController.SequenceNumberKey)
            }
        }
    }
    
    private var _accountEmail: String? {
        didSet {
            if _accountEmail != nil && _accountEmail! != "" {
                UserDefaults.standard.set(accountEmail, forKey: AccountController.EmailKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AccountController.EmailKey)
            }
        }
    }
    public var accountEmail: String? { return _accountEmail }
    
    public var accountExists: Bool { return _sequenceNumber != nil }
    private var _isCreatingAccount = false
    public var isCreatingAccount: Bool { return _isCreatingAccount }
    private var _isDeletingAccount = false
    public var isDeletingAccount: Bool { return _isDeletingAccount }
    
    public var delegate: AccountControllerDelegate?
    
    /// Returns whether we have a pin match with that specific PeerID, that is, the global Peeree identifier. Note, that this does NOT imply we have a match with a concrete PeerInfo with that PeerID, as that PeerInfo may be a malicious peer
    public func hasPinMatch(_ peerID: PeerID) -> Bool {
        // it is enough to check whether we are pinned by peerID, as we only know that if we matched
        return pinnedByPeers.contains(peerID)
    }
    
    /**
     * Returns whether we have a pin match with that specific peer.
     * Note that this does NOT ultimately mean we have a pin match as long as the peer is not verified!
     */
    public func hasPinMatch(_ peer: PeerInfo) -> Bool {
        // it is NOT enough to check whether we are pinned by peer, as we also need to check whether the peer is really the person behind it's peerID (that is, it's public key matches the one we pinned)
        return pinnedByPeers.contains(peer.peerID) && isPinned(peer)
    }
    
    public func isPinned(_ peer: PeerInfo) -> Bool {
        return pinnedPeers.contains { $0.0 == peer.peerID && $0.1 == peer.publicKeyData }
    }
    
    public func isPinning(_ peerID: PeerID) -> Bool {
        return pinningPeers.contains(peerID)
    }
    
    public func pin(_ peer: PeerInfo) {
        guard accountExists else { return }
        let peerID = peer.peerID
        guard !isPinned(peer) && PeeringController.shared.remote.availablePeers.contains(peerID) && !(pinningPeers.contains(peerID)) else { return }
        
        self.pinningPeers.insert(peerID)
        Notifications.pinningStarted.post(peerID)
        DefaultAPI.putPin(pinnedID: peerID, pinnedKey: peer.publicKeyData.base64EncodedData()) { (_isPinMatch, _error) in
            self.pinningPeers.remove(peerID)
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
                // possible HTTP errors:
                // 402: not enough pin points
                // 409: non-matching public key
                //
                switch error {
                case .httpError(402, _), .sessionTaskError(402?, _, _):
                    InAppPurchaseController.shared.refreshPinPoints()
                case .httpError(409, _), .sessionTaskError(409?, _, _):
                    self.delegate?.publicKeyMismatch(of: peerID)
                default:
                    break
                }
                Notifications.pinFailed.post(peerID)
            } else if let isPinMatch = _isPinMatch  {
                self.pin(peer: peer, isPinMatch: isPinMatch)
            } else {
                Notifications.pinFailed.post(peerID)
            }
        }
    }
    
    private func pin(peer: PeerInfo, isPinMatch: Bool) {
        guard accountExists else { return }
        self.pinnedPeers.accessAsync { (dictionary) in
            let peerID = peer.peerID
            if !(dictionary.contains { $0.0 == peerID && $0.1 == peer.publicKeyData }) {
                dictionary[peerID] = peer.publicKeyData
                // access the set on the queue to ensure the last peerID is also included
                archiveObjectInUserDefs(dictionary as NSDictionary, forKey: AccountController.PinnedPeersKey)
                
                DispatchQueue.main.async {
                    InAppPurchaseController.shared.decreasePinPoints()
                    Notifications.pinned.post(peerID)
                }
            }
            
            if isPinMatch {
                self.pinnedByPeers.accessAsync { (set) in
                    if !set.contains(peerID) {
                        set.insert(peerID)
                        // access the set on the queue to ensure the last peerID is also included
                        archiveObjectInUserDefs(set as NSSet, forKey: AccountController.PinnedByPeersKey)
                        
                        DispatchQueue.main.async {
                            PeeringController.shared.remote.indicatePinMatch(to: peer)
                            Notifications.pinMatch.post(peerID)
                        }
                    }
                }
            }
        }
    }
    
    private func unpin(peer: PeerInfo) {
        let peerID = peer.peerID
        self.pinnedPeers.accessAsync { (dictionary) in
            dictionary.removeValue(forKey: peerID)
            // access the set on the queue to ensure the last peerID is also included
            archiveObjectInUserDefs(dictionary as NSDictionary, forKey: AccountController.PinnedPeersKey)
            Notifications.pinFailed.post(peerID)
        }
        
        self.pinnedByPeers.accessAsync { (set) in
            if set.remove(peerID) != nil {
                // access the set on the queue to ensure the last peerID is also included
                archiveObjectInUserDefs(set as NSSet, forKey: AccountController.PinnedByPeersKey)
            }
        }
    }

    public func updatePinStatus(of peer: PeerInfo) {
        guard accountExists else { return }
        // attack scenario: Eve sends pin match indication to Alice, but Alice only asks server, if she pinned Eve in the first place => Eve can observe Alice's internet communication and can figure out, whether Alice pinned her, depending on whether Alice' asked the server after the indication.
        // thus, we (Alice) have to at least once validate with the server, even if we know, that we did not pin Eve
        // This is achieved through the hasPinMatch query, as this will always fail, if we do not have a true match, thus we query ALWAYS the server when we receive an pin match indication. If flooding attack (Eve sends us dozens of indications) gets serious, implement above behaviour, that we only validate once
        // we can savely ignore this if we already know we have a pin match
        guard !hasPinMatch(peer) else { return }
        
        let pinPublicKey = peer.publicKeyData.base64EncodedData()
        
        DefaultAPI.getPin(pinnedID: peer.peerID, pinnedKey: pinPublicKey) { (_pinStatus, _error) in
            guard _error == nil else {
                self.preprocessAuthenticatedRequestError(_error!)
                return
            }
            if let pinStatus = _pinStatus {
                switch pinStatus {
                case 0:
                    self.pin(peer: peer, isPinMatch: false)
                case 1:
                    self.pin(peer: peer, isPinMatch: true)
                default:
                    self.unpin(peer: peer)
                }
                
            }
        }
    }
    
    public func createAccount(completion: @escaping (Error?) -> Void) {
        guard !_isCreatingAccount else { return }
        _isCreatingAccount = true
        _sequenceNumber = nil // we are not responsible here to ensure that no account already exists and need to not send this sequence number as our public key
        var publicKey = UserPeerInfo.instance.peer.publicKeyData
    
        DefaultAPI.putAccount(email: _accountEmail) { (_account, _error) in
            var completionError: Error?
            defer {
                self._isCreatingAccount = false
                completion(completionError)
                if completionError == nil {
                    Notifications.accountCreated.post(UserPeerInfo.instance.peerID)
                }
            }
            
            guard let account = _account, let sequenceNumberDataCipher = account.sequenceNumber, let newPeerID = account.peerID else {
                completionError = _error ?? NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Server did provide malformed or no account information", comment: "Error when an account creation request response is malformed")])
                return
            }

            self._sequenceNumber = sequenceNumberDataCipher
            completionError = nil
            DispatchQueue.main.sync {
                // UserPeerInfo has to be modified on the main queue
                UserPeerInfo.instance.peerID = newPeerID
                // further requests need peerID in UserPeerInfo to be set
                InAppPurchaseController.shared.refreshPinPoints()
            }
        }
    }
    
    public func deleteAccount(completion: @escaping (Error?) -> Void) {
        guard accountExists else { return }
        guard !_isDeletingAccount else { return }
        _isDeletingAccount = true
        PeeringController.shared.peering = false
        DefaultAPI.deleteAccount { (_error) in
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
            } else {
                PeeringController.shared.peering = false
                self._accountEmail = nil
                self._sequenceNumber = nil
                DispatchQueue.main.sync {
                    UserPeerInfo.delete()
                }
            }
            self._isDeletingAccount = false
            completion(_error)
        }
    }
    
    public func update(email: String, completion: @escaping (Error?) -> Void) {
        guard accountExists else { return }
        guard email != "" else { deleteEmail(completion: completion); return }
        DefaultAPI.putAccountEmail(email: email) { (_error) in
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
            } else {
                self._accountEmail = email
            }
            completion(_error)
        }
    }
    
    public func deleteEmail(completion: @escaping (Error?) -> Void) {
        guard accountExists else { return }
        DefaultAPI.deleteAccountEmail { (_error) in
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
            } else {
                self._accountEmail = nil
            }
            completion(_error)
        }
    }
    
    public func getPinPoints(completion: @escaping (PinPoints?, Error?) -> Void) {
        guard accountExists else { return }
        DefaultAPI.getAccountPinPoints { (_pinPoints, _error) in
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
            }
            completion(_pinPoints, _error)
        }
    }
    
    public func redeem(receipts: Data, completion: @escaping (PinPoints?, Error?) -> Void) {
        guard accountExists else { return }
        DefaultAPI.putInAppPurchaseIosReceipt(receiptData: receipts) { (_pinPoints, _error) in
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
            }
            completion(_pinPoints, _error)
        }
    }
    
    public func getProductIDs(completion: @escaping ([String]?, Error?) -> Void) {
        guard accountExists else {
            completion(nil, NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("A Peeree identity is needed to retrieve products.", comment: "The user tried to refresh the product IDs but has no account yet.")]))
            return
        }
        DefaultAPI.getInAppPurchaseIosProductIds { (_response, _error) in
            if let error = _error {
                self.preprocessAuthenticatedRequestError(error)
            }
            completion(_response, _error)
        }
    }
    
    // MARK: SecurityDelegate
    
    public func getPeerID() -> String {
        return UserPeerInfo.instance.peer.peerID.uuidString
    }
    
    public func getSignature() -> String {
        return (try? computeSignature()) ?? (try? UserPeerInfo.instance.keyPair.externalPublicKey().base64EncodedString()) ?? ""
    }
    
    // MARK: Private Functions
    
    private init() {
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(AccountController.PinnedByPeersKey)
        pinnedByPeers = SynchronizedSet(queueLabel: "\(Bundle.main.bundleIdentifier!).pinnedByPeers", set: nsPinnedBy as? Set<PeerID> ?? Set())
        let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(AccountController.PinnedPeersKey)
        pinnedPeers = SynchronizedDictionary(queueLabel: "\(Bundle.main.bundleIdentifier!).pinnedPeers", dictionary: nsPinned as? [PeerID : Data] ?? [PeerID : Data]())
        _accountEmail = UserDefaults.standard.string(forKey: AccountController.EmailKey)
        _sequenceNumber = (UserDefaults.standard.object(forKey: AccountController.SequenceNumberKey) as? NSNumber)?.int32Value
    }
    
    /// resets sequence number to state before request if the request did not reach the server
    private func preprocessAuthenticatedRequestError(_ errorResponse: ErrorResponse) {
        switch errorResponse {
        case .httpError(403, _): // TODO well this should only handle 403 errors and thus the switch should not be exhaustive...
            self.resetSequenceNumber()
        case .parseError(_):
            NSLog("ERR: Response could not be parsed.")
            break
        case .sessionTaskError(let statusCode, _, let error):
            NSLog("ERR: Network error \(statusCode ?? -1) occurred: \(error.localizedDescription)")
            if (error as NSError).domain == NSURLErrorDomain {
                if let sequenceNumber = _sequenceNumber {
                    // we did not even reach the server, so we have to decrement our sequenceNumber again
                    _sequenceNumber = Int32.subtractWithOverflow(sequenceNumber, 1).0
                }
            }
            if statusCode == 403 { // forbidden
                // the signature was invalid, so request a new sequenceNumber
                self.resetSequenceNumber()
            }
        default:
            break
        }
    }
    
    private func computeSignature() throws -> String {
        guard _sequenceNumber != nil, let sequenceNumberData = String(_sequenceNumber!).data(using: .utf8) else {
            throw NSError(domain: "Peeree", code: -2, userInfo: nil)
        }
        
        _sequenceNumber = Int32.addWithOverflow(_sequenceNumber!, 1).0
        return try UserPeerInfo.instance.keyPair.sign(message: sequenceNumberData).base64EncodedString()
    }
}