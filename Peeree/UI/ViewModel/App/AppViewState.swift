//
//  AppViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

final class AppViewState: ObservableObject {

	// MARK: Static Constants

	/// Global state object.
	static let shared = AppViewState()

	var isActive: Bool {
		return scenePhase == .active
	}

	var scenePhase: ScenePhase = .inactive
}
