//
//  AsymmetricCrypto.swift
//  Peeree
//
//  Created by Christopher Kobusch on 27.05.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import Foundation
import CommonCrypto

extension Data {
	/// Computes the SHA-256 digest hash of this data.
	func sha256() -> Data {
		let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
		var digest = Data(count: digestLength)
		_ = digest.withUnsafeMutablePointer({ (digestMutableBytes) in
			self.withUnsafePointer({ (plainTextBytes) in
				CC_SHA256(plainTextBytes, CC_LONG(self.count), digestMutableBytes)
			})
		})
		return digest
	}
}

/// Represents a public or private asymmetric key.
public class AsymmetricKey: Codable {
	/// Padding to be used for cryptographic operations applying this key.
	fileprivate static let signaturePadding: SecPadding = [], encryptionPadding: SecPadding = [] // .PKCS1SHA256

	/// Which properties should be serialized; automatically read by ``Codable`` protocol.
	enum CodingKeys: String, CodingKey {
		case key, keyClass, type, size
	}

	/// Opaque container of the asymmetric key this class wraps around.
	fileprivate let key: SecKey

	/// Cryptographic property of `key`.
	public let keyClass: CFString, type: CFString, size: Int

	/// See ``SecKeyGetBlockSize(_:)``.
	public var blockSize: Int { return SecKeyGetBlockSize(key) }

	/// Obtains the binary representation of this key.
	///
	/// Should only be used for public keys, since private keys should remain in the keychain.
	///
	/// - Returns: The mathematical representation of the key in binary Format. See ``SecKeyCopyExternalRepresentation(_:_:)`` for more information.
	///
	/// - Throws: An `NSError` if the key is not exportable.
	public func externalRepresentation() throws -> Data {
		if #available(macOS 10.12.1, iOS 10.0, *) {
			var error: Unmanaged<CFError>?
			guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
				throw error!.takeRetainedValue()
			}
			return data
		} else {
			let temporaryTag = try generateRandomData(length: 4)
			let temporaryLabel = temporaryTag.base64EncodedString()

			defer {
				// always try to remove key from keychain
				do {
					try removeFromKeychain(tag: temporaryTag, keyType: type, keyClass: keyClass, size: size)
				} catch {
					// only log this
					wlog("Removing temporary key from keychain failed: \(error)")
				}
			}
			
			return try addToKeychain(key: key, label: temporaryLabel, tag: temporaryTag, keyType: type, keyClass: keyClass, size: size)
		}
	}

	/// Parses `data` based on the key properties provided to this method.
	///
	/// - Throws: An `NSError` if `data` does not contain an appropriate representation of a key.
	fileprivate convenience init(from data: Data, type: CFString, size: Int, keyClass: CFString) throws {
		if #available(macOS 10.12.1, iOS 10.0, *) {
			let attributes: [String : Any] = [
				kSecAttrKeyType as String:			type,
				kSecAttrKeySizeInBits as String:	  size,
				kSecAttrKeyClass as String:		   keyClass]
			var error: Unmanaged<CFError>?
			guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
				throw error!.takeRetainedValue()
			}

			self.init(key: key, type: type, keyClass: keyClass, size: size)
		} else {
			let tag = try generateRandomData(length: 4)
			let temporaryLabel = tag.base64EncodedString()

			// always try to remove key from keychain before we add it again
			try? removeFromKeychain(tag: tag, keyType: type, keyClass: keyClass, size: size)
			
			defer {
				// always try to remove key from keychain when we added it
				do {
					try removeFromKeychain(tag: tag, keyType: type, keyClass: keyClass, size: size)
				} catch {
					// only log this
					ilog("Removing temporary key from keychain failed: \(error)")
				}
			}
			
			let addquery: [String: Any] = [kSecClass as String: kSecClassKey,
										   kSecAttrKeyType as String: type,
										   kSecAttrApplicationTag as String: tag,
										   kSecAttrKeySizeInBits as String: size,
										   kSecValueData as String: data,
										   kSecAttrLabel as String: temporaryLabel as CFString,
										   kSecAttrKeyClass as String: keyClass,
										   kSecReturnRef as String: NSNumber(value: true)]
			var item: CFTypeRef?
			try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", tableName: "AsymmetricCrypto", comment: "Writing raw key data to the keychain produced an error."))

			self.init(key: item as! SecKey, type: type, keyClass: keyClass, size: size)
		}
	}

	/// Sets the properties directly and does not validate them.
	fileprivate init(key: SecKey, type: CFString, keyClass: CFString, size: Int) {
		self.type = type
		self.size = size
		self.key = key
		self.keyClass = keyClass
	}

	/// Decodes the properties, but does not validate them.
	///
	/// - Throws: An `NSError` if the binary data is invalid.
	required public convenience init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(from: try values.decode(Data.self, forKey: .key),
					  type: try values.decode(String.self, forKey: .type) as CFString,
					  size: try values.decode(Int.self, forKey: .size),
					  keyClass: try values.decode(String.self, forKey: .keyClass) as CFString)
	}

	/// Encodes the key properties and external representation.
	///
	/// - Throws: The error from ``externalRepresentation()``, if any.
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(externalRepresentation(), forKey: .key)
		try container.encode(type as String, forKey: .type)
		try container.encode(size, forKey: .size)
		try container.encode(keyClass as String, forKey: .keyClass)
	}
}

/// Represents a public asymmetric key.
public class AsymmetricPublicKey: AsymmetricKey {
	/// Hides this initializer by making it `private`.
	private override init(key: SecKey, type: CFString, keyClass: CFString, size: Int) {
		// we need to override (all) the superclasses designated initializers to inherit its convenience initializers (and thus the Codable initializer we want)
		super.init(key: key, type: type, keyClass: kSecAttrKeyClassPublic, size: size)
	}

	/// Initializes  `AsymmetricKey` with `keyClass` `kSecAttrKeyClassPublic`.
	public convenience init(from data: Data, type: CFString, size: Int) throws {
		try self.init(from: data, type: type, size: size, keyClass: kSecAttrKeyClassPublic)
	}

	/// Initializes  `AsymmetricKey` with `keyClass` `kSecAttrKeyClassPublic`.
	fileprivate init(key: SecKey, type: CFString, size: Int) {
		super.init(key: key, type: type, keyClass: kSecAttrKeyClassPublic, size: size)
	}

	/// Checks the integrity of `message` by calculating, whether the `signature` was computed with the corresponding private key to this public key.
	///
	/// - Throws: An `NSError` if the signature is invalid or the verification process failed.
	public func verify(message data: Data, signature: Data) throws {
		if #available(macOS 10.12.1, iOS 10.0, *) {
			let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
			guard SecKeyIsAlgorithmSupported(key, .verify, algorithm) else {
				let errorFormat = NSLocalizedString("Elliptic curve algorithm %@ does not support verifying.", tableName: "AsymmetricCrypto", comment: "Error description for verifying exception, which should never actually occur")

				let errorDescription = String(format: errorFormat, SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256.rawValue as String)
				throw NSError(domain: AsymmetricCryptoErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : errorDescription])
			}

			var error: Unmanaged<CFError>?
			guard SecKeyVerifySignature(key, algorithm, data as CFData, signature as CFData, &error) else {
				throw error!.takeUnretainedValue() as Error
			}
		} else {
			#if os(iOS)
				let digest = data.sha256()
				
				let status = signature.withUnsafePointer { (signatureBytes: UnsafePointer<UInt8>) in
					return digest.withUnsafePointer { (digestBytes: UnsafePointer<UInt8>) in
						SecKeyRawVerify(key, AsymmetricKey.signaturePadding, digestBytes, digest.count, signatureBytes, signature.count)
					}
				}
				
				try SecKey.check(status: status, localizedError: NSLocalizedString("Verifying signature failed.", tableName: "AsymmetricCrypto", comment: "Cryptographically verifying a message failed."))
			#else
				throw makeOldMacOSUnsupportedError()
//			var _error: Unmanaged<CFError>? = nil
//			let _transform = SecVerifyTransformCreate(key, signature as CFData, &_error)
//			guard let transform = _transform else {
//				throw _error!.takeRetainedValue()
//			}
//			guard SecTransformSetAttribute(transform, kSecTransformInputAttributeName, data as CFData, &_error) else {
//				throw _error!.takeRetainedValue()
//			}
//			SecTransformExecute(<#T##transformRef: SecTransform##SecTransform#>, <#T##errorRef: UnsafeMutablePointer<Unmanaged<CFError>?>?##UnsafeMutablePointer<Unmanaged<CFError>?>?#>)
			#endif
		}
	}

	/// Encrypts `message`, s.t. it can only be decrypted by the corresponding private key to this public key.
	///
	/// - Returns: Cipher text of `message`, which can be decrypted with ``AsymmetricPrivateKey/decrypt(message:)``.
	///
	/// - Throws: An `NSError` if the encryption process failed.
	public func encrypt(message plainText: Data) throws -> Data {
		if #available(macOS 10.12.1, iOS 10.0, *) {
			let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM // does not work: ecdhKeyExchangeStandardX963SHA256, ecdhKeyExchangeCofactor
			guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm) else {
				let errorFormat = NSLocalizedString("Elliptic curve algorithm %@ does not support encryption.", tableName: "AsymmetricCrypto", comment: "Error description for verifying exception, which should never actually occur")

				let errorDescription = String(format: errorFormat, algorithm.rawValue as String)
				throw NSError(domain: AsymmetricCryptoErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : errorDescription])
			}
			
			let padding = 0 // TODO find out how much it is for ECDH
			guard plainText.count <= (SecKeyGetBlockSize(key)-padding) else {
				let errorFormat = NSLocalizedString("Plain text length (%d) exceeds block size %d", tableName: "AsymmetricCrypto", comment: "Exception when trying to encrypt too-big data.")

				let errorDescription = String(format: errorFormat, plainText.count, SecKeyGetBlockSize(key)-padding)
				throw NSError(domain: NSCocoaErrorDomain, code: NSValidationErrorMaximum, userInfo: [NSLocalizedDescriptionKey : errorDescription])
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
				let status = cipher.withUnsafeMutablePointer { (cipherBytes: UnsafeMutablePointer<UInt8>) in
					return plainText.withUnsafePointer { ( plainTextBytes: UnsafePointer<UInt8>) in
						SecKeyEncrypt(key, AsymmetricKey.encryptionPadding, plainTextBytes, plainText.count, cipherBytes, &cipherSize)
					}
				}
				try SecKey.check(status: status, localizedError: NSLocalizedString("Cryptographically encrypting failed.", tableName: "AsymmetricCrypto", comment: "Cryptographically encrypting a message failed."))
				
				return cipher.subdata(in: 0..<cipherSize)
			#else
				throw makeOldMacOSUnsupportedError()
			#endif
		}
	}
}

/// Represents a private asymmetric key.
public class AsymmetricPrivateKey: AsymmetricKey {

	/// Hides this initializer by making it `private`.
	private override init(key: SecKey, type: CFString, keyClass: CFString, size: Int) {
		// we need to override (all) the superclasses designated initializers to inherit its convenience initializers (and thus the Codable initializer we want)
		super.init(key: key, type: type, keyClass: kSecAttrKeyClassPrivate, size: size)
	}

	/// Initializes  `AsymmetricKey` with `keyClass` `kSecAttrKeyClassPrivate`.
	public convenience init(from data: Data, type: CFString, size: Int) throws {
		try self.init(from: data, type: type, size: size, keyClass: kSecAttrKeyClassPrivate)
	}

	/// Initializes  `AsymmetricKey` with `keyClass` `kSecAttrKeyClassPrivate`.
	fileprivate init(key: SecKey, type: CFString, size: Int) {
		super.init(key: key, type: type, keyClass: kSecAttrKeyClassPrivate, size: size)
	}

	/// Produces a digital signature for `message`, which can be used to verify its integrity.
	///
	/// - Returns: The digital signature of `message`, which can be checked with ``AsymmetricPublicKey/verify(message:signature:)``.
	///
	/// - Throws: An `NSError` if the sign process failed.
	public func sign(message data: Data) throws -> Data {
		if #available(macOS 10.12.1, iOS 10.0, *) {
			let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
			guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
				let errorFormat = NSLocalizedString("Elliptic curve algorithm %@ does not support signing.", tableName: "AsymmetricCrypto", comment: "Error description for signing exception, which should never actually occur")

				let errorDescription = String(format: errorFormat, algorithm.rawValue as String)
				throw NSError(domain: AsymmetricCryptoErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : errorDescription])
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
				
				let status = signature.withUnsafeMutablePointer { (signatureBytes: UnsafeMutablePointer<UInt8>) in
					return digest.withUnsafePointer { (digestBytes: UnsafePointer<UInt8>) in
						SecKeyRawSign(key, AsymmetricKey.signaturePadding, digestBytes /* CC_SHA256_DIGEST_LENGTH */, digest.count, signatureBytes, &signatureSize)
					}
				}
				
				try SecKey.check(status: status, localizedError: NSLocalizedString("Cryptographically signing failed.", tableName: "AsymmetricCrypto", comment: "Cryptographically signing a message failed."))
				
				return signature.subdata(in: 0..<signatureSize)
			#else
				throw makeOldMacOSUnsupportedError()
			#endif
		}
	}

	/// Produces plain text for encrypted `message`.
	///
	/// - Returns: The plain text of `message`, which was encrypted with ``AsymmetricPublicKey/encrypt(message:)``.
	///
	/// - Throws: An `NSError` if the decryption process failed.
	public func decrypt(message cipherText: Data) throws -> Data {
		if #available(macOS 10.12.1, iOS 10.0, *) {
			let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM
			guard SecKeyIsAlgorithmSupported(key, .decrypt, algorithm) else {
				let errorFormat = NSLocalizedString("Elliptic curve algorithm %@ does not support decryption.", tableName: "AsymmetricCrypto", comment: "Error description for decryption exception, which should never actually occur")

				let errorDescription = String(format: errorFormat, algorithm.rawValue as String)
				throw NSError(domain: AsymmetricCryptoErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : errorDescription])
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
				let status = cipherText.withUnsafePointer { (cipherTextBytes: UnsafePointer<UInt8>) in
					return plainText.withUnsafeMutablePointer { (plainTextBytes: UnsafeMutablePointer<UInt8>) in
						SecKeyDecrypt(key, AsymmetricKey.encryptionPadding, cipherTextBytes, cipherText.count, plainTextBytes, &plainTextSize)
					}
				}
			try SecKey.check(status: status, localizedError: NSLocalizedString("Decrypting cipher text failed.", tableName: "AsymmetricCrypto", comment: "Cryptographically decrypting a message failed."))
				
				return plainText.subdata(in: 0..<plainTextSize)
			#else
				throw makeOldMacOSUnsupportedError()
			#endif
		}
	}
	
}

/// Container for an asymmetric key pair.
public struct KeyPair {
	/// Private part of this key pair, which needs to be kept secure.
	private let privateKey: AsymmetricPrivateKey

	/// Public part of this key pair, which can be passed around publicly.
	public let publicKey: AsymmetricPublicKey

	/// Keychain item property.
	let privateTag: Data, publicTag: Data, label: String

	/// The block size of the private key.
	public var blockSize: Int { return privateKey.blockSize }

	/// Generates a key pair and optionally stores it in the keychain.
	public init(label: String, privateTag: Data, publicTag: Data, type: CFString, size: Int, persistent: Bool, useEnclave: Bool = false) throws {
		self.privateTag = privateTag
		self.publicTag = publicTag
		self.label = label
		var error: Unmanaged<CFError>?
		var attributes: [String : Any]
		if useEnclave {
			guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error) else {
				throw error!.takeRetainedValue() as Error
			}
			attributes = [
				kSecAttrLabel as String:			  label as CFString,
				kSecAttrKeyType as String:			type,
				kSecAttrKeySizeInBits as String:	  size,
				kSecAttrTokenID as String:			kSecAttrTokenIDSecureEnclave,
				kSecPrivateKeyAttrs as String: [
					kSecAttrIsPermanent as String:	persistent,
					kSecAttrApplicationTag as String: privateTag,
					kSecAttrAccessControl as String:  access
					] as CFDictionary,
				kSecPublicKeyAttrs as String: [
					kSecAttrIsPermanent as String:	persistent,
					kSecAttrApplicationTag as String: publicTag,
					kSecAttrAccessControl as String:  access
					] as CFDictionary
			]
		} else {
			attributes = [
				kSecAttrLabel as String:			  label as CFString,
				kSecAttrKeyType as String:			type,
				kSecAttrKeySizeInBits as String:	  size,
				kSecAttrIsExtractable as String:	  false as CFBoolean,
				kSecPrivateKeyAttrs as String: [
					kSecAttrIsPermanent as String:	persistent,
					kSecAttrApplicationTag as String: privateTag
					] as CFDictionary,
				kSecPublicKeyAttrs as String: [
					kSecAttrIsPermanent as String:	persistent,
					kSecAttrApplicationTag as String: publicTag
					] as CFDictionary
			]
		}
		
		var _publicKey, _privateKey: SecKey?
		try SecKey.check(status: SecKeyGeneratePair(attributes as CFDictionary, &_publicKey, &_privateKey), localizedError: NSLocalizedString("Generating cryptographic key pair failed.", tableName: "AsymmetricCrypto", comment: "Low level crypto error."))
		
		ilog("Created key pair with block sizes \(SecKeyGetBlockSize(_privateKey!)), \(SecKeyGetBlockSize(_publicKey!))")
		
		privateKey = AsymmetricPrivateKey(key: _privateKey!, type: type, size: size)
		
		#if (os(iOS) && (arch(x86_64) || arch(i386))) || os(macOS) // iPhone Simulator or macOS
			publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size)
		#else
			publicKey = AsymmetricPublicKey(key: _publicKey!, type: type, size: size)
		#endif
	}

	/// Loads a key pair from the system keychain.
	public init(fromKeychainWith label: String, privateTag: Data, publicTag: Data, type: CFString, size: Int) throws {
		self.privateTag = privateTag
		self.publicTag = publicTag
		self.label = label
		privateKey = try privateKeyFromKeychain(label: label, tag: privateTag, type: type, size: size)
		#if ((arch(i386) || arch(x86_64)) && os(iOS)) || os(macOS) // iPhone Simulator or macOS
			publicKey = try publicKeyFromKeychain(label: label, tag: publicTag, type: type, size: size)
		#else
		if #available(iOS 10.0, *) {
			guard let pubKey = SecKeyCopyPublicKey(privateKey.key) else {
				throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInvalidAttributePrivateKeyFormat), userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("No public key derivable.", tableName: "AsymmetricCrypto", comment: "Low level error.")])
			}
			publicKey = AsymmetricPublicKey(key: pubKey, type: type, size: size)
		} else {
			publicKey = try publicKeyFromKeychain(label: label, tag: publicTag, type: type, size: size)
		}
		#endif
	}

	/// Deletes the keys in the keychain.
	public func removeFromKeychain() throws {
		// it is not so critical when the public key remains, but more critical when the private one remains
		try? Peeree.removeFromKeychain(key: publicKey, label: label, tag: publicTag)
		try Peeree.removeFromKeychain(key: privateKey, label: label, tag: privateTag)
	}

	/// Obtains the binary representation of the public key, s.t. it can be distributed.
	public func externalPublicKey() throws -> Data {
		return try publicKey.externalRepresentation()
	}

	/// Signs `message` using the private key; see also ``AsymmetricPrivateKey/sign(message:)``.
	public func sign(message: Data) throws -> Data {
		return try privateKey.sign(message: message)
	}

	/// Verifies `message` using the public key; see also ``AsymmetricPublicKey/verify(message:signature:)``.
	public func verify(message: Data, signature: Data) throws {
		try publicKey.verify(message: message, signature: signature)
	}

	/// Encrypts `message` using the public key; see also ``AsymmetricPublicKey/encrypt(message:)``.
	public func encrypt(message plainText: Data) throws -> Data {
		return try publicKey.encrypt(message: plainText)
	}

	/// Decrypts `message` using the private key; see also ``AsymmetricPrivateKey/decrypt(message:)``.
	public func decrypt(message cipherText: Data) throws -> Data {
		return try privateKey.decrypt(message: cipherText)
	}
}

/// Wrapper-function around addToKeychain() for `SecKey`.
func addToKeychain(key: AsymmetricKey, label: String, tag: Data) throws -> Data {
	return try addToKeychain(key: key.key, label: label, tag: tag, keyType: key.type, keyClass: key.keyClass, size: key.size)
}

/// Wrapper-function around removeFromKeychain() for `SecKey`.
func removeFromKeychain(key: AsymmetricKey, label: String, tag: Data) throws {
	try removeFromKeychain(tag: tag, keyType: key.type, keyClass: key.keyClass, size: key.size)
}

/// Wrapper-function around keyFromKeychain() for `SecKey`.
func publicKeyFromKeychain(label: String, tag: Data, type: CFString, size: Int) throws -> AsymmetricPublicKey {
	let key = try keyFromKeychain(label: label, tag: tag, keyType: type, keyClass: kSecAttrKeyClassPublic, size: size)
	return AsymmetricPublicKey(key: key, type: type, size: size)
}

/// Wrapper-function around keyFromKeychain() for `SecKey`.
func privateKeyFromKeychain(label: String, tag: Data, type: CFString, size: Int) throws -> AsymmetricPrivateKey {
	let key = try keyFromKeychain(label: label, tag: tag, keyType: type, keyClass: kSecAttrKeyClassPrivate, size: size)
	return AsymmetricPrivateKey(key: key, type: type, size: size)
}

/// The `domain` value of errors created within this file.
///
/// > Note: Errors from other domains, such as `NSCocoaErrorDomain`, may still be thrown.
private let AsymmetricCryptoErrorDomain = "AsymmetricCryptoErrorDomain";

/// Creates an error indicating that macOS below 10.12.1 is not supported.
private func makeOldMacOSUnsupportedError() -> Error {
	return NSError(domain: AsymmetricCryptoErrorDomain, code: NSFeatureUnsupportedError, userInfo: [NSLocalizedDescriptionKey : NSLocalizedString("macOS below 10.12.1 is not supported.", tableName: "AsymmetricCrypto", comment: "Error description for cryptographic operation failure")])
}
