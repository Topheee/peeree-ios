//
//  BrowseFilterSettingsTests.swift
//  PeereeTests
//
//  Created by Christopher Kobusch on 22.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import XCTest
@testable import Peeree

class BrowseFilterSettingsTests: XCTestCase {

	override func setUpWithError() throws {
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}

	override func tearDownWithError() throws {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
	}

	func testEncoding() throws {
		// This is an example of a functional test case.
		// Use XCTAssert and related functions to verify your tests produce the correct results.
		let filter = BrowseFilter(ageMin: 42, ageMax: 42, gender: [.males], onlyWithAge: true, onlyWithPicture: true)

		let encoder = JSONEncoder()
		let data = try encoder.encode(filter)

		let decoder = JSONDecoder()
		let decodedFilter = try decoder.decode(BrowseFilter.self, from: data)

		XCTAssertNotNil(decodedFilter)
		XCTAssertEqual(filter.ageMin, decodedFilter.ageMin)
		XCTAssertEqual(filter.ageMax, decodedFilter.ageMax)
		XCTAssertEqual(filter.gender, decodedFilter.gender)
		XCTAssertEqual(filter.onlyWithAge, decodedFilter.onlyWithAge)
		XCTAssertEqual(filter.onlyWithPicture, decodedFilter.onlyWithPicture)
	}

	func testPerformanceExample() throws {
		// This is an example of a performance test case.
		self.measure {
			// Put the code you want to measure the time of here.
		}
	}

}
