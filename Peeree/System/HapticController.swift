//
//  HapticController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.02.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation
import CoreHaptics
import PeereeCore

/// use this class from main thread only!
@available(iOS 13.0, *)
actor HapticController {
	static let shared = HapticController()

	// Log tag.
	private static let LogTag = "HapticController"

	private var hapticEngine: CHHapticEngine? = nil

	private func getHapticEngine() async throws -> CHHapticEngine {
		if let engine = self.hapticEngine {
			return engine
		} else {
			let engine = try CHHapticEngine()
			engine.isAutoShutdownEnabled = false
			engine.stoppedHandler = { reason in
				ilog(Self.LogTag, "The haptic engine stopped: \(reason.rawValue)")
				self.hapticEngine = nil
			}
			engine.resetHandler = { wlog(Self.LogTag, "The haptic engine reset.") }
			engine.notifyWhenPlayersFinished { (error) -> CHHapticEngine.FinishedAction in
				if let error {
					elog(Self.LogTag, "Haptic player finished with error: \(error.localizedDescription)")
				}
				return .stopEngine
			}

			try await engine.start()

			self.hapticEngine = engine
			return engine
		}
	}
	
	/// plays the haptic feedback when pinning a person
	func playHapticPin() async {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

		do {
			let engine = try await getHapticEngine()

			let anotherPattern = try CHHapticPattern(events: [
				CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient,
							  parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.5)],
							  relativeTime: 0.0, duration: 0.1),
				CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient,
							  parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.9)],
							  relativeTime: 0.3, duration: 0.3)], parameters: [])

			let player = try engine.makePlayer(with: anotherPattern)

			try player.start(atTime: 0)
		} catch let error {
			elog(Self.LogTag, "Haptic Engine Error: \(error). See CHHapticErrorCode for details.")
		}
	}
	
	/// plays the haptic feedback when pinning a person
	func playHapticClick() async {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

		do {
			let engine = try await getHapticEngine()

			let anotherPattern = try CHHapticPattern(events: [
				CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient,
							  parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.7)],
							  relativeTime: 0.0, duration: 0.1)], parameters: [])

			let player = try engine.makePlayer(with: anotherPattern)

			try player.start(atTime: 0)
		} catch let error {
			elog(Self.LogTag, "Haptic Engine Error: \(error). See CHHapticErrorCode for details.")
		}
	}
}
