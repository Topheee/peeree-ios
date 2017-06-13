//
//  SecurityHelper.swift
//  Peeree
//
//  Created by Christopher Kobusch on 27.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation

// MARK: - Security

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
    fileprivate let signaturePadding: SecPadding = [] /* SecPadding.PKCS1SHA256 */
    fileprivate let encryptionPadding: SecPadding = [] /* SecPadding.PKCS1SHA256 */
    
    public func removeFromKeychain() throws {
        guard let tag = _tag else { return }
        
        let remquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag]
        try SecKey.check(status: SecItemDelete(remquery as CFDictionary), localizedError: NSLocalizedString("Deleting keychain item failed.", comment: "Removing an item from the keychain produced an error."))
        _tag = nil
    }
    
    public func addToKeychain(tag: Data) throws -> Data {
        assert(_tag == nil, "If this occurs, decide whether it should be allowed to add the key (with a different) tag again")
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecAttrKeySizeInBits as String: size as AnyObject,
                                       kSecValueRef as String: self,
                                       kSecReturnData as String: NSNumber(value: true)]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
        self._tag = tag
        
        return (item as! CFData) as Data
    }
    
    public func addToKeychain(tag: Data) throws {
        assert(_tag == nil, "If this occurs, decide whether it should be allowed to add the key (with a different) tag again")
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecAttrKeySizeInBits as String: size,
                                       kSecValueRef as String: self]
        var item: CFTypeRef?
        try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
        self._tag = tag
    }
    
    public func externalRepresentation() throws -> Data {
        var error: Unmanaged<CFError>?
        if #available(macOS 10.12.1, iOS 10.0, *) {
            guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
                throw error!.takeRetainedValue()
            }
            return data
        } else {
            let tag = "de.kobusch.tempkey2".data(using: .utf8)!
            
            defer {
                // always try to remove key from keychain
                do {
                    try removeFromKeychain()
                } catch {
                    // only log this
                    NSLog("\(error)")
                }
            }
            
            return try addToKeychain(tag: tag)
        }
    }
    
    public init(from data: Data, type: CFString, size: Int) throws {
        self.type = type
        self.size = size
        if #available(macOS 10.12.1, iOS 10.0, *) {
            let attributes: [String : AnyObject] = [
                kSecAttrKeyType as String:            type as AnyObject,
                kSecAttrKeySizeInBits as String:      size as AnyObject]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
                throw error!.takeRetainedValue()
            }
            
            self.key = key
        } else {
            let tag = "de.kobusch.tempkey".data(using: .utf8)!
            
            let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                           kSecAttrKeyType as String: type,
                                           kSecAttrApplicationTag as String: tag,
                                           kSecValueData as String: data,
                                           kSecReturnPersistentRef as String: NSNumber(value: true)]
            var item: CFTypeRef?
            try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))
            
            self.key = item as! SecKey
            self._tag = tag
            
            // always try to remove key from keychain
            do {
                try removeFromKeychain()
            } catch {
                // only log this
                NSLog("\(error)")
            }
        }
    }
    
    public init(from data: Data, type: CFString, size: Int, tag: Data) throws {
        self.type = type
        self.size = size
        let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrKeyType as String: type,
                                       kSecAttrApplicationTag as String: tag,
                                       kSecValueData as String: data,
                                       kSecReturnPersistentRef as String: NSNumber(value: true)]
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
            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            guard SecKeyIsAlgorithmSupported(key, .verify, algorithm) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm \(SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256) does not support verifying", comment: "Error description for verifying exception, which should never actually occur.")])
            }
            
            var error: Unmanaged<CFError>?
            guard SecKeyVerifySignature(key, algorithm, data as CFData, signature as CFData, &error) else {
                throw error!.takeRetainedValue() as Error
            }
        } else {
            #if os(iOS)
                let status = signature.withUnsafeBytes { (signatureBytes: UnsafePointer<UInt8>) in
                    return data.withUnsafeBytes { (dataBytes: UnsafePointer<UInt8>) in
                        SecKeyRawVerify(key, signaturePadding, dataBytes, data.count, signatureBytes, signature.count)
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
                    return plainText.withUnsafeBytes { (plainTextBytes: UnsafePointer<UInt8>) in
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
                throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Elliptic curve algorithm \(SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256) does not support signing", comment: "Error description for signing exception, which should never actually occur.")])
            }
            
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(key, algorithm, data as CFData, &error) as Data? else {
                throw error!.takeRetainedValue() as Error
            }
            
            return signature
        } else {
            #if os(iOS)
                var signatureSize = SecKeyGetBlockSize(key)
                var signature = Data(count: signatureSize)
                let status = signature.withUnsafeMutableBytes { (signatureBytes: UnsafeMutablePointer<UInt8>) in
                    return data.withUnsafeBytes { (dataBytes: UnsafePointer<UInt8>) in
                        SecKeyRawSign(key, signaturePadding, dataBytes, data.count, signatureBytes, &signatureSize)
                    }
                }
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
            
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey : msg])
        }
    }
}

public class KeyPair {
    private let privateKey: AsymmetricPrivateKey
    public let publicKey: AsymmetricPublicKey
    
    public init(privateTag: Data, publicTag: Data, type: CFString, size: Int, persistent: Bool) throws {
        var error: Unmanaged<CFError>?
        var attributes: [String : Any]
            #if os(OSX)
                attributes = [
                    kSecAttrKeyType as String:            type,
                    kSecAttrKeySizeInBits as String:      size,
                    kSecAttrIsPermanent as String:    persistent,
                    kSecAttrApplicationTag as String: privateTag
                ]
            #elseif TARGET_IPHONE_SIMULATOR
                attributes = [
                    kSecAttrKeyType as String:            type,
                    kSecAttrKeySizeInBits as String:      size,
                    kSecPrivateKeyAttrs as String: [
                        kSecAttrIsPermanent as String:    persistent,
                        kSecAttrApplicationTag as String: privateTag
                        ] as CFDictionary,
                    kSecPublicKeyAttrs as String: [
                        kSecAttrIsPermanent as String:    persistent,
                        kSecAttrApplicationTag as String: publicTag
                        ] as CFDictionary
                ]
            #else
                guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error) else {
                    throw error!.takeRetainedValue() as Error
                }
                
//                if #available(iOS 10.0, *) {
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
//                } else {
//                    attributes = [
//                        kSecAttrKeyType as String:            kSecAttrKeyTypeEC,
//                        kSecAttrKeySizeInBits as String:      size as AnyObject,
//                        kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
//                        kSecPrivateKeyAttrs as String: [
//                            kSecAttrIsPermanent as String:    persistent,
//                            kSecAttrApplicationTag as String: tag as AnyObject,
//                            kSecAttrAccessControl as String:  access
//                            ] as CFDictionary
//                    ]
//                }
            #endif
        
        var _publicKey, _privateKey: SecKey?
        try SecKey.check(status: SecKeyGeneratePair(attributes as CFDictionary, &_publicKey, &_privateKey), localizedError: NSLocalizedString("Generating cryptographic key pair failed.", comment: "Low level crypto error."))
        
        privateKey = AsymmetricPrivateKey(key: _privateKey!, type: type, size: size, tag: privateTag)
        
        #if TARGET_IPHONE_SIMULATOR || os(OSX)
            publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size, tag: publicTag)
        #else
            if #available(iOS 10.0, *) {
                publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size, tag: nil)
            } else {
                publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size, tag: nil)
                try publicKey.addToKeychain(tag: publicTag) as Void
            }
        #endif
    }
    
    public init(fromKeychainWith privateTag: Data, publicTag: Data) throws {
        privateKey = try AsymmetricPrivateKey(tag: privateTag)
        #if TARGET_IPHONE_SIMULATOR || os(OSX)
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
/*
 @available(OSX 10.12.1, iOS 10.0, *)
 public struct SecureEnclaveKeyPair {
 private let privateKey: SecKey
 private let publicKey: SecKey
 
 public func externalPublicKey() throws -> Data {
 var error: Unmanaged<CFError>?
 guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
 throw error!.takeRetainedValue() as Error
 }
 return data
 }
 
 public init(tag: Data, persistent: Bool) throws {
 var error: Unmanaged<CFError>?
 guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error) else {
 throw error!.takeRetainedValue() as Error
 }
 
 let attributes: [String : AnyObject] = [
 kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
 kSecAttrKeySizeInBits as String:      256 as AnyObject,
 //            kSecAttrKeySizeInBits as String: SecKeySizes.secp256r1.rawValue as AnyObject, only available on macOS...
 //            kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
 kSecPrivateKeyAttrs as String: [
 kSecAttrIsPermanent as String:    NSNumber(value: persistent),
 kSecAttrApplicationTag as String: tag,
 kSecAttrAccessControl as String:  access
 ] as CFDictionary
 ]
 
 guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
 throw error!.takeRetainedValue() as Error
 }
 
 privateKey = key
 
 guard let pKey = SecKeyCopyPublicKey(privateKey) else {
 throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : NSLocalizedsString("no public key derivable", comment: "Low level error.")])
 }
 
 publicKey = pKey
 
 if let attrs = SecKeyCopyAttributes(publicKey) {
 print("Attributes: \(attrs)")
 }
 
 guard persistent else { return }
 
 //        let tag = tag.data(using: .utf8)!
 let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
 kSecAttrApplicationTag as String: tag,
 kSecValueRef as String: key]
 let status = SecItemAdd(addquery as CFDictionary, nil)
 guard status == errSecSuccess else {
 #if os(OSX)
 let msg = SecCopyErrorMessageString(status, nil) ?? "Adding key to keychain failed" as CFString
 #else
 let msg = NSLocalizedString("Adding key to keychain failed.", comment: "Low level error.")
 #endif
 
 throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey : msg])
 }
 }
 
 public init(fromKeychainWith tag: Data) throws {
 let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
 kSecAttrApplicationTag as String: tag,
 kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
 kSecReturnRef as String: NSNumber(value: true)]
 var item: CFTypeRef?
 let status = SecItemCopyMatching(getquery as CFDictionary, &item)
 guard status == errSecSuccess else {
 #if os(OSX)
 let msg = SecCopyErrorMessageString(status, nil) ?? "Reading key from keychain failed" as CFString
 #else
 let msg = NSLocalizedString("Reading key from failed.", comment: "Low level error.")
 #endif
 
 throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey : msg])
 }
 
 privateKey = item as! SecKey
 
 guard let pKey = SecKeyCopyPublicKey(privateKey) else {
 throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("no public key derivable", comment: "Low level error.")])
 }
 
 publicKey = pKey
 }
 
 public func sign(message data: Data) throws -> Data {
 let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
 guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
 throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedsString("Elliptic curve algorithm \(SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256) does not support signing", comment: "Error description for signing exception, which should never actually occur.")])
 }
 
 var error: Unmanaged<CFError>?
 guard let signature = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) as Data? else {
 throw error!.takeRetainedValue() as Error
 }
 
 return signature
 }
 
 public func verify(message data: Data, signature: Data) throws -> Bool {
 let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
 guard SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm) else {
 throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedsString("Elliptic curve algorithm \(SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256) does not support verifying", comment: "Error description for verifying exception, which should never actually occur.")])
 }
 
 var error: Unmanaged<CFError>?
 guard SecKeyVerifySignature(publicKey, algorithm, data as CFData, signature as CFData, &error) else {
 throw error!.takeRetainedValue() as Error
 }
 
 return true
 }
 
 public func encrypt(message plainText: Data) throws -> Data {
 let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM // does not work: ecdhKeyExchangeStandardX963SHA256, ecdhKeyExchangeCofactor
 guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
 throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedsString("Elliptic curve algorithm \(SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM) does not support encryption", comment: "Error description for encryption exception, which should never actually occur.")])
 }
 
 let padding = 0 // TODO find out how much it is for ECDH
 guard plainText.count < (SecKeyGetBlockSize(publicKey)-padding) else {
 throw NSError(domain: NSCocoaErrorDomain, code: NSValidationErrorMaximum, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("Plain text length (\(plainText.count)) exceeds block size \(SecKeyGetBlockSize(publicKey)-padding)", comment: "Exception when trying to encrypt too-big data.")])
 }
 
 var error: Unmanaged<CFError>?
 guard let cipherText = SecKeyCreateEncryptedData(publicKey, algorithm, plainText as CFData, &error) as Data? else {
 throw error!.takeRetainedValue() as Error
 }
 
 return cipherText
 }
 
 public func decrypt(message cipherText: Data) throws -> Data {
 let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM
 guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
 throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedsString("Elliptic curve algorithm \(SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM) does not support decryption", comment: "Error description for decryption exception, which should never actually occur.")])
 }
 
 //        guard cipherText.count == SecKeyGetBlockSize(privateKey) else {
 //            throw NSError(domain: NSCocoaErrorDomain, code: NSValidationErrorMaximum, userInfo: [NSLocalizedDescriptionKey : NSLocalizedsString("Cipher text length (\(cipherText.count)) not match block size \(SecKeyGetBlockSize(privateKey))", comment: "Exception when trying to decrypt data of wrong length.")])
 //        }
 
 var error: Unmanaged<CFError>?
 guard let clearText = SecKeyCreateDecryptedData(privateKey, algorithm, cipherText as CFData, &error) as Data? else {
 throw error!.takeRetainedValue() as Error
 }
 
 return clearText
 }
 }
 */
