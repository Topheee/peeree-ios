//
//  HapticController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 21.02.21.
//  Copyright © 2021 Kobusch. All rights reserved.
//

import Foundation
import CoreHaptics

/// use this class from main thread only!
@available(iOS 13.0, *)
class HapticController {
	private static var hapticEngine: CHHapticEngine? = nil
	
	private static func getHapticEngine() throws -> CHHapticEngine {
		if let engine = hapticEngine {
			return engine
		} else {
			let engine = try CHHapticEngine()
			try engine.start()
			hapticEngine = engine
			return engine
		}
	}
	
	/// plays the haptic feedback when pinning a person
	static func playHapticPin() {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

		do {
			let engine = try getHapticEngine()

			// The engine stopped; print out why
			engine.stoppedHandler = { reason in
				NSLog("INFO: The haptic engine stopped: \(reason.rawValue)")
			}

			// If something goes wrong, attempt to restart the engine immediately
			engine.resetHandler = {
				NSLog("ERROR: The haptic engine reset")

//				do {
//					try engine.start()
//				} catch {
//					print("Failed to restart the haptic engine: \(error)")
//				}
			}

			let anotherPattern = try CHHapticPattern(events: [
				CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient, parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.5)], relativeTime: 0.0, duration: 0.1),
				CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient, parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.9)], relativeTime: 0.3, duration: 0.3)], parameters: [])

			let player = try engine.makePlayer(with: anotherPattern)

			try player.start(atTime: 0)
		} catch let error {
			NSLog("ERROR: Haptic Engine Error: \(error). See CHHapticErrorCode for details.")
		}
	}
	
	/// plays the haptic feedback when pinning a person
	static func playHapticClick() {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

		do {
			let engine = try getHapticEngine()

			// The engine stopped; print out why
			engine.stoppedHandler = { reason in NSLog("INFO: The haptic engine stopped: \(reason.rawValue)") }

			// If something goes wrong, attempt to restart the engine immediately
			engine.resetHandler = { NSLog("ERROR: The haptic engine reset") }

			let anotherPattern = try CHHapticPattern(events: [
				CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient, parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.7)], relativeTime: 0.0, duration: 0.1)], parameters: [])

			let player = try engine.makePlayer(with: anotherPattern)

			try player.start(atTime: 0)
		} catch let error {
			NSLog("ERROR: Haptic Engine Error: \(error). See CHHapticErrorCode for details.")
		}
	}
}
