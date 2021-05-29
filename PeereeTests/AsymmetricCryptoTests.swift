//
//  AsymmetricCryptoTests.swift
//  PeereeTests
//
//  Created by Christopher Kobusch on 29.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import XCTest
import Peeree

class AsymmetricCryptoTests: XCTestCase {
	func testEncoding() throws {
		guard let privateTag = "privateTag".data(using: .utf8),
			  let publicTag = "publicTag".data(using: .utf8) else {
			XCTAssert(false)
			return
		}
		let keyPair = try KeyPair(label: "test", privateTag: privateTag, publicTag: publicTag, type: PeerInfo.KeyType, size: PeerInfo.KeySize, persistent: false)
		let encoder = JSONEncoder()
		let data = try encoder.encode(keyPair.publicKey)
		let decoder = JSONDecoder()
		let decodedPublicKey = try decoder.decode(AsymmetricPublicKey.self, from: data)
		XCTAssertEqual(try keyPair.publicKey.externalRepresentation(), try decodedPublicKey.externalRepresentation())
	}
}
