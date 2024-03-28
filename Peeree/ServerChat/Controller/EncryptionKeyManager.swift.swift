//
//  EncryptionKeyManager.swift.swift
//  PeereeServerChat
//
//  Created by Christopher Kobusch on 23.09.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

//
// Copyright 2020 New Vector Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import KeychainWrapper
import CommonCrypto
import MatrixSDK

final class EncryptionKeyManager: NSObject, MXKeyProviderDelegate {
	static let shared = EncryptionKeyManager()

	private static let keychainService: String = "EncryptionKeyManager.encryption-manager-service"
	private static let contactsIv: String = "EncryptionKeyManager.contactsIv"
	private static let contactsAesKey: String = "EncryptionKeyManager.contactsAesKey"
	private static let accountIv: String = "EncryptionKeyManager.accountIv"
	private static let accountAesKey: String = "EncryptionKeyManager.accountAesKey"
	private static let cryptoOlmPickleKey: String = "EncryptionKeyManager.cryptoOlmPickleKey"
	private static let roomLastMessageIv: String = "EncryptionKeyManager.roomLastMessageIv"
	private static let roomLastMessageAesKey: String = "EncryptionKeyManager.roomLastMessageAesKey"
	private static let cryptoSDKStoreKey: String = "EncryptionKeyManager.cryptoSDKStoreKey"

	private override init() {
		super.init()
		initKeys()
	}

	private func initKeys() {
		generateIvIfNotExists(forKey: EncryptionKeyManager.accountIv)
		generateAesKeyIfNotExists(forKey: EncryptionKeyManager.accountAesKey)
		generateIvIfNotExists(forKey: EncryptionKeyManager.contactsIv)
		generateAesKeyIfNotExists(forKey: EncryptionKeyManager.contactsAesKey)
		generateKeyIfNotExists(forKey: EncryptionKeyManager.cryptoOlmPickleKey, size: 32)
		generateIvIfNotExists(forKey: EncryptionKeyManager.roomLastMessageIv)
		generateAesKeyIfNotExists(forKey: EncryptionKeyManager.roomLastMessageAesKey)
		generateKeyIfNotExists(forKey: EncryptionKeyManager.cryptoSDKStoreKey, size: 32)
	}

	// MARK: - MXKeyProviderDelegate

	func isEncryptionAvailableForData(ofType dataType: String) -> Bool {
		return dataType == MXCryptoOlmPickleKeyDataType
			|| dataType == MXRoomLastMessageDataType
			|| dataType == MXCryptoSDKStoreKeyDataType
	}

	func hasKeyForData(ofType dataType: String) -> Bool {
		return keyDataForData(ofType: dataType) != nil
	}

	func keyDataForData(ofType dataType: String) -> MXKeyData? {
		switch dataType {
		case MXCryptoOlmPickleKeyDataType:
			if let key = try? KeychainWrapper.genericPasswordFromKeychain(account: Self.cryptoOlmPickleKey, service: Self.keychainService) {
				return MXRawDataKey(key: key)
			}
		case MXRoomLastMessageDataType:
			if let ivKey = try? KeychainWrapper.genericPasswordFromKeychain(account: Self.roomLastMessageIv, service: Self.keychainService),
			   let aesKey = try? KeychainWrapper.genericPasswordFromKeychain(account: Self.roomLastMessageAesKey, service: Self.keychainService) {
				return MXAesKeyData(iv: ivKey, key: aesKey)
			}
		case MXCryptoSDKStoreKeyDataType:
			if let key = try? KeychainWrapper.genericPasswordFromKeychain(account: Self.cryptoSDKStoreKey, service: Self.keychainService) {
				return MXRawDataKey(key: key)
			}
		default:
			MXLog.failure("[EncryptionKeyManager] keyDataForData: Attempting to get data for unknown type", dataType)
			return nil
		}
		return nil
	}

	// MARK: - Private methods

	private func generateIvIfNotExists(forKey key: String) {
		guard ((try? KeychainWrapper.genericPasswordFromKeychain(account: key, service: Self.keychainService)) == nil) else {
			return
		}

		do {
			try KeychainWrapper.persistGenericPasswordInKeychain(MXAes.iv(), account: key, service: Self.keychainService)
		} catch {
			MXLog.debug("[EncryptionKeyManager] initKeys: Failed to generate IV: \(error.localizedDescription)")
		}
	}

	private func generateAesKeyIfNotExists(forKey key: String) {
		generateKeyIfNotExists(forKey: key, size: kCCKeySizeAES256)
	}

	private func generateKeyIfNotExists(forKey key: String, size: Int) {
		guard ((try? KeychainWrapper.genericPasswordFromKeychain(account: key, service: Self.keychainService)) == nil) else {
			return
		}

		do {
			var keyBytes = [UInt8](repeating: 0, count: size)
			  _ = SecRandomCopyBytes(kSecRandomDefault, size, &keyBytes)
			try KeychainWrapper.persistGenericPasswordInKeychain(Data(bytes: keyBytes, count: size), account: key, service: Self.keychainService)
		} catch {
			MXLog.debug("[EncryptionKeyManager] initKeys: Failed to generate Key[\(key)]: \(error.localizedDescription)")
		}
	}
}

