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
	//shorten name parts if length of display name exceeds bluetooth handshake length
	private var shortenLastname: Bool = false //think about these two. Do we need them? Is it a good idea to shorten it or should be ask the user what to do?
	private var shortenFirstname: Bool = false //maybe like "your name exceeds 63 characters in length. It won't be fully visible to peers"
	
	@objc func encode(with aCoder: NSCoder) {
		aCoder.encode(lastname.hidden, forKey: "lastname" + ".hidden")
		if !lastname.hidden {
			aCoder.encode(lastname.value, forKey: "lastname")
		}
		aCoder.encode(firstname.hidden, forKey: "firstname" + ".hidden")
		if !firstname.hidden {
			aCoder.encode(firstname.value, forKey: "firstname")
		}
		
		aCoder.encode(shortenFirstname, forKey: "shortenFirstname")
		aCoder.encode(shortenLastname, forKey: "shortenLastname")
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		var stringValue: String
		var hiddenValue: Bool
		
		hiddenValue = aDecoder.decodeBool(forKey: "lastname" + ".hidden")
		if !hiddenValue {
			stringValue = aDecoder.decodeObject(forKey: "lastname") as! String
		} else {
			stringValue = ""
		}
		lastname = HideableProperty(value: stringValue, hidden: hiddenValue)
		hiddenValue = aDecoder.decodeBool(forKey: "firstname" + ".hidden")
		if !hiddenValue {
			stringValue = aDecoder.decodeObject(forKey: "firstname") as! String
		} else {
			stringValue = ""
		}
		firstname = HideableProperty(value: stringValue, hidden: hiddenValue)
		
		shortenFirstname = aDecoder.decodeBool(forKey: "shortenFirstname")
		shortenLastname = aDecoder.decodeBool(forKey: "shortenLastname")
	}
}
