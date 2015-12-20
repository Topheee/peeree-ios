//
//  LocalPeerManagerTests.swift
//  Peeree
//
//  Created by Christopher Kobusch on 22.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import UIKit
import MultipeerConnectivity
import XCTest

/**
 *	Contains tests of the LocalPeerManager class.
 */
class LocalPeerManagerTests: XCTestCase {
	//copied from LocalPeerManager
	//static private let kPrefPeerID = "kobusch-prefs-peerID"
	
	static private var peerData: MCPeerID? = nil
	
	/**
	 *	Saves the user default preferences until the tests are finished.
	 */
	static override func setUp() {
		NSLog("%s\n", __FUNCTION__)
		//keep the preferences as they were
		peerData = LocalPeerManager.getLocalPeerID()
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
			LocalPeerManager.setLocalPeerName(data.displayName)
			NSLog("\twrote %@ to preferences", data)
			if !data.isEqual(LocalPeerManager.getLocalPeerID()) {
				NSLog("\tthe peer ID changes, even if you create one with the same display name")
			}
		}
	}
	
	/**
	 *	Clears the user default preferences.
	 */
    override func setUp() {
		super.setUp()
		LocalPeerManager.dropLocalPeerID()
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
		XCTAssertNil(LocalPeerManager.getLocalPeerID(), "local peer has to be nil")
		
		LocalPeerManager.setLocalPeerName("testName")
		let testPeer = LocalPeerManager.getLocalPeerID()
		
		XCTAssertNotNil(testPeer, "local peer ID was not created, though a name was specified")
		
		if let peer = testPeer {
			XCTAssertEqual("testName", peer.displayName, "display name was not correctly adopted")
		}
		
		var tooLongName = ""
		for _ in 0...8 {
			//will make tooLongName 64 bytes long, which exceeds the maximum length of a peer display name
			tooLongName += "12345678"
		}
		//TODO XCTAssertThrows with tooLongName and "" as parameter for setLocalPeerName
    }

}
