//
//  GenericFunctionsUI.swift
//  Peeree
//
//  Created by Christopher Kobusch on 04.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

/// Tries to create an `URL` from `urlString` and open it.
@MainActor
func open(urlString: String) {
	guard let url = URL(string: urlString) else { return }

	if #available(iOS 10.0, *) {
		UIApplication.shared.open(url)
	} else {
		UIApplication.shared.openURL(url)
	}
}
