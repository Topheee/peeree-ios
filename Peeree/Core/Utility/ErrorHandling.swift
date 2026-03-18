//
//  ErrorHandling.swift
//  Peeree
//
//  Created by Christopher Kobusch on 08.03.26.
//  Copyright © 2026 Kobusch. All rights reserved.
//

/** Who provoked the error and is thus able to fix it. */
public enum AudiencedErrorSource: Sendable {
	/**
	 The end user provoked an error, that they are able to fix.
	 The `message` is intended to be displayed, so should be localized.
	 */
	case user

	/**
	 The consumer of the library / module provoked an error, that they are
	 able to fix.
	 The error message should be studied by the programmer.

	 > Forwarding these errors to a crashlytics service is recommended.
	 */
	case consumer

	/**
	 An internal assumption has failed. The library vendor should be
	 contacted about this.

	 > Forwarding these errors to a crashlytics service is recommended.
	 */
	case vendor

	/**
	 Something that nobody has influence on provoked the error, typically I/O.
	 */
	case external
}

/** An error description based on its (presumed) perpetrator. */
public struct AudiencedError: Error {

	/** Who provoked the error and is thus able to fix it. */
	public let source: AudiencedErrorSource

	/** Gives a hint from where this error came. */
	public let domain: String

	/**
	 Should explain what caused this error. Should be localized for `.user`
	 and `.external` source.
	 */
	public let message: String

	/** Optional underlying error. */
	public let cause: Error?

	/** Message appropriate for displaying it to the user. */
	public var localizedDescription: String {
		self.message
	}

	/** Message appropriate for displaying it to the developer. */
	public var technicalReport: String {
		if let cause = self.cause as? AudiencedError {
			return "\(domain) \(source) \(message) - cause: \(cause.technicalReport)"
		} else if let cause = self.cause {
			return "\(domain) \(source) \(message) - cause: \(cause)"
		} else {
			return "\(domain) \(source) \(message)"
		}
	}

	/**
	 Create an ``AudiencedError`` with all necessary information.
	 */
	public init(
		source: AudiencedErrorSource, domain: String, message: String,
		cause: Error? = nil
	) {
		self.source = source
		self.domain = domain
		self.message = message
		self.cause = cause
	}
}

/// Creates an `NSError` with the main bundle's `bundleIdentifier` as `domain`.
public func createApplicationError(localizedDescription: String, code: Int = -1) -> Error {
	return NSError(domain: Bundle.main.bundleIdentifier ?? Bundle.main.bundlePath, code: code, userInfo: [NSLocalizedDescriptionKey : localizedDescription])
}

/// Creates an unrecoverable error describing the user of our function violated
/// a constraint that we explicitly documented.
public func makeConsumerError(
	_ description: String, in domain: String, cause: Error? = nil
) -> Error {
	return AudiencedError(
		source: .consumer, domain: domain, message: description)
}

/// Creates an unrecoverable error describing an unexpected error source.
public func makeExternalError(
	_ description: String, in domain: String, cause: Error? = nil
) -> Error {
	return AudiencedError(
		source: .external, domain: domain, message: description, cause: cause)
}

/// Creates an unrecoverable error describing a developer mistake.
public func makeFailedAssumptionError(
	_ description: String, in domain: String, cause: Error? = nil
) -> Error {
	return AudiencedError(
		source: .vendor, domain: domain, message: description, cause: cause)
}

/// Creates a possibly recoverable error describing a user mistake.
///
/// - Parameter localizedDescription Must be localized.
public func makeUserError(
	_ localizedDescription: String, in domain: String
) -> Error {
	return AudiencedError(
		source: .vendor, domain: domain, message: localizedDescription)
}

/// Creates an unrecoverable error describing an unexpected nil value.
public func makeUnexpectedNilError(in domain: String) -> Error {
	return AudiencedError(
		source: .vendor, domain: domain,
		message: "Found unexpected nil object at \(Thread.callStackSymbols.joined(separator: " < "))")
}

/// Creates an unrecoverable error describing an issue with string encoding.
public func makeEncodingError(
	in domain: String, encoding: String.Encoding = .utf8
) -> Error {
	return AudiencedError(
		source: .vendor, domain: domain,
		message: "Could not (de-)serialize string with encoding \(encoding) at \(Thread.callStackSymbols.joined(separator: " < "))")
}

/// Creates an `Error` based on the value of `errno`.
public func createSystemError() -> Error? {
	let code = errno
	guard let errorCString = strerror(code), let errorString = String(utf8String: errorCString) else { return nil }

	return createApplicationError(localizedDescription: errorString, code: Int(code))
}

/// Retrieves the error message describing `status`.
public func errorMessage(describing status: OSStatus) -> String {
	let fallbackMessage = "OSStatus \(status)"
	let msg: String
	#if os(OSX)
		msg = "\(SecCopyErrorMessageString(status, nil) ?? fallbackMessage as CFString)"
	#else
		if #available(iOS 11.3, *) {
			msg = "\(SecCopyErrorMessageString(status, nil) ?? fallbackMessage as CFString)"
		} else {
			perror(nil)
			msg = fallbackMessage
		}
	#endif
	return msg
}
