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
	func testMalformedPublicKey() throws {
		XCTAssertThrowsError(try PeereeIdentity(peerID: UUID(), publicKeyData: Data()))
	}
}
