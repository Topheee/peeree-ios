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
	private static var hapticsQueue = DispatchQueue(label: "de.peeree.haptics", qos: .utility)
	private static var hapticEngine: CHHapticEngine? = nil
	
	private static func withHapticEngine(completion: @escaping (Result<CHHapticEngine, Error>) -> Void) {
		hapticsQueue.async {
			let result = Result { () -> CHHapticEngine in
				if let engine = hapticEngine {
					return engine
				} else {
					let engine = try CHHapticEngine()
					engine.isAutoShutdownEnabled = true
					engine.stoppedHandler = { reason in
						ilog("The haptic engine stopped: \(reason.rawValue)")
						HapticController.hapticEngine = nil
					}
					engine.resetHandler = { wlog("The haptic engine reset.") }
					engine.notifyWhenPlayersFinished { (_error) -> CHHapticEngine.FinishedAction in
						if let error = _error {
							elog("Haptic player finished with error: \(error.localizedDescription)")
						}
						return .stopEngine
					}
					try engine.start()
					hapticEngine = engine
					return engine
				}
			}
			completion(result)
		}
	}
	
	/// plays the haptic feedback when pinning a person
	static func playHapticPin() {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

		HapticController.withHapticEngine { result in
			do {
				let engine = try result.get()

				let anotherPattern = try CHHapticPattern(events: [
					CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient, parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.5)], relativeTime: 0.0, duration: 0.1),
					CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient, parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.9)], relativeTime: 0.3, duration: 0.3)], parameters: [])

				let player = try engine.makePlayer(with: anotherPattern)

				try player.start(atTime: 0)
			} catch let error {
				elog("Haptic Engine Error: \(error). See CHHapticErrorCode for details.")
			}
		}
	}
	
	/// plays the haptic feedback when pinning a person
	static func playHapticClick() {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

		HapticController.withHapticEngine { result in
			do {
				let engine = try result.get()

				let anotherPattern = try CHHapticPattern(events: [
					CHHapticEvent(eventType: CHHapticEvent.EventType.hapticTransient, parameters: [CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: 0.7)], relativeTime: 0.0, duration: 0.1)], parameters: [])

				let player = try engine.makePlayer(with: anotherPattern)

				try player.start(atTime: 0)
			} catch let error {
				elog("Haptic Engine Error: \(error). See CHHapticErrorCode for details.")
			}
		}
	}
}
