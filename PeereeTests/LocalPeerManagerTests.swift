//
//  LocalPeerManagerTests.swift
//  Peeree
//
//  Created by Christopher Kobusch on 22.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import XCTest

import class Peeree.LocalPeerManager

/**
 *	Contains tests of the LocalPeerManager class.
 */
class LocalPeerManagerTests: XCTestCase {
	//copied from LocalPeerManager
	static private let kPrefPeerID = "kobusch-prefs-peerID"
	
	static private var peerData: NSData? = nil
	
	/**
	 *	Saves the user default preferences until the tests are finished.
	 */
	static override func setUp() {
		NSLog("%s\n", __FUNCTION__)
		//keep the preferences as they were
		let defs = NSUserDefaults.standardUserDefaults()
		peerData = defs.objectForKey(kPrefPeerID) as? NSData
		if let data = peerData {
			NSLog("\tretrieved %@ from preferences", data)
		}
	}
	
	/**
	 *	Restores the original user default preferences.
	 */
	static override func tearDown() {
		NSLog("%s\n", __FUNCTION__)
		if let data = peerData {
			let defs = NSUserDefaults.standardUserDefaults()
			defs.setObject(NSKeyedArchiver.archivedDataWithRootObject(data), forKey: kPrefPeerID)
			NSLog("\twrote %@ to preferences", data)
		}
	}
	
	/**
	 *	Clears the user default preferences.
	 */
    override func setUp() {
		super.setUp()
		NSUserDefaults.standardUserDefaults().removeObjectForKey(LocalPeerManagerTests.kPrefPeerID)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
	
	/**
	 *	Tests LocalPeerManager.setLocalPeer() and LocalPeerManager.getLocalPeer()
	 *	Test cases:
	 *	- is the local peer nil when the user defaults are empty?
	 *	- is the local peer not nil, when a valid name was set?
	 *	- is the display name of the peer the same as the formerly provided one?
	 */
    func testSetAndGetLocalPeer() {
		//local peer has to be nil here since we removed it in setUp()
		XCTAssertNil(LocalPeerManager.getLocalPeer(), "local peer has to be nil")
		
		LocalPeerManager.setLocalPeerName("testName")
		let testPeer = LocalPeerManager.getLocalPeer()
		
		XCTAssertNotNil(testPeer, "local peer ID was not created, though a name was specified")
		
		if let peer = testPeer {
			XCTAssertEqual("testName", peer.displayName, "display name was not correctly adopted")
		}
		
		var tooLongName = ""
		for i in 0...8 {
			//will make tooLongName 64 bytes long, which exceeds the maximum length of a peer display name
			tooLongName += "12345678"
		}
		//TODO XCTAssertThrows with tooLongName and "" as parameter for setLocalPeerName
    }
	
	/**
	 *	Tests whether LocalPeerManager.kDiscoveryServiceID is valid
	 *	Test cases:
	 *	- has the id the right length?
	 *	- are only valid characters included?
	 */
	func testDiscoveryServiceID() {
		let toTest = LocalPeerManager.kDiscoveryServiceID
		let toTestLen = count(toTest)
		XCTAssertFalse(toTestLen < 1 || toTestLen > 15, "service id must be 1–15 characters long")
		var buffer = [CChar](count: toTestLen, repeatedValue: 0)
		var hyphenBuf = [CChar](count: 2, repeatedValue: 0)
		toTest.getCString(&buffer, maxLength: toTestLen, encoding: NSASCIIStringEncoding)
		var blubb = "-".getCString(&hyphenBuf, maxLength: 2, encoding: NSASCIIStringEncoding)
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
