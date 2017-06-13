//
//  AccountController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 03.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

public class AccountController: SecurityDelegate {
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
    
    private static func getCertFromBundle(name: String) -> SecCertificate? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "der") else {
            NSLog("could not find certificate \(name) in bundle.")
            return nil
        }
        var data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            NSLog("unable to read certificate \(name): \(error.localizedDescription)")
            return nil
        }
        
        guard let certificate = SecCertificateCreateWithData(kCFAllocatorDefault, data as CFData) else {
            NSLog("certificate \(name) is not in DER format.")
            return nil
        }
        
        return certificate
    }
    
    private static var __once: () = { () -> Void in
        SwaggerClientAPI.customHeaders["peerID"] = UserPeerInfo.instance.peer.peerID.uuidString
        DefaultAPI.delegate = _instance
        
        guard let caCert = getCertFromBundle(name: "cacert"), let serverCert = getCertFromBundle(name: "servercert") else { return }
        
        // let policy = SecPolicyCreateSSL(true, SwaggerClientAPI.host as CFString)
        let policy = SecPolicyCreateSSL(true, nil)
        
        var _trust: SecTrust?
        var status = SecTrustCreateWithCertificates(serverCert, policy, &_trust)
        guard let trust = _trust, status == errSecSuccess else {
            NSLog("creating trust failed with code \(status)")
            return
        }
        
        status = SecTrustSetAnchorCertificates(trust, [caCert] as CFArray)
        guard status == errSecSuccess else {
            NSLog("adding anchor certificate failed with code \(status)")
            return
        }
//        SecTrustSetAnchorCertificatesOnly(<#T##trust: SecTrust##SecTrust#>, <#T##anchorCertificatesOnly: Bool##Bool#>)
        
        var result: SecTrustResultType = .otherError
        status = SecTrustEvaluate(trust, &result)
        guard status == errSecSuccess else {
            NSLog("evaluating trust failed with code \(status).")
            return
        }
        
        guard result == .proceed || result == .unspecified else {
            NSLog("server certificate not trusted, result code: \(result.rawValue).")
            return
        }
        
        let space = URLProtectionSpace(host: SwaggerClientAPI.host, port: 0, protocol: SwaggerClientAPI.`protocol`, realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        
        URLCredentialStorage.shared.setDefaultCredential(URLCredential(trust: trust), for: space)
    }()
    
    public enum Notifications: String {
        public enum UserInfo: String {
            case peerID
        }
        case pinned, pinningStarted, pinFailed, pinMatch
        
        func post(_ peerID: PeerID) {
            NotificationCenter.default.post(name: Notification.Name(rawValue: self.rawValue), object: AccountController.shared, userInfo: [UserInfo.peerID.rawValue : peerID])
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
    private var pinnedPeers = SynchronizedDictionary<PeerID, Data>()
    // maybe encrypt these on disk so no one can read out their display names
    private var pinnedByPeers = SynchronizedSet<PeerID>()
    
    private var pinningPeers = SynchronizedSet<PeerID>()
    
    private func resetSequenceNumber() {
        DefaultAPI.deleteAccountSecuritySequenceNumber { (_sequenceNumberDataCipher, _error) in
            guard let sequenceNumberDataCipher = _sequenceNumberDataCipher else {
                if let error = _error {
                    NSLog("getAccountSecuritySequenceNumber failed: \(error)")
                }
                return
            }
            
            do {
                try self.decodeSequenceNumber(cipher: sequenceNumberDataCipher)
            } catch {
                NSLog("Decoding sequence number failed: \(error)")
            }
        }
    }
    
    private var _sequenceNumber: Int64? {
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
    
    public func hasPinMatch(_ peer: PeerInfo) -> Bool {
        return isPinned(peer) && pinnedByPeers.contains(peer.peerID)
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
        guard !isPinned(peer) && PeeringController.shared.remote.availablePeers.contains(peerID) && !(pinningPeers.contains(peerID)) else {
            Notifications.pinFailed.post(peerID)
            return
        }
        
        let pinPublicKey = peer.publicKeyData.base64EncodedData()
        
        self.pinningPeers.insert(peerID)
        Notifications.pinningStarted.post(peerID)
        DefaultAPI.putPin(peerID: peerID, publicKey: pinPublicKey) { (_isPinMatch, _error) in
            if let error = _error {
                self.handleStandardErrors(error: error)
            } else if let isPinMatch = _isPinMatch  {
                self.pinningPeers.remove(peerID)
                self.pin(peer: peer, isPinMatch: isPinMatch)
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
                InAppPurchaseController.decreasePinPoints()
                
                Notifications.pinned.post(peerID)
            }
            
            if isPinMatch {
                self.pinnedByPeers.accessAsync { (set) in
                    if !set.contains(peerID) {
                        set.insert(peerID)
                        // access the set on the queue to ensure the last peerID is also included
                        archiveObjectInUserDefs(set as NSSet, forKey: AccountController.PinnedByPeersKey)
                        
                        PeeringController.shared.remote.indicatePinMatch(to: peer)
                        Notifications.pinMatch.post(peerID)
                    }
                }
            }
        }
    }
    
    public func validatePinMatch(with peerID: PeerID) {
        guard accountExists else { return }
        // attack scenario: Eve sends pin match indication to Alice, but Alice only asks server, if she pinned Eve in the first place => Eve can observe Alice's internet communication and can figure out, whether Alice pinned her, depending on whether Alice' asked the server after the indication.
        // thus, we (Alice) have to at least once validate with the server, even if we know, that we did not pin Eve
        // TODO if flooding attack (Eve sends us dozens of indications) gets serious, implement above behaviour, that we only validate once
//        guard !pinnedByPeers.contains(peerID) else { return }
        guard let peer = PeeringController.shared.remote.getPeerInfo(of: peerID) else { return }
        // we can savely ignore this if we already know we have a pin match
        guard !hasPinMatch(peer) else { return }
        
        let pinPublicKey = peer.publicKeyData.base64EncodedData()
        
        DefaultAPI.getPin(peerID: peerID, publicKey: pinPublicKey) { (_isPinMatch, _error) in
            if let error = _error {
                self.handleStandardErrors(error: error)
            } else if let isPinMatch = _isPinMatch, isPinMatch {
                self.pin(peer: peer, isPinMatch: isPinMatch)
            }
        }
    }
    
    public func createAccount(completion: @escaping (Error?) -> Void) {
        guard !_isCreatingAccount else { return }
        _isCreatingAccount = true
//        do {
            var publicKey = UserPeerInfo.instance.peer.publicKeyData
            
            // this call must not throw, as then the defer statement would invoke completion as well as the catch handler of the enclosing do statement!
            DefaultAPI.putAccount(publicKey: publicKey.base64EncodedData(), email: _accountEmail) { (_account, _error) in
                var completionError: Error?
                defer {
                    self._isCreatingAccount = false
                    completion(completionError)
                }
                
                guard let account = _account else {
                    if let error = _error {
                        self.handleStandardErrors(error: error)
                    }
//                    completion(_error)
                    completionError = _error
                    return
                }
                guard let sequenceNumberDataCipher = account.sequenceNumber, let newPeerID = account.peerID else {
                    NSLog("no sequence number or peer ID in account")
//                    completion(NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Server Error 1", comment: "Server sent wrong data.")]))
                    completionError = NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Server Error 1", comment: "Server sent wrong data.")])
                    return
                }
                do {
                    try self.decodeSequenceNumber(cipher: sequenceNumberDataCipher)
                } catch {
                    NSLog(error.localizedDescription)
//                    completion(NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Server Error 2", comment: "Server sent wrong data.")]))
                    completionError = NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Server Error 2", comment: "Server sent wrong data.")])
                    return
                }
                DispatchQueue.main.sync {
                    // UserPeerInfo has to be modified on the main queue
                    UserPeerInfo.instance.peerID = newPeerID
                    // further requests need peerID in UserPeerInfo to be set
                    InAppPurchaseController.refreshPinPoints()
//                    completion(nil)
                }
                completionError = nil
            }
//        } catch { 
//            completion(error)
//            _isCreatingAccount = false
//        }
    }
    
    public func deleteAccount(completion: @escaping (Error?) -> Void) {
        guard accountExists else { return }
        guard !_isDeletingAccount else { return }
        _isDeletingAccount = true
        DefaultAPI.deleteAccount { (_error) in
            if let error = _error {
                self.handleStandardErrors(error: error)
            } else {
                self._accountEmail = nil
                self._sequenceNumber = nil
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
                self.handleStandardErrors(error: error)
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
                self.handleStandardErrors(error: error)
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
                self.handleStandardErrors(error: error)
            }
            completion(_pinPoints, _error)
        }
    }
    
    public func redeem(receipts: Data, completion: @escaping (PinPoints?, Error?) -> Void) {
        guard accountExists else { return }
        DefaultAPI.putAppInAppPurchaseIosReceiptsRedeem(receiptData: receipts) { (_pinPoints, _error) in
            if let error = _error {
                self.handleStandardErrors(error: error)
            }
            completion(_pinPoints, _error)
        }
    }
    
    public func getProductIDs(completion: @escaping ([String]?, Error?) -> Void) {
        guard accountExists else {
            completion(nil, NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("A Peeree account is needed to retrieve products.", comment: "The user tried to refresh the product IDs but has no account yet.")]))
            return
        }
        DefaultAPI.getAppInAppPurchaseIosProductIds { (_response, _error) in
            if let error = _error {
                self.handleStandardErrors(error: error)
            }
            completion(_response?.data, _error)
        }
    }
    
//    public func sign(nonce: Data) throws -> Data {
//        return try UserPeerInfo.instance.keyPair.sign(message: nonce)
//    }
    
    // MARK: SecurityDelegate
    
    func getPeerID() -> String {
        return UserPeerInfo.instance.peer.peerID.uuidString
    }
    
    func getSignature() -> String {
        return (try? computeSignature()) ?? ""
    }
    
    // MARK: Private Functions
    
    private init() {
        let nsPinnedBy: NSSet? = unarchiveObjectFromUserDefs(AccountController.PinnedByPeersKey)
        pinnedByPeers = SynchronizedSet(set: nsPinnedBy as? Set<PeerID> ?? Set())
        let nsPinned: NSDictionary? = unarchiveObjectFromUserDefs(AccountController.PinnedPeersKey)
        pinnedPeers = SynchronizedDictionary(dictionary: nsPinned as? [PeerID : Data] ?? [PeerID : Data]())
        _accountEmail = UserDefaults.standard.string(forKey: AccountController.EmailKey)
        _sequenceNumber = (UserDefaults.standard.object(forKey: AccountController.SequenceNumberKey) as? NSNumber)?.int64Value
    }
    
    private func handleStandardErrors(error: Error) {
        guard let errorResponse = error as? ErrorResponse else {
            NSLog("Unknown network error occured: \(error)")
            return
        }
        
        switch errorResponse {
        case .Error(let statusCode, _, let theError):
            NSLog("Network error \(statusCode) occurred: \(theError)")
            if (theError as NSError).code == NSURLErrorSecureConnectionFailed {
                // TODO inform the user about this incident
            }
            if statusCode == 403 { // forbidden
                // the signature was invalid, so request a new sequenceNumber
                self.resetSequenceNumber()
            }
        }
    }
    
    private func decodeSequenceNumber(cipher: Data) throws {
        guard let sequenceNumberDataCipher = Data(base64Encoded: cipher) else {
            throw NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : "Sequence number data cipher not base64 encoded"])
        }
        
        // decode and set seq num
        let keyPair = UserPeerInfo.instance.keyPair
        
        let sequenceNumberData = try keyPair.decrypt(message: sequenceNumberDataCipher)
        guard let sequenceNumberString = String(data:sequenceNumberData, encoding: .utf8) else {
            throw NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : "Sequence number data not in utf8"])
        }
        guard let newSequenceNumber = Int64(sequenceNumberString) else {
            throw NSError(domain: "Peeree", code: -1, userInfo: [NSLocalizedDescriptionKey : "Sequence number data not a number"])
        }
        
        self._sequenceNumber = newSequenceNumber
    }
    
    private func computeSignature() throws -> String {
        let keyPair = UserPeerInfo.instance.keyPair
        
        guard _sequenceNumber != nil, let sequenceNumberData = String(_sequenceNumber!).data(using: .utf8) else { return "" }
        
        _sequenceNumber! += 1
        return try keyPair.encrypt(message: sequenceNumberData).base64EncodedString()
    }
}
