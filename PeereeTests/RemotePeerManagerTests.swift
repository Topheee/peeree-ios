//
//  RemotePeerManagerTests.swift
//  Peeree
//
//  Created by Christopher Kobusch on 13.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import XCTest

import class Peeree.LocalPeerManager
import class Peeree.RemotePeerManager

class RemotePeerManagerTests: XCTestCase {
	
	static let rpm = RemotePeerManager.sharedManager

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

}
