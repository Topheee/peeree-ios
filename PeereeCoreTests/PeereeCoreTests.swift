//
//  PeereeCoreTests.swift
//  PeereeCoreTests
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import Testing
@testable import PeereeCore

import KeychainWrapper

struct PeereeCoreTests {
	private let UserDefaultsKeyTestDict = "UserDefaultsKeyTestDict"

	@Test func testDestroyedPublicKey() throws {
		let key = try KeyPair(
			tag: Data(), algorithm: .ec, size: PeereeIdentity.KeySize)

		let publicKey = try key.publicKey

		try key.removeFromKeychain()

		#expect(throws: Never.self) {
			try PeereeIdentity(peerID: UUID(), publicKey: publicKey)
		}
	}

	@Test func testOldObjectSerializationAndDeserialization() throws {
		let myDict = ["a": "b"]
		archiveObjectInUserDefs(
			myDict as NSDictionary, forKey: UserDefaultsKeyTestDict)

		let unarchived: NSDictionary? = unarchiveObjectFromUserDefs(
			UserDefaultsKeyTestDict)

		let value = try #require(unarchived?.value(forKey: "a") as? String)

		#expect(myDict["a"] == value)
	}

	@Test func testOldObjectSerialization() throws {
		let myDict = ["a": "b"]

		let data = try NSKeyedArchiver.archivedData(
			withRootObject: myDict as NSDictionary,
			requiringSecureCoding: true)

		let unarchived: NSDictionary? = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: NSDictionary.self, from: data)

		let value = try #require(unarchived?.value(forKey: "a") as? String)

		#expect(myDict["a"] == value)
	}
}
