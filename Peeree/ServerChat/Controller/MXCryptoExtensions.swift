//
//  MXCryptoExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 25.11.22.
//  Copyright © 2022 Kobusch. All rights reserved.
//

import Foundation
import MatrixSDK

extension MXCrypto {
	/// Trusts all devices in the given map.
	func trustAll(devices: MXUsersDevicesMap<MXDeviceInfo>, _ completion: @escaping (Error?) -> Void) {
		var usersAndDevices = [(String, String)]()
		for userId in devices.userIds() {
			for deviceId in devices.deviceIds(forUser: userId) {
				usersAndDevices.append((userId, deviceId))
			}
		}

		trustAll(devicesForUsers: usersAndDevices, completion)
	}

	/// Trusts all devices in the given map.
	fileprivate func trustAll(devicesForUsers: [(String, String)], index: Int = 0, _ completion: @escaping (Error?) -> Void) {
		guard index < devicesForUsers.count else {
			completion(nil)
			return
		}

		let (userId, deviceId) = devicesForUsers[index]

		self.setDeviceVerification(.verified, forDevice: deviceId, ofUser: userId) {
			self.trustAll(devicesForUsers: devicesForUsers, index: index + 1, completion)
		} failure: { deviceVerificationError in
			completion(deviceVerificationError)
		}
	}
}
