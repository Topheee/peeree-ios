//
//  UserDefaultsMock.swift
//  PeereeTests
//
//  Created by Christopher Kobusch on 22.04.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation

class UserDefaultsMock {
	static let standard = UserDefaultsMock()

	private var values = [String : Any]()

	func set(_ value: Any?, forKey defaultName: String) {
		if let value = value {
			values[defaultName] = value
		} else {
			values.removeValue(forKey: defaultName)
		}
	}

	func object(forKey defaultName: String) -> Any? {
		return values[defaultName]
	}
}
