//
//  File.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

class DisplayName: NSObject, NSCoding {
	//possible parts of the displayed name
	private var lastname: HideableProperty<String>
	private var firstname: HideableProperty<String>
	private var nickname: HideableProperty<String>
	//shorten name parts if length of display name exceeds bluetooth handshake length
	private var shortenLastname: Bool = false //think about these two. Do we need them? Is it a good idea to shorten it or should be ask the user what to do?
	private var shortenFirstname: Bool = false //maybe like "your name exceeds 63 characters in length. It won't be fully visible to peers"
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeBool(lastname.hidden, forKey: "lastname" + ".hidden")
		if !lastname.hidden {
			aCoder.encodeObject(lastname.value, forKey: "lastname")
		}
		aCoder.encodeBool(firstname.hidden, forKey: "firstname" + ".hidden")
		if !firstname.hidden {
			aCoder.encodeObject(firstname.value, forKey: "firstname")
		}
		aCoder.encodeBool(nickname.hidden, forKey: "nickname" + ".hidden")
		if !nickname.hidden {
			aCoder.encodeObject(nickname.value, forKey: "nickname")
		}
		
		aCoder.encodeBool(shortenFirstname, forKey: "shortenFirstname")
		aCoder.encodeBool(shortenLastname, forKey: "shortenLastname")
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		var stringValue: String
		var hiddenValue: Bool
		
		hiddenValue = aDecoder.decodeBoolForKey("lastname" + ".hidden")
		if !hiddenValue {
			stringValue = aDecoder.decodeObjectForKey("lastname") as! String
		} else {
			stringValue = ""
		}
		lastname = HideableProperty(value: stringValue, hidden: hiddenValue)
		hiddenValue = aDecoder.decodeBoolForKey("firstname" + ".hidden")
		if !hiddenValue {
			stringValue = aDecoder.decodeObjectForKey("firstname") as! String
		} else {
			stringValue = ""
		}
		firstname = HideableProperty(value: stringValue, hidden: hiddenValue)
		hiddenValue = aDecoder.decodeBoolForKey("nickname" + ".hidden")
		if !hiddenValue {
			stringValue = aDecoder.decodeObjectForKey("nickname") as! String
		} else {
			stringValue = ""
		}
		nickname = HideableProperty(value: stringValue, hidden: hiddenValue)
		
		shortenFirstname = aDecoder.decodeBoolForKey("shortenFirstname")
		shortenLastname = aDecoder.decodeBoolForKey("shortenLastname")
	}
}