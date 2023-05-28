//
//  PeereeServerAPITests.swift
//  PeereeServerAPITests
//
//  Created by Christopher Kobusch on 14.05.23.
//  Copyright © 2023 Kobusch. All rights reserved.
//

import XCTest
import PeereeCore
@testable import PeereeServerAPI
import KeychainWrapper

final class IdentityProvider: SecurityDataSource {
	let peerID: PeerID

	let keyPair: KeyPair

	init(peerID: PeerID, keyPair: KeyPair) {
		self.peerID = peerID
		self.keyPair = keyPair
	}

	func getSignature() -> String {
		do {
			return try computeSignature()
		} catch let error {
			NSLog("Cannot compute signature: \(error)")
			return ""
		}
	}

	func getPeerID() -> String {
		return peerID.uuidString
	}

	/// The number added to the current sequence number after each server chat operation.
	private static let SequenceNumberIncrement: Int32 = 13

	var sequenceNumber: Int32 = 0

	/// Computes a digital signature based on the current `sequenceNumber` and increments the `sequenceNumber` afterwards.
	private func computeSignature() throws -> String {
		guard let sequenceNumberData = String(sequenceNumber).data(using: .utf8) else {
			throw NSError(domain: "Peeree", code: -2, userInfo: nil)
		}

		sequenceNumber = sequenceNumber.addingReportingOverflow(IdentityProvider.SequenceNumberIncrement).partialValue
		return try keyPair.sign(message: sequenceNumberData).base64EncodedString()
	}
}

/// Used during account creation.
private struct InitialSecurityDataSource: SecurityDataSource {
	/// Base64-encoded binary representation of the public key part of a `PeereeIdentity`.
	let base64PublicKey: String

	public func getPeerID() -> String { return "" }

	public func getSignature() -> String { return base64PublicKey }
}

/// Tests the PeereeServerAPI module.
final class PeereeServerAPITests: XCTestCase {

	/// The number added to the current sequence number after each server chat operation.
	private static let PrivateTag = "PeereeServerAPITests.Identity.Private".data(using: .utf8, allowLossyConversion: true)!

	/// The number added to the current sequence number after each server chat operation.
	private static let PublicTag = "PeereeServerAPITests.Identity.Public".data(using: .utf8, allowLossyConversion: true)!

	/// The PeerID of the test account in the local database. See `testCreateTestAccount()` on how to obtain this.
	private let peerID = PeerID(uuidString: "DC20BF4B-02BF-4146-A84E-F6D740DBCFDF")!

	/// The key pair of the test account; initialized in `setUp()`.
	private var keyPair: KeyPair!

	/// Run this once on the very first test run to create a test account!
	/// Comment out the line `keyPair = try KeyPair...` in `setUp()` to run this test.
/*	func testCreateTestAccount() throws {
		let expectation = XCTestExpectation(description: "Create a test account.")

		keyPair = try KeyPair(privateTag: PeereeServerAPITests.PrivateTag, publicTag: PeereeServerAPITests.PublicTag, algorithm: .ec, size: PeereeIdentity.KeySize, persistent: true)

		SwaggerClientAPI.dataSource = InitialSecurityDataSource(base64PublicKey: try keyPair.externalPublicKey().base64EncodedString())
		AccountAPI.putAccount { data, error in
			NSLog("Generated test account. Change the peerID variable of this test to the following value: \(data?.peerID.uuidString ?? "\(error?.localizedDescription ?? "FAILED")").")
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}*/

	override func setUp() {
		SwaggerClientAPI.host = "localhost:10443"
		SwaggerClientAPI.unsafeTLS = true
		keyPair = try! KeyPair(fromKeychainWithPrivateTag: PeereeServerAPITests.PrivateTag, publicTag: PeereeServerAPITests.PublicTag, algorithm: .ec, size: PeereeIdentity.KeySize)
		let ip = IdentityProvider(peerID: peerID, keyPair: keyPair)
		SwaggerClientAPI.dataSource = ip

		let semaphore = DispatchSemaphore(value: 0)

		AuthenticationAPI.deleteAccountSecuritySequenceNumber { data, error in
			ip.sequenceNumber = data ?? 0
			semaphore.signal()
		}

		// This is so stupid, but there seems to be no other way
		// https://stackoverflow.com/questions/67943181/how-can-i-wait-for-an-async-function-from-synchronous-function-in-swift-5-5
		switch semaphore.wait(timeout: DispatchTime.now().advanced(by: .seconds(10))) {
		case .success:
			// do nothing
			break
		case .timedOut:
			exit(1)
		}
	}

	func testIdentityCreationAndDeletion() throws {
		let keyPair = try KeyPair(privateTag: "asdfasdfasdf1".data(prefixedEncoding: .utf8)!, publicTag: "asdfasdfasdfasdfasdf1".data(prefixedEncoding: .utf8)!, algorithm: .ec, size: PeereeIdentity.KeySize, persistent: false)

		SwaggerClientAPI.dataSource = InitialSecurityDataSource(base64PublicKey: try keyPair.externalPublicKey().base64EncodedString())
		let expectation = XCTestExpectation(description: "Create an account.")
		AccountAPI.putAccount { data, error in
			XCTAssertNil(error, "Expected no errors during account creation.")
			XCTAssertNotNil(data, "Expected account data during account creation.")

			guard let data else { return }

			let ip = IdentityProvider(peerID: data.peerID, keyPair: keyPair)
			ip.sequenceNumber = data.sequenceNumber
			SwaggerClientAPI.dataSource = ip

			AccountAPI.deleteAccount { _, deleteAccountError in
				XCTAssertNil(deleteAccountError, "Expected no errors during account deletion.")
				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 5.0)
	}

	func testGetPins() throws {
		let expectation = XCTestExpectation(description: "Get pins.")
		PinsAPI.getAccountPins { data, error in
			XCTAssertNil(error, "Expected no errors during pin list retrieval.")
			XCTAssertNotNil(data, "Expected pin list data during pin list retrieval.")

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}

	func testDownloadPortraitHashes() throws {
		let expectation = XCTestExpectation(description: "Get portrait hashes.")

		ContentfilterAPI.getContentFilterPortraitHashes { data, error in
			XCTAssertNil(error, "Expected no errors during portrait hashes retrieval.")
			XCTAssertNotNil(data, "Expected hash list data during portrait hashes retrieval.")

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}

	func testDownloadLastPortraitHashes() throws {
		let expectation = XCTestExpectation(description: "Get portrait hashes.")

		ContentfilterAPI.getContentFilterPortraitHashes(startDate: Date(timeIntervalSinceNow: -20)) { data, error in
			XCTAssertNil(error, "Expected no errors during portrait hashes retrieval.")
			XCTAssertNotNil(data, "Expected hash list data during portrait hashes retrieval.")

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}

	func testUploadPortraitHash() throws {
		let expectation = XCTestExpectation(description: "Upload portrait hashes.")

		// This PeerID must be present in the test database.
		let reportedPeerID = PeerID(uuidString: "8c9ff980-a891-4621-a0fe-a60bd9628e2b") ?? PeerID()
		let fakeImage = Data(repeating: 42, count: 42)
		let fakeHash = fakeImage.sha256().hexString()

		ContentfilterAPI.putContentFilterPortraitReport(body: fakeImage, reportedPeerID: reportedPeerID, hash: fakeHash) { data, error in
			XCTAssertNil(error, "Expected no errors during portrait hash upload.")
			XCTAssertNotNil(data, "Expected hash list data during portrait hash upload.")

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}
/*
	func testRefuseUploadOwnPortraitHash() throws {
		let expectation = XCTestExpectation(description: "Upload portrait hashes.")

		let fakeImage = Data(repeating: 42, count: 42)
		let fakeHash = fakeImage.sha256().hexString()

		ContentfilterAPI.putContentFilterPortraitReport(body: fakeImage, reportedPeerID: peerID, hash: fakeHash) { data, error in
			XCTAssertNotNil(error, "Expected errors when uploading portrait hashes of own account.")
			XCTAssertNil(data, "Expected no when uploading portrait hashes of own account.")

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}
*/
	func testPin() throws {
		let expectation = XCTestExpectation(description: "Pin and unpin.")

		// This PeerID must be present in the test database.
		let pinnedPeerID = PeerID(uuidString: "e7d0b00b-7c16-4ce6-9b45-eec06db2212a") ?? PeerID()
		let pinnedPublicKey = Data(hexString: "04ef3405a3235c3a6fa0d42edf7cf7535320d9e9be0ba8b9bda000070e7fe3af7c89dc2ebe8ea83a0906a7a9eec1fdeaecb2356c048bc5cd4dd3b2956d2203e4ef") ?? Data()

		PinsAPI.putPin(pinnedID: pinnedPeerID, pinnedKey: pinnedPublicKey.base64EncodedData()) { data, error in
			XCTAssertNil(error, "Expected no errors during pinning.")
			XCTAssertNotNil(data, "Expected hash list data during pinning.")

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}

	func testPinAndUnpin() throws {
		let expectation = XCTestExpectation(description: "Pin and unpin.")

		// This PeerID must be present in the test database.
		let pinnedPeerID = PeerID(uuidString: "8c9ff980-a891-4621-a0fe-a60bd9628e2b") ?? PeerID()
		let pinnedPublicKey = Data(hexString: "04b676bb108b475350f2f22fe6c09cd2c6fcc10d933724251a5e9a980bdff61239332c895429ded5a561d4943db53374c0871157ee9d222c19ef653f2d8f386df1") ?? Data()

		PinsAPI.putPin(pinnedID: pinnedPeerID, pinnedKey: pinnedPublicKey.base64EncodedData()) { data, error in
			XCTAssertNil(error, "Expected no errors during pinning.")
			XCTAssertNotNil(data, "Expected bool data during pinning.")

			guard data != nil && error == nil else { return }

			PinsAPI.deletePin(pinnedID: pinnedPeerID) { data, error in
				XCTAssertNil(error, "Expected no errors during unpinning.")

				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 5.0)
	}
}
