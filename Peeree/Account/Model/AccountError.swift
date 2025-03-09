//
//  AccountError.swift
//  Peeree
//
//  Created by Christopher Kobusch on 28.02.25.
//  Copyright © 2025 Kobusch. All rights reserved.
//


/// An `error` created by the account module.
enum AccountError: Error {

	/// Thrown when no server chat account exists yet.
	case noAccount

	/// Thrown when a server chat account already exists.
	case accountAlreadyExists

}
