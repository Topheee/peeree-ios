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

public class KeychainStore {
	/// low-level keychain manipulation
	public static func keyFromKeychain(tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws -> SecKey {
		let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
									   kSecAttrKeyClass as String: keyClass,
									   kSecAttrKeyType as String: keyType,
									   kSecAttrKeySizeInBits as String: size,
									   kSecAttrApplicationTag as String: tag,
									   kSecReturnRef as String: NSNumber(value: true)]
		var item: CFTypeRef?
		try SecKey.check(status: SecItemCopyMatching(getquery as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))
		
		return item as! SecKey
	}
	/// low-level keychain manipulation
	public static func keyDataFromKeychain(tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws -> Data {
		let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
									   kSecAttrKeyClass as String: keyClass,
									   kSecAttrKeySizeInBits as String: size,
									   kSecAttrApplicationTag as String: tag,
									   kSecAttrKeyType as String: keyType,
									   kSecReturnData as String: NSNumber(value: true)]
		var item: CFTypeRef?
		try SecKey.check(status: SecItemCopyMatching(getquery as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))
		
		return (item as! CFData) as Data
	}
	/// low-level keychain manipulation
	public static func addToKeychain(key: SecKey, tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws -> Data {
		let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
									   kSecAttrKeyClass as String: keyClass,
									   kSecValueRef as String: key,
									   kSecAttrKeySizeInBits as String: size,
									   kSecAttrApplicationTag as String: tag,
									   kSecAttrKeyType as String: keyType,
									   kSecReturnData as String: NSNumber(value: true)]
		var item: CFTypeRef?
		try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
		
		return (item as! CFData) as Data
	}
	/// low-level keychain manipulation
	public static func removeFromKeychain(tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws {
		let remquery: [String: Any] = [kSecClass as String: kSecClassKey,
									   kSecAttrKeyClass as String: keyClass,
									   kSecAttrKeySizeInBits as String: size,
									   kSecAttrApplicationTag as String: tag,
									   kSecAttrKeyType as String: keyType]
		try SecKey.check(status: SecItemDelete(remquery as CFDictionary), localizedError: NSLocalizedString("Deleting keychain item failed.", comment: "Removing an item from the keychain produced an error."))
	}
	
	public static func addToKeychain(key: AsymmetricKey, tag: Data) throws -> Data {
		return try KeychainStore.addToKeychain(key: key.key, tag: tag, keyType: key.type, keyClass: key.keyClass, size: key.size)
	}
	
	public static func removeFromKeychain(key: AsymmetricKey, tag: Data) throws {
		try KeychainStore.removeFromKeychain(tag: tag, keyType: key.type, keyClass: key.keyClass, size: key.size)
	}
	
	public static func publicKeyFromKeychain(tag: Data, type: CFString, size: Int) throws -> AsymmetricPublicKey {
		let key = try KeychainStore.keyFromKeychain(tag: tag, keyType: type, keyClass: kSecAttrKeyClassPublic, size: size)
		return AsymmetricPublicKey(key: key, type: type, size: size)
	}
	
	public static func privateKeyFromKeychain(tag: Data, type: CFString, size: Int) throws -> AsymmetricPrivateKey {
		let key = try KeychainStore.keyFromKeychain(tag: tag, keyType: type, keyClass: kSecAttrKeyClassPrivate, size: size)
		return AsymmetricPrivateKey(key: key, type: type, size: size)
	}
	
}

public class AsymmetricKey {
	fileprivate static let signaturePadding: SecPadding = [], encryptionPadding: SecPadding = [] // .PKCS1SHA256
    
    fileprivate let key: SecKey
    public let keyClass: CFString, type: CFString, size: Int
    
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
                    try KeychainStore.removeFromKeychain(tag: temporaryTag, keyType: type, keyClass: keyClass, size: size)
                } catch {
                    // only log this
                    NSLog("WARN: Removing temporary key from keychain failed: \(error)")
                }
            }
            
            return try KeychainStore.addToKeychain(key: key, tag: temporaryTag, keyType: type, keyClass: keyClass, size: size)
        }
    }
    
    fileprivate init(from data: Data, type: CFString, size: Int, keyClass: CFString) throws {
        self.type = type
        self.size = size
        self.keyClass = keyClass
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
            try? KeychainStore.removeFromKeychain(tag: tag, keyType: type, keyClass: keyClass, size: size)
            
            defer {
                // always try to remove key from keychain when we added it
                do {
                    try KeychainStore.removeFromKeychain(tag: tag, keyType: type, keyClass: keyClass, size: size)
                } catch {
                    // only log this
                    NSLog("INFO: Removing temporary key from keychain failed: \(error)")
                }
            }
            
            let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                           kSecAttrKeyType as String: type,
                                           kSecAttrApplicationTag as String: tag,
                                           kSecAttrKeySizeInBits as String: size,
                                           kSecValueData as String: data,
                                           kSecAttrKeyClass as String: keyClass,
                                           kSecReturnRef as String: NSNumber(value: true)]
            var item: CFTypeRef?
            try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
            
            self.key = item as! SecKey
        }
    }
    
    fileprivate init(key: SecKey, type: CFString, keyClass: CFString, size: Int) {
        self.type = type
        self.size = size
        self.key = key
        self.keyClass = keyClass
    }
}

public class AsymmetricPublicKey: AsymmetricKey {
    
    public init(from data: Data, type: CFString, size: Int) throws {
        try super.init(from: data, type: type, size: size, keyClass: kSecAttrKeyClassPublic)
    }
	
	fileprivate init(key: SecKey, type: CFString, size: Int) {
		super.init(key: key, type: type, keyClass: kSecAttrKeyClassPublic, size: size)
	}
    
    public func verify(message data: Data, signature: Data) throws {
        if #available(macOS 10.12.1, iOS 10.0, *) {
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
				
                let status = signature.withUnsafeBytes { (signatureBytes: UnsafePointer<UInt8>) in
                    return digest.withUnsafeBytes { (digestBytes: UnsafePointer<UInt8>) in
                        SecKeyRawVerify(key, AsymmetricKey.signaturePadding, digestBytes, digest.count, signatureBytes, signature.count)
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
            guard plainText.count <= (SecKeyGetBlockSize(key)-padding) else {
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
                        SecKeyEncrypt(key, AsymmetricKey.encryptionPadding, plainTextBytes, plainText.count, cipherBytes, &cipherSize)
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
    public init(from data: Data, type: CFString, size: Int) throws {
        try super.init(from: data, type: type, size: size, keyClass: kSecAttrKeyClassPrivate)
    }
	
	fileprivate init(key: SecKey, type: CFString, size: Int) {
		super.init(key: key, type: type, keyClass: kSecAttrKeyClassPrivate, size: size)
	}
    
    public func sign(message data: Data) throws -> Data {
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm does not support signing", comment: "Error description for signing exception, which should never actually occur.")])
            }
            
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(key, algorithm, data as CFData, &error) as Data? else {
                let throwedError = error!.takeRetainedValue() as Error
                throw throwedError
            }
            
            return signature
        } else {
            #if os(iOS)
                let digest = data.sha256()
                
                var signatureSize = 256 // in CryptoExercise it is SecKeyGetBlockSize(key), but on the internet it's some magic number like this
                var signature = Data(count: signatureSize)
                
                let status = signature.withUnsafeMutableBytes { (signatureBytes: UnsafeMutablePointer<UInt8>) in
                    return digest.withUnsafeBytes { (digestBytes: UnsafePointer<UInt8>) in
                        SecKeyRawSign(key, AsymmetricKey.signaturePadding, digestBytes /* CC_SHA256_DIGEST_LENGTH */, digest.count, signatureBytes, &signatureSize)
                    }
                }
				
                try SecKey.check(status: status, localizedError: NSLocalizedString("Cryptographically signing failed.", comment: "Cryptographically signing a message failed."))
                
                return signature.subdata(in: 0..<signatureSize)
            #else
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("macOS below 10.12.1 is not supported", comment: "Error description for signing exception, which should never actually occur.")])
            #endif
        }
    }
    
    public func decrypt(message cipherText: Data) throws -> Data {
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM
            guard SecKeyIsAlgorithmSupported(key, .decrypt, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM does not support decryption", comment: "Error description for decryption exception, which should never actually occur.")])
            }
            
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
                        SecKeyDecrypt(key, AsymmetricKey.encryptionPadding, cipherTextBytes, cipherText.count, plainTextBytes, &plainTextSize)
                    }
                }
                try SecKey.check(status: status, localizedError: NSLocalizedString("Decrypting cipher text failed.", comment: "Cryptographically decrypting a message failed."))
                
                return plainText.subdata(in: 0..<plainTextSize)
            #else
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("macOS below 10.12.1 is not supported", comment: "Error description for decrypting exception, which should never actually occur.")])
            #endif
        }
    }
    
}

extension SecKey {
    static func check(status: OSStatus, localizedError: String) throws {
        guard status == errSecSuccess else {
            #if os(OSX)
                let msg = "\(localizedError) - \(SecCopyErrorMessageString(status, nil) ?? "" as CFString)"
            #else
                let msg = localizedError
            #endif
			NSLog("ERROR: OSStatus \(status) check failed: \(localizedError)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey : msg])
        }
    }
}

public struct KeyPair {
    private let privateKey: AsymmetricPrivateKey
    public let publicKey: AsymmetricPublicKey
	let privateTag: Data, publicTag: Data
    
    public var blockSize: Int { return SecKeyGetBlockSize(privateKey.key) }
    
    public init(privateTag: Data, publicTag: Data, type: CFString, size: Int, persistent: Bool, useEnclave: Bool = false) throws {
		self.privateTag = privateTag
		self.publicTag = publicTag
        var error: Unmanaged<CFError>?
        var attributes: [String : Any]
        #if os(macOS) || (os(iOS) && (arch(x86_64) || arch(i386))) //iPhone Simulator
            attributes = [
                kSecAttrKeyType as String:            type,
                kSecAttrKeySizeInBits as String:      size,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String:    persistent,
                    kSecAttrApplicationTag as String: privateTag
                    ] as CFDictionary
            ]
        #else
            if useEnclave {
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
        
		NSLog("INFO: Created key pair with block sizes \(SecKeyGetBlockSize(_privateKey!)), \(SecKeyGetBlockSize(_publicKey!))")
        
        privateKey = AsymmetricPrivateKey(key: _privateKey!, type: type, size: size)
        
        #if (os(iOS) && (arch(x86_64) || arch(i386))) || os(macOS) // iPhone Simulator or macOS
            publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size)
        #else
            if #available(iOS 10.0, *) {
                publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size)
            } else {
                publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size)
				_ = try KeychainStore.addToKeychain(key: publicKey, tag: publicTag)
            }
        #endif
    }
    
    public init(fromKeychainWith privateTag: Data, publicTag: Data, type: CFString, size: Int) throws {
		self.privateTag = privateTag
		self.publicTag = publicTag
        privateKey = try KeychainStore.privateKeyFromKeychain(tag: privateTag, type: type, size: size)
        #if ((arch(i386) || arch(x86_64)) && os(iOS)) || os(macOS) // iPhone Simulator or macOS
            publicKey = try KeychainStore.publicKeyFromKeychain(tag: publicTag, type: type, size: size)
        #else
        if #available(iOS 10.0, *) {
            guard let pubKey = SecKeyCopyPublicKey(privateKey.key) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInvalidAttributePrivateKeyFormat), userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("No public key derivable.", comment: "Low level error.")])
            }
            publicKey = AsymmetricPublicKey(key: pubKey, type: type, size: size)
        } else {
            publicKey = try KeychainStore.publicKeyFromKeychain(tag: publicTag, type: type, size: size)
        }
        #endif
    }
    
    public func removeFromKeychain() throws {
        try KeychainStore.removeFromKeychain(key: publicKey, tag: publicTag)
        try KeychainStore.removeFromKeychain(key: privateKey, tag: privateTag)
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
