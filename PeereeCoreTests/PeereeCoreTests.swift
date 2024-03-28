//
//  PeereeCoreTests.swift
//  PeereeCoreTests
//
//  Created by Christopher Kobusch on 01.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import XCTest
@testable import PeereeCore

final class PeereeCoreTests: XCTestCase {
	private let UserDefaultsKeyTestDict = "UserDefaultsKeyTestDict"

	func testMalformedPublicKey() throws {
		XCTAssertThrowsError(try PeereeIdentity(peerID: UUID(), publicKeyData: Data()))
	}

	func testOldObjectSerializationAndDeserialization() throws {
		let myDict = ["a" : "b"]
		archiveObjectInUserDefs(myDict as NSDictionary, forKey: UserDefaultsKeyTestDict)

		let unarchived: NSDictionary? = unarchiveObjectFromUserDefs(UserDefaultsKeyTestDict)

		guard let value = unarchived?.value(forKey: "a") as? String else {
			XCTAssert(false, "not a string")
			return
		}

		XCTAssertEqual(myDict["a"], value)
	}

	func testOldObjectSerializationAndNewDeserializationNSDictionary() throws {
		let myDict = ["a" : "b"]
		
		let data = NSKeyedArchiver.archivedData(withRootObject: myDict as NSDictionary)

		let unarchived: NSDictionary? = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: data)

		guard let value = unarchived?.value(forKey: "a") as? String else {
			XCTAssert(false, "not a string")
			return
		}

		XCTAssertEqual(myDict["a"], value)
	}

	func testOldObjectSerializationAndNewDeserializationDictionary() throws {
		let myDict = ["a" : "b"]

		let data = NSKeyedArchiver.archivedData(withRootObject: myDict)

		let unarchived: NSDictionary? = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: data)

		guard let value = unarchived?.value(forKey: "a") as? String else {
			XCTAssert(false, "not a string")
			return
		}

		XCTAssertEqual(myDict["a"], value)
	}

	func testOldSetSerialization() throws {
		let mySet = Set<String>(["a", "b"])

		let data = NSKeyedArchiver.archivedData(withRootObject: mySet)

		let unarchived: NSSet? = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: data)

		guard let decodedSet = unarchived as? Set<String> else {
			XCTAssert(false, "not a string set")
			return
		}

		XCTAssert(decodedSet.contains("a"))
		XCTAssert(decodedSet.contains("b"))
	}

	func testSetSerializationDeserialization() throws {
		let mySet = Set<String>(["a", "b"])

		let data = try NSKeyedArchiver.archivedData(withRootObject: mySet, requiringSecureCoding: true)

		let unarchived: NSSet? = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: data)

		guard let decodedSet = unarchived as? Set<String> else {
			XCTAssert(false, "not a string set")
			return
		}

		XCTAssert(decodedSet.contains("a"))
		XCTAssert(decodedSet.contains("b"))
	}

	func testSerializationsEqual() throws {
		let mySet = Set<String>(["a", "b"])

		let data = NSKeyedArchiver.archivedData(withRootObject: mySet as NSSet)
		let data2 = try NSKeyedArchiver.archivedData(withRootObject: mySet, requiringSecureCoding: true)

		XCTAssertEqual(data, data2)

		XCTAssertNoThrow(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: data))
	}
}
