//
//  PeerInfoTests.swift
//  PeereeTests
//
//  Created by Christopher Kobusch on 30.05.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import XCTest
import Peeree

class PeerInfoTests: XCTestCase {
	func testEncoding() throws {
		let peerInfo = PeerInfo(nickname: "The Hanger", gender: .male, age: nil, hasPicture: false)
		let encoder = JSONEncoder()
		let data = try encoder.encode(peerInfo)
		let decoder = JSONDecoder()
		let decodedPeerInfo = try decoder.decode(PeerInfo.self, from: data)
		XCTAssertEqual(peerInfo.age, decodedPeerInfo.age)
		XCTAssertEqual(peerInfo.gender, decodedPeerInfo.gender)
		XCTAssertEqual(peerInfo.hasPicture, decodedPeerInfo.hasPicture)
		XCTAssertEqual(peerInfo.lastChanged, decodedPeerInfo.lastChanged)
		XCTAssertEqual(peerInfo.nickname, decodedPeerInfo.nickname)
		XCTAssertEqual(peerInfo.version, decodedPeerInfo.version)
	}
}
