//
//  KeychainAccess.swift
//  Peeree
//
//  Created by Christopher Kobusch on 18.04.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation

/// Extracts a cryptographic key from the system's Keychain.
func keyFromKeychain(label: String, tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws -> SecKey {
	let getquery: [String: Any] = [kSecAttrLabel as String: label as CFString,
								   kSecClass as String: kSecClassKey,
								   kSecAttrKeyClass as String: keyClass,
								   kSecAttrKeyType as String: keyType,
								   kSecAttrKeySizeInBits as String: size,
								   kSecAttrApplicationTag as String: tag,
								   kSecReturnRef as String: NSNumber(value: true)]
	var item: CFTypeRef?
	try SecKey.check(status: SecItemCopyMatching(getquery as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))

	return item as! SecKey
}

/// Extracts an encoded cryptographic key from the system's Keychain.
func keyDataFromKeychain(label: String, tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws -> Data {
	let getquery: [String: Any] = [kSecAttrLabel as String: label as CFString,
								   kSecClass as String: kSecClassKey,
								   kSecAttrKeyClass as String: keyClass,
								   kSecAttrKeySizeInBits as String: size,
								   kSecAttrApplicationTag as String: tag,
								   kSecAttrKeyType as String: keyType,
								   kSecReturnData as String: NSNumber(value: true)]
	var item: CFTypeRef?
	try SecKey.check(status: SecItemCopyMatching(getquery as CFDictionary, &item), localizedError: NSLocalizedString("Reading key from keychain failed.", comment: "Attempt to read a keychain item failed."))

	return (item as! CFData) as Data
}

/// Inserts a cryptographic key into the system's Keychain.
func addToKeychain(key: SecKey, label: String, tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws -> Data {
	let addquery: [String: Any]
	if #available(OSX 10.15, iOS 13.0, *) {
		addquery = [kSecAttrLabel as String: label as CFString,
					kSecUseDataProtectionKeychain as String: true as CFBoolean,
					kSecClass as String: kSecClassKey,
					kSecAttrKeyClass as String: keyClass,
					kSecValueRef as String: key,
					kSecAttrKeySizeInBits as String: size,
					kSecAttrApplicationTag as String: tag,
					kSecAttrKeyType as String: keyType,
					kSecReturnData as String: NSNumber(value: true)]
	} else {
		addquery = [kSecAttrLabel as String: label as CFString,
					kSecClass as String: kSecClassKey,
					kSecAttrKeyClass as String: keyClass,
					kSecValueRef as String: key,
					kSecAttrKeySizeInBits as String: size,
					kSecAttrApplicationTag as String: tag,
					kSecAttrKeyType as String: keyType,
					kSecReturnData as String: NSNumber(value: true)]
	}
	var item: CFTypeRef?
	try SecKey.check(status: SecItemAdd(addquery as CFDictionary, &item), localizedError: NSLocalizedString("Adding key data to keychain failed.", comment: "Writing raw key data to the keychain produced an error."))

	return (item as! CFData) as Data
}

/// Purges a cryptographic key from the system's Keychain.
func removeFromKeychain(tag: Data, keyType: CFString, keyClass: CFString, size: Int) throws {
	let remquery: [String: Any] = [kSecClass as String:					kSecClassKey,
								   kSecAttrKeyClass as String:			keyClass,
								   kSecAttrKeySizeInBits as String:		size,
								   kSecAttrApplicationTag as String:	tag,
								   kSecAttrKeyType as String:			keyType]
	try SecKey.check(status: SecItemDelete(remquery as CFDictionary), localizedError: NSLocalizedString("Deleting keychain item failed.", comment: "Removing an item from the keychain produced an error."))
}

/// Writes a generic unspecified secret.
func persistSecretInKeychain(secret: String, label: String) throws {
	guard let tokenData = secret.data(using: .utf8) else { throw unexpectedNilError() }

	// Delete old token first (if available).
	var query: [String: Any] = [kSecClass as String:		kSecClassGenericPassword,
								kSecAttrLabel as String:	label]
	SecItemDelete(query as CFDictionary)

	query = [kSecClass as String:		kSecClassGenericPassword,
			 kSecAttrLabel as String:	label,
			 kSecValueData as String:	tokenData]
	try SecKey.check(status: SecItemAdd(query as CFDictionary, nil), localizedError: NSLocalizedString("Adding secret to Keychain failed", comment: "SecItemAdd failed"))
}

/// Retrieves an internet password from the keychain.
func secretFromKeychain(label: String) throws -> String {
	let query: [String: Any] = [kSecClass as String:		kSecClassGenericPassword,
								kSecAttrLabel as String:	label,
								kSecMatchLimit as String:	kSecMatchLimitOne,
								kSecReturnData as String:	true]
	var item: CFTypeRef?
	try SecKey.check(status: SecItemCopyMatching(query as CFDictionary, &item), localizedError: NSLocalizedString("Reading internet password from keychain failed.", comment: "Attempt to read a keychain item failed."))

	guard let passwordData = item as? Data,
		  let password = String(data: passwordData, encoding: String.Encoding.utf8) else {
		throw createApplicationError(localizedDescription: "passwordData is nil or not UTF-8 encoded.")
	}

	return password
}

/// Writes the `password` into the keychain as an internet password.
func persistInternetPasswordInKeychain(account: String, url: URL, _ password: Data) throws {
	let query: [String: Any] = [kSecClass as String:		kSecClassInternetPassword,
								kSecAttrAccount as String:	account,
								kSecAttrServer as String:	url.absoluteString,
								kSecValueData as String:	password]
	try SecKey.check(status: SecItemAdd(query as CFDictionary, nil), localizedError: NSLocalizedString("Adding internet password to Keychain failed", comment: "SecItemAdd failed"))
}

/// Retrieves an internet password from the keychain.
func internetPasswordFromKeychain(account: String, url: URL) throws -> String {
	let query: [String: Any] = [kSecClass as String:		kSecClassInternetPassword,
								kSecAttrServer as String:	url.absoluteString,
								kSecAttrAccount as String:	account,
								kSecMatchLimit as String:	kSecMatchLimitOne,
								kSecReturnData as String:	true]
	var item: CFTypeRef?
	try SecKey.check(status: SecItemCopyMatching(query as CFDictionary, &item), localizedError: NSLocalizedString("Reading internet password from keychain failed.", comment: "Attempt to read a keychain item failed."))

	guard let passwordData = item as? Data,
		  let password = String(data: passwordData, encoding: String.Encoding.utf8) else {
		throw createApplicationError(localizedDescription: "passwordData is nil or not UTF-8 encoded.")
	}

	return password
}

/// Purges an internet password from the keychain.
func removeInternetPasswordFromKeychain(account: String, url: URL) throws {
	let query: [String: Any] = [kSecClass as String:		kSecClassInternetPassword,
								kSecAttrAccount as String:	account,
								kSecAttrServer as String:	url.absoluteString]
	try SecKey.check(status: SecItemDelete(query as CFDictionary), localizedError: NSLocalizedString("Deleting key from keychain failed.", comment: "Attempt to delete a keychain item failed."))
}
