//
//  RemotePeerManagerTests.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import XCTest

class RemotePeerManagerTests: XCTestCase {
	
	let rpm = RemotePeerManager.sharedManager

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
		LocalPeerManager.dropLocalPeerID()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
	
	func testGoOnline() {
		
		rpm.goOnline()
		/* without a local peer ID, we cannot go online */
		XCTAssertNil(rpm.btAdvertiser)
		XCTAssertNil(rpm.btBrowser)
		
		LocalPeerManager.setLocalPeerName("test")
		
		rpm.goOnline()
	}
	
	/**
	*	Tests whether RemotePeerManager.kDiscoveryServiceID is valid
	*	Test cases:
	*	- has the id the right length?
	*	- are only valid characters included?
	*/
	func testDiscoveryServiceID() {
		let toTest = RemotePeerManager.kDiscoveryServiceID
		let toTestLen = toTest.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
		XCTAssertFalse(toTestLen < 1 || toTestLen > 15, "service id must be 1–15 characters long")
		var buffer = [CChar](count: toTestLen, repeatedValue: 0)
		var hyphenBuf = [CChar](count: 2, repeatedValue: 0)
		toTest.getCString(&buffer, maxLength: toTestLen, encoding: NSUTF8StringEncoding)
		"-".getCString(&hyphenBuf, maxLength: 2, encoding: NSUTF8StringEncoding)
		var idx: Int
		//for character in buffer {
		//only go to toTestLen-1 to ommit trainling 0
		for idx = 0; idx < toTestLen-1; idx++ {
			let character = buffer[idx]
			let char32: Int32 = Int32(character)
			let test1 = isalnum(char32) != 0
			let test2 = character == hyphenBuf[0]
			let test = test1 || test2
			XCTAssertTrue(test, "only alphanumeric and hyphen characters are allowed in service ids")
		}
	}

}
