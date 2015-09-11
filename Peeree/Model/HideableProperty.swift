//
//  HideableProperty.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.07.15.
//  Copyright (c) 2015 Kobusch. All rights reserved.
//

import Foundation

struct HideableProperty<T> {
	var value: T
	var hidden: Bool
	
	init(value: T, hidden: Bool) {
		self.value = value
		self.hidden = hidden
	}
}