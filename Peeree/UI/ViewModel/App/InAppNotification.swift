//
//  InAppNotification.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

struct InAppNotification: Error, Identifiable {
	enum Severity {
		case info, warning, error
	}

	let id = UUID()

	let localizedTitle: String
	let localizedMessage: String

	let severity: Severity

	let furtherDescription: String?
}
