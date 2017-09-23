//
//  SecurityHelper.swift
//  Peeree
//
//  Created by Christopher Kobusch on 27.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import Security
import CommonCrypto

extension Data {
    func sha256() -> Data {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var digest = Data(count: digestLength)
        _ = digest.withUnsafeMutableBytes({ (digestMutableBytes) in
            self.withUnsafeBytes({ (plainTextBytes) in
                CC_SHA256(plainTextBytes, CC_LONG(self.count), digestMutableBytes)
            })
        })
        
        return digest
    }
}

public class AsymmetricKey {
    public static func keyFromKeychain(tag: Data, keyType: String) throws -> Data {
        let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecAttrKeyType as String: keyType,
                                       kSecReturnData as String: NSNumber(value: true)]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemCopyMatching(getquery as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))
        
        return (item as! CFData) as Data
    }
    
    fileprivate let key: SecKey
    private var _tag: Data?
    fileprivate let type: CFString, size: Int
    fileprivate let signaturePadding: SecPadding = [] // .PKCS1SHA256
    fileprivate let encryptionPadding: SecPadding = .PKCS1SHA256
    
    public func removeFromKeychain() throws {
        guard let tag = _tag else { return }
        
        let remquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag]
        try SecKey.check(status: SecItemDelete(remquery as CFDictionary), localizedError: NSLocalizedString("Deleting keychain item failed.", comment: "Removing an item from the keychain produced an error."))
        _tag = nil
    }
    
    public func addToKeychain(tag: Data, keyClass: CFString) throws -> Data {
        assert(_tag == nil, "If this occurs, decide whether it should be allowed to add the key (with a different) tag again")
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyClass as String: keyClass,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecAttrKeySizeInBits as String: size,
                                       kSecValueRef as String: key,
                                       kSecReturnData as String: NSNumber(value: true)]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
        self._tag = tag
        
        return (item as! CFData) as Data
    }
    
    public func addToKeychain(tag: Data, keyClass: CFString) throws {
        assert(_tag == nil, "If this occurs, decide whether it should be allowed to add the key (with a different) tag again")
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyClass as String: keyClass,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecAttrKeySizeInBits as String: size,
                                       kSecValueRef as String: key]
        try SecKey.check(status: SecItemAdd(addquery as CFDictionary, nil), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
        self._tag = tag
    }
    
    public static func addToKeychain(key: SecKey, tag: Data) throws -> Data {
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecValueRef as String: key,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecReturnData as String: NSNumber(value: true)]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
        
        return (item as! CFData) as Data
    }
    
    public static func removeFromKeychain(tag: Data) throws {
        let remquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrApplicationTag as String: tag]
        try SecKey.check(status: SecItemDelete(remquery as CFDictionary), localizedError: NSLocalizedString("Deleting keychain item failed.", comment: "Removing an item from the keychain produced an error."))
    }
    
    public func externalRepresentation() throws -> Data {
        var error: Unmanaged<CFError>?
        if #available(macOS 10.12.1, iOS 10.0, *) {
            guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
                throw error!.takeRetainedValue()
            }
            return data
        } else {
            let temporaryTag = "de.kobusch.tempkey2".data(using: .utf8)!
            
            defer {
                // always try to remove key from keychain
                do {
                    try AsymmetricKey.removeFromKeychain(tag: temporaryTag)
                } catch {
                    // only log this
                    NSLog("\(error)")
                }
            }
            
            return try AsymmetricKey.addToKeychain(key: key, tag: temporaryTag)
        }
    }
    
    public init(from data: Data, type: CFString, size: Int, keyClass: CFString) throws {
        self.type = type
        self.size = size
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let attributes: [String : Any] = [
                kSecAttrKeyType as String:            type,
                kSecAttrKeySizeInBits as String:      size,
                kSecAttrKeyClass as String:           keyClass]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
                throw error!.takeRetainedValue()
            }
            
            self.key = key
        } else {
            let tag = "de.kobusch.tempkey".data(using: .utf8)!
            
            // always try to remove key from keychain before we add it again
            try? AsymmetricKey.removeFromKeychain(tag: tag)
            
            defer {
                // always try to remove key from keychain when we added it
                do {
                    try AsymmetricKey.removeFromKeychain(tag: tag)
                } catch {
                    // only log this
                    NSLog("\(error)")
                }
            }
            
            let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                           kSecAttrKeyType as String: type,
                                           kSecAttrApplicationTag as String: tag,
                                           kSecValueData as String: data,
                                           kSecAttrKeyClass as String: keyClass,
                                           kSecReturnRef as String: NSNumber(value: true)]
            var item: CFTypeRef?
            try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
            
            self.key = item as! SecKey
        }
    }
    
    public init(from data: Data, type: CFString, size: Int, keyClass: CFString, tag: Data) throws {
        self._tag = tag
        self.type = type
        self.size = size
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyClass as String: keyClass,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecValueData as String: data,
                                       kSecReturnRef as String: NSNumber(value: true)]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
        
        self.key = item as! SecKey
    }
    
    public init(tag: Data) throws {
        _tag = tag
        let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecReturnRef as String: NSNumber(value: true)]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemCopyMatching(getquery as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))
        
        key = item as! SecKey
        
        let attributesQuery: [String: Any] = [kSecClass as String: kSecClassKey,
                                              kSecAttrApplicationTag as String: tag,
                                              kSecReturnAttributes as String: NSNumber(value: true)]
        try SecKey.check(status: SecItemCopyMatching(attributesQuery as CFDictionary, &item), localizedError: NSLocalizedString("Reading attributes from keychain failed.", comment: "Attempt to read attributes of a keychain item failed."))
        
        let attributes = (item as! CFDictionary) as! [String: Any]
        type = attributes[kSecAttrKeyType as String] as! CFString
        size = attributes[kSecAttrKeySizeInBits as String] as! NSNumber as! Int
    }
    
    fileprivate init(key: SecKey, type: CFString, size: Int, tag: Data?) {
        self._tag = tag
        self.type = type
        self.size = size
        self.key = key
    }
}

public class AsymmetricPublicKey: AsymmetricKey {
    public func verify(message data: Data, signature: Data) throws {
        if #available(macOS 10.12.1, iOS 10.0, *) {
            NSLog("Verify signature size: \(signature.count), block size: \(SecKeyGetBlockSize(key))")
            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            guard SecKeyIsAlgorithmSupported(key, .verify, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm \(SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256) does not support verifying", comment: "Error description for verifying exception, which should never actually occur.")])
            }
            
            var error: Unmanaged<CFError>?
            guard SecKeyVerifySignature(key, algorithm, data as CFData, signature as CFData, &error) else {
                throw error!.takeUnretainedValue() as Error
            }
        } else {
            #if os(iOS)
                let digest = data.sha256()
                NSLog("Verify signature size: \(signature.count), digest size: \(digest.count), block size: \(SecKeyGetBlockSize(key))")
                
                let status = signature.withUnsafeBytes { (signatureBytes: UnsafePointer<UInt8>) in
                    return digest.withUnsafeBytes { (digestBytes: UnsafePointer<UInt8>) in
                        SecKeyRawVerify(key, signaturePadding, digestBytes, digest.count, signatureBytes, signature.count)
                    }
                }
                
                try SecKey.check(status: status, localizedError: NSLocalizedString("Verifying signature failed.", comment: "Cryptographically verifying a message failed."))
            #else
                throw NSError(domain: "unsupported", code: -1, userInfo: nil)
//            var _error: Unmanaged<CFError>? = nil
//            let _transform = SecVerifyTransformCreate(key, signature as CFData, &_error)
//            guard let transform = _transform else {
//                throw _error!.takeRetainedValue()
//            }
//            guard SecTransformSetAttribute(transform, kSecTransformInputAttributeName, data as CFData, &_error) else {
//                throw _error!.takeRetainedValue()
//            }
//            SecTransformExecute(<#T##transformRef: SecTransform##SecTransform#>, <#T##errorRef: UnsafeMutablePointer<Unmanaged<CFError>?>?##UnsafeMutablePointer<Unmanaged<CFError>?>?#>)
            #endif
        }
    }
    
    public func encrypt(message plainText: Data) throws -> Data {
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM // does not work: ecdhKeyExchangeStandardX963SHA256, ecdhKeyExchangeCofactor
            guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm \(SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM) does not support encryption", comment: "Error description for encryption exception, which should never actually occur.")])
            }
            
            let padding = 0 // TODO find out how much it is for ECDH
            guard plainText.count < (SecKeyGetBlockSize(key)-padding) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSValidationErrorMaximum, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Plain text length (\(plainText.count)) exceeds block size \(SecKeyGetBlockSize(key)-padding)", comment: "Exception when trying to encrypt too-big data.")])
            }
            
            var error: Unmanaged<CFError>?
            guard let cipherText = SecKeyCreateEncryptedData(key, algorithm, plainText as CFData, &error) as Data? else {
                throw error!.takeRetainedValue() as Error
            }
            
            return cipherText
        } else {
            #if os(iOS)
                var cipherSize = SecKeyGetBlockSize(key)
                var cipher = Data(count: cipherSize)
                let status = cipher.withUnsafeMutableBytes { (cipherBytes: UnsafeMutablePointer<UInt8>) in
                    return plainText.withUnsafeBytes { ( plainTextBytes: UnsafePointer<UInt8>) in
                        SecKeyEncrypt(key, encryptionPadding, plainTextBytes, plainText.count, cipherBytes, &cipherSize)
                    }
                }
                try SecKey.check(status: status, localizedError: NSLocalizedString("Cryptographically encrypting failed.", comment: "Cryptographically encrypting a message failed."))
                
                return cipher.subdata(in: 0..<cipherSize)
            #else
                throw NSError(domain: "unsupported", code: -1, userInfo: nil)
            #endif
        }
    }
    
}

public class AsymmetricPrivateKey: AsymmetricKey {
    public func sign(message data: Data) throws -> Data {
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm does not support signing", comment: "Error description for signing exception, which should never actually occur.")])
            }
            
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(key, algorithm, data as CFData, &error) as Data? else {
                throw error!.takeRetainedValue() as Error
            }
            
            NSLog("Sign signatureSize: \(signature.count), block size: \(SecKeyGetBlockSize(key))")
            return signature
        } else {
            #if os(iOS)
                let digest = data.sha256()
                
                var signatureSize = 256 // in CryptoExercise it is SecKeyGetBlockSize(key), but on the internet it's some magic number like this
                NSLog("Sign digest size: \(digest.count) (should be \(CC_SHA256_DIGEST_LENGTH)), signatureSize (block size): \(signatureSize)")
                var signature = Data(count: signatureSize)
                
                let status = signature.withUnsafeMutableBytes { (signatureBytes: UnsafeMutablePointer<UInt8>) in
                    return digest.withUnsafeBytes { (digestBytes: UnsafePointer<UInt8>) in
                        SecKeyRawSign(key, signaturePadding, digestBytes /* CC_SHA256_DIGEST_LENGTH */, digest.count, signatureBytes, &signatureSize)
                    }
                }
                NSLog("\t actual signatureSize: \(signatureSize)")
                
                try SecKey.check(status: status, localizedError: NSLocalizedString("Cryptographically signing failed.", comment: "Cryptographically signing a message failed."))
                
                return signature.subdata(in: 0..<signatureSize)
            #else
                throw NSError(domain: "unsupported", code: -1, userInfo: nil)
            #endif
        }
    }
    
    public func decrypt(message cipherText: Data) throws -> Data {
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM
            guard SecKeyIsAlgorithmSupported(key, .decrypt, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm \(SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM) does not support decryption", comment: "Error description for decryption exception, which should never actually occur.")])
            }
            
            //        guard cipherText.count == SecKeyGetBlockSize(privateKey) else {
            //            throw NSError(domain: NSCocoaErrorDomain, code: NSValidationErrorMaximum, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Cipher text length (\(cipherText.count)) not match block size \(SecKeyGetBlockSize(privateKey))", comment: "Exception when trying to decrypt data of wrong length.")])
            //        }
            
            var error: Unmanaged<CFError>?
            guard let clearText = SecKeyCreateDecryptedData(key, algorithm, cipherText as CFData, &error) as Data? else {
                throw error!.takeRetainedValue() as Error
            }
            
            return clearText
        } else {
            #if os(iOS)
                var plainTextSize = cipherText.count
                var plainText = Data(count: plainTextSize)
                let status = cipherText.withUnsafeBytes { (cipherTextBytes: UnsafePointer<UInt8>) in
                    return plainText.withUnsafeMutableBytes { (plainTextBytes: UnsafeMutablePointer<UInt8>) in
                        SecKeyDecrypt(key, encryptionPadding, cipherTextBytes, cipherText.count, plainTextBytes, &plainTextSize)
                    }
                }
                try SecKey.check(status: status, localizedError: NSLocalizedString("Decrypting cipher text failed.", comment: "Cryptographically decrypting a message failed."))
                
                return plainText.subdata(in: 0..<plainTextSize)
            #else
                throw NSError(domain: "unsupported", code: -1, userInfo: nil)
            #endif
        }
    }
    
}

extension SecKey {
    static func check(status: OSStatus, localizedError: String) throws {
        guard status == errSecSuccess else {
            #if os(OSX)
                let msg = "\(localizedError): \(SecCopyErrorMessageString(status, nil) ?? "" as CFString)"
            #else
                let msg = localizedError
            #endif
            NSLog("OSStatus \(status) check failed: \(localizedError)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey : msg])
        }
    }
}

public class KeyPair {
    private let privateKey: AsymmetricPrivateKey
    public let publicKey: AsymmetricPublicKey
    
    public var blockSize: Int { return SecKeyGetBlockSize(privateKey.key) }
    
    public init(privateTag: Data, publicTag: Data, type: CFString, size: Int, persistent: Bool) throws {
        var error: Unmanaged<CFError>?
        var attributes: [String : Any]
        #if os(macOS)
            attributes = [
                kSecAttrKeyType as String:            type,
                kSecAttrKeySizeInBits as String:      size,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String:    persistent,
                    kSecAttrApplicationTag as String: privateTag
                    ] as CFDictionary
            ]
        #elseif os(iOS) && (arch(x86_64) || arch(i386)) //iPhone Simulator
            attributes = [
                kSecAttrKeyType as String:            type,
                kSecAttrKeySizeInBits as String:      size,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String:    persistent,
                    kSecAttrApplicationTag as String: privateTag
                    ] as CFDictionary
            ]
        #else
            
            if #available(iOS 10.0, *) {
                guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error) else {
                    throw error!.takeRetainedValue() as Error
                }
            attributes = [
                kSecAttrKeyType as String:            type,
                kSecAttrKeySizeInBits as String:      size,
                kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String:    persistent,
                    kSecAttrApplicationTag as String: privateTag,
                    kSecAttrAccessControl as String:  access
                    ] as CFDictionary
                ]
            } else {
                // we do not use the Secure Enclave on iOS 9!
                attributes = [
                    kSecAttrKeyType as String:            type,
                    kSecAttrKeySizeInBits as String:      size,
                    kSecPrivateKeyAttrs as String: [
                        kSecAttrIsPermanent as String:    persistent,
                        kSecAttrApplicationTag as String: privateTag
                        ] as CFDictionary
                ]
            }
        #endif
        
        var _publicKey, _privateKey: SecKey?
        try SecKey.check(status: SecKeyGeneratePair(attributes as CFDictionary, &_publicKey, &_privateKey), localizedError: NSLocalizedString("Generating cryptographic key pair failed.", comment: "Low level crypto error."))
        
        NSLog("Created key pair with block sizes \(SecKeyGetBlockSize(_privateKey!)), \(SecKeyGetBlockSize(_publicKey!))")
        
        privateKey = AsymmetricPrivateKey(key: _privateKey!, type: type, size: size, tag: privateTag)
        
        #if os(iOS) && (arch(x86_64) || arch(i386)) || os(macOS) // iPhone Simulator or macOS
            publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size, tag: publicTag)
        #else
            if #available(iOS 10.0, *) {
                publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size, tag: nil)
            } else {
                publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size, tag: nil)
                try publicKey.addToKeychain(tag: publicTag, keyClass: kSecAttrKeyClassPublic) as Void
            }
        #endif
    }
    
    public init(fromKeychainWith privateTag: Data, publicTag: Data) throws {
        privateKey = try AsymmetricPrivateKey(tag: privateTag)
        #if os(iOS) && (arch(x86_64) || arch(i386)) || os(macOS) // iPhone Simulator or macOS
            publicKey = try AsymmetricPublicKey(tag: publicTag)
        #else
        if #available(iOS 10.0, *) {
            guard let pubKey = SecKeyCopyPublicKey(privateKey.key) else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("no public key derivable", comment: "Low level error.")])
            }
            publicKey = AsymmetricPublicKey(key: pubKey, type: privateKey.type, size: privateKey.size, tag: nil)
        } else {
            publicKey = try AsymmetricPublicKey(tag: publicTag)
        }
        #endif
    }
    
    public func removeFromKeychain() throws {
        try publicKey.removeFromKeychain()
        try privateKey.removeFromKeychain()
    }
    
    public func externalPublicKey() throws -> Data {
        return try publicKey.externalRepresentation()
    }
    
    public func sign(message: Data) throws -> Data {
        return try privateKey.sign(message: message)
    }
    
    public func verify(message: Data, signature: Data) throws {
        try publicKey.verify(message: message, signature: signature)
    }
    
    public func encrypt(message plainText: Data) throws -> Data {
        return try publicKey.encrypt(message: plainText)
    }
    
    public func decrypt(message cipherText: Data) throws -> Data {
        return try privateKey.decrypt(message: cipherText)
    }
}