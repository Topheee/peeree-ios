//
//  PeerDescription.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import UIKit.UIImage

/*
 *	This class is used to store remote peers locally. It provides an interface to load the picture of the remote peer lazily.
 */
class LocalPeerDescription: NetworkPeerDescription {
	private static let pictureKey = "local-peer-picture"
	
	var _picture: UIImage?
	var picture: UIImage? {
		return _picture
	}
	
	var _isPictureLoading = false
	var isPictureLoading: Bool {
		return _isPictureLoading
	}
	
	// is only set to true, if a pin match happend
	var pinnedMe = false
	
	func loadPicture() {
		if hasPicture && !_isPictureLoading {
			_isPictureLoading = true
			//TODO load picture
		}
	}
	
	@objc override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		//TODO
		if picture != nil {
			aCoder.encodeObject(picture, forKey: LocalPeerDescription.pictureKey)
		}
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		//TODO
		if aDecoder.containsValueForKey(LocalPeerDescription.pictureKey) {
			_picture = aDecoder.decodeObjectOfClass(UIImage.self, forKey: LocalPeerDescription.pictureKey)!as UIImage
		}
	}

	@objc required init() {
	    super.init()
	}
}

/*
 *	This class encapsulates all data a peer has specified, except of his or her picture.
 *	It is transmitted to other peers when the peers connect, to allow filtering. In result, the primary goal is to keep the binary representation of this class as small as possible.
 */
class NetworkPeerDescription: NSSecureCoding {
	private static let firstnameKey = "firstname"
	private static let lastnameKey = "lastname"
	private static let traitsKey = "characterTraits"
	
	var firstname, lastname: String
	var displayName: String? {
		get {
			let ret = firstname + lastname
			if ret.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 63 {
				// TODO substring of 60 bytes length plus "..." string
			}
			return ret
		}
	}
	var peerID = MCPeerID()
	var hasPicture = false
	var hasVagina = false
	var age = 18
	static let possibleStatuses = ["no comment", "married", "divorced", "going to be divorced", "in a relationship", "single"]
	var status = 0
	var characterTraits: [CharacterTrait]
	/*
	 *	Version information with the same format as Apple's dylib version format. This is used to test the compatibility of two Peeree apps exchanging data via bluetooth.
	 */
	var version = "1.0"
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		// TODO empty stub
	}
	
	@objc required init() {
		// TODO empty stub
		firstname = "Christopher"
		lastname = "Kobusch"
		characterTraits = CharacterTrait.standardTraits()
		peerID = MCPeerID(displayName: displayName!)
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		firstname = aDecoder.decodeObjectOfClass(NSString.self, forKey: NetworkPeerDescription.firstnameKey) as! String
		lastname = aDecoder.decodeObjectOfClass(NSString.self, forKey: NetworkPeerDescription.lastnameKey) as! String
		characterTraits = aDecoder.decodeObjectOfClass(NSArray.self, forKey: NetworkPeerDescription.traitsKey) as! [CharacterTrait]
		// TODO decode the rest of the properties
	}
}