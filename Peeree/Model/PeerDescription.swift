//
//  PeerDescription.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

/*
This class represents all data a peer has specified.
It is also transmitted to other peers via network
*/
class PeerDescription: NSCoding {
	var displayName: DisplayName
	var characterTraits: [CharacterTrait] //maybe use an NSArray to enable archiving
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		//TODO
	}
	
	@objc required init(coder aDecoder: NSCoder) {
		//TODO
		displayName = DisplayName(coder: aDecoder)
		characterTraits = []
	}
}