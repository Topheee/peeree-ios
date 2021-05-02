//
//  BrowseFilterSettingsTests.swift
//  PeereeTests
//
//  Created by Christopher Kobusch on 22.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import XCTest

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
		let filter = BrowseFilterSettings.shared
		filter.ageMin = 42
		filter.ageMax = 42
		filter.gender = .male
		filter.onlyWithAge = true
		filter.onlyWithPicture = true
		if #available(iOS 11.0, *) {
			let archiver = NSKeyedArchiver(requiringSecureCoding: true)
			filter.encode(with: archiver)
			let data = archiver.encodedData
			let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
			let decodedFilter = BrowseFilterSettings(coder: unarchiver)
			XCTAssertNotNil(decodedFilter)
			XCTAssertEqual(filter.ageMin, decodedFilter!.ageMin)
			XCTAssertEqual(filter.ageMax, decodedFilter!.ageMax)
			XCTAssertEqual(filter.gender, decodedFilter!.gender)
			XCTAssertEqual(filter.onlyWithAge, decodedFilter!.onlyWithAge)
			XCTAssertEqual(filter.onlyWithPicture, decodedFilter!.onlyWithPicture)
		} else {
			// Fallback on earlier versions
		}
	}

	func testPerformanceExample() throws {
		// This is an example of a performance test case.
		self.measure {
			// Put the code you want to measure the time of here.
		}
	}

}
