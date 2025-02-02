//
//  SocialPersonAspect.swift
//  PeereeServer
//
//  Created by Christopher Kobusch on 16.01.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import Foundation

import PeereeCore

@MainActor
public protocol SocialPersonAspect: PersonAspect {

	var pinState: PinState { get set }
}
