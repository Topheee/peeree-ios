//
//  AppViewState.swift
//  Peeree
//
//  Created by Christopher Kobusch on 24.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

/// State of the whole application.
final class AppViewState: ObservableObject {

	// MARK: Variables

	/// Whether the application is in front.
	var isActive: Bool {
		return scenePhase == .active
	}

	/// An indication of a scene’s operational state.
	var scenePhase: ScenePhase = .inactive
}
