//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

/// Log tag.
private let LogTag = "GenericFunctions"

// MARK: - Functions

/// Archive an Objective-C object in `UserDefaults`.
public func archiveObjectInUserDefs<T: NSSecureCoding>(_ object: T, forKey: String) {
	#if TESTING
	PeereeTests.UserDefaultsMock.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
	#else
	if #available(iOS 12.0, *) {
		do {
			UserDefaults.standard.set(try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true), forKey: forKey)
		} catch {
			flog(LogTag, error.localizedDescription)
		}
	} else {
		UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
	}
	#endif
}

/// Unarchive an Objective-C object in `UserDefaults`.
public func unarchiveObjectFromUserDefs<T: NSObject & NSSecureCoding>(_ forKey: String, containing classes: [AnyClass] = []) -> T? {
	#if TESTING
	guard let data = UserDefaultsMock.standard.object(forKey: forKey) as? Data else { return nil }
	#else
	guard let data = UserDefaults.standard.object(forKey: forKey) as? Data else { return nil }
	#endif

	if #available(iOS 12.0, *) {
		do {
			if classes.count > 0 {
				return try NSKeyedUnarchiver.unarchivedObject(ofClasses: [T.self] + classes, from: data) as? T
			} else {
				return try NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
			}
		} catch {
			flog(LogTag, error.localizedDescription)
			return nil
		}
	} else {
		return NSKeyedUnarchiver.unarchiveObject(with: data) as? T
	}
}

/// Encode `object` and put the resulting encoded `Data` value into `UserDefaults`.
public func archiveInUserDefs<T: Encodable>(_ object: T, forKey: String) throws {
	#if TESTING
	PeereeTests.UserDefaultsMock.standard.set(PropertyListEncoder().encode(object), forKey: forKey)
	#else
	UserDefaults.standard.set(try PropertyListEncoder().encode(object), forKey: forKey)
	#endif
}

/// Read `Data` from `UserDefaults`, decode it and return it.
public func unarchiveFromUserDefs<T: Decodable>(_ type: T.Type, _ forKey: String) throws -> T? {
	#if TESTING
	guard let data = UserDefaultsMock.standard.object(forKey: forKey) as? Data else { return nil }
	#else
	guard let data = UserDefaults.standard.object(forKey: forKey) as? Data else { return nil }
	#endif

	return try PropertyListDecoder().decode(type, from: data)
}

/// create a plist and add it to copied resources. In the file, make the root entry to an array and add string values to it
public func arrayFromBundle(name: String) -> [String]? {
	guard let url = Bundle.main.url(forResource: name, withExtension:"plist") else { return nil }
	return NSArray(contentsOf: url) as? [String]
}

/// Creates an `NSError` with the main bundle's `bundleIdentifier` as `domain`.
public func createApplicationError(localizedDescription: String, code: Int = -1) -> Error {
	return NSError(domain: Bundle.main.bundleIdentifier ?? Bundle.main.bundlePath, code: code, userInfo: [NSLocalizedDescriptionKey : localizedDescription])
}

/// Always throws an error; use in situations where there must be a developer mistake.
public func programmingError(_ description: String,
							 code: Int = -1) throws -> Never {
	throw NSError(
		domain: Bundle.main.bundleIdentifier ?? Bundle.main.bundlePath,
		code: code,
		userInfo: [NSLocalizedDescriptionKey : description])
}

/// Creates an unrecoverable error describing an unexpected nil value.
public func unexpectedNilError() -> Error {
	return createApplicationError(localizedDescription: "Found unexpected nil object", code: -1)
}

/// Creates an unrecoverable error describing an unexpected enum value.
public func unexpectedEnumValueError() -> Error {
	return createApplicationError(localizedDescription: "Found unexpected enumeration case", code: -1)
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

/// Throwing wrapper around `SecRandomCopyBytes(_:_:_:)`.
public func generateRandomData(length: Int) throws -> Data {
	var nonce = Data(count: length)
	let status = nonce.withUnsafeMutablePointer({ SecRandomCopyBytes(kSecRandomDefault, length, $0) })
	if status == errSecSuccess {
		return nonce
	} else {
		throw makeOSStatusError(from: status)
	}
}

/// Converts an `OSStatus` returned by a security function to an `Error`.
public func makeOSStatusError(from status: OSStatus) -> Error {
	return NSError(domain: kCFErrorDomainOSStatus as String, code: Int(status), userInfo: [NSLocalizedDescriptionKey : errorMessage(describing: status)])
}

/// Objective-C __bridge cast
public func bridge<T : AnyObject>(obj : T) -> UnsafeRawPointer {
	return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

/// Objective-C __bridge cast
public func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
	return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

/// Objective-C __bridge_retained equivalent. Casts the object pointer to a void pointer and retains the object.
public func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
	return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
}

/// Objective-C __bridge_transfer equivalent. Converts the void pointer back to an object pointer and consumes the retain.
public func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
	return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
}

extension FileManager {
	/// Purges a file from disk if it exists.
	public func deleteFile(at url: URL) throws {
		if self.fileExists(atPath: url.path) {
			try self.removeItem(at: url)
		}
	}
}


// MARK: - Extensions

extension Result where Failure: Error {
	/// Returns the encapsulated `Failure` error, if any.
	// I'd very much like to name this simply `error`, but MatrixSDK has a similar extension (which is worse than mine).
	public var mError: Failure? {
		switch self {
		case .failure(let error):
			return error
		case .success(_):
			return nil
		}
	}

	/// Returns the encapsulated `Success` value, if any.
	// I'd very much like to name this simply `value`, but MatrixSDK has a similar extension (which is worse than mine).
	public var mValue: Success? {
		switch self {
		case .failure(_):
			return nil
		case .success(let value):
			return value
		}
	}
}

extension CGRect {
	public var center: CGPoint {
		return CGPoint(x: midX, y: midY)
	}
	
	public init(squareEdgeLength: CGFloat) {
		self.init(x: 0.0, y: 0.0, width: squareEdgeLength, height: squareEdgeLength)
	}
}

extension CGSize {
	public init(squareEdgeLength: CGFloat) {
		self.init(width: squareEdgeLength, height: squareEdgeLength)
	}
}

extension RawRepresentable where Self.RawValue == String {
	public var localizedRawValue: String {
		return Bundle.main.localizedString(forKey: rawValue, value: nil, table: nil)
	}
}

extension Notification.Name {
	/// Posts a new notification to the `default` `NotificationCenter`.
	public func post(on object: (any AnyObject & Sendable)? = nil,
					 userInfo: [AnyHashable : Any]? = nil) {
		NotificationCenter.`default`.post(name: self, object: object,
										  userInfo: userInfo)
	}
}

// http://stackoverflow.com/questions/30757193/ddg#39425959
extension Character {
	/// A simple emoji is one scalar and presented to the user as an Emoji
	public var isSimpleEmoji: Bool {
		guard let firstScalar = unicodeScalars.first else { return false }
		return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
	}

	/// Checks if the scalars will be merged into an emoji
	public var isCombinedIntoEmoji: Bool { unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false }

	public var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}

// http://stackoverflow.com/questions/30757193/ddg#39425959
extension String {
	public var isSingleEmoji: Bool { count == 1 && containsEmoji }

	public var containsEmoji: Bool { contains { $0.isEmoji } }

	public var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }

	public var emojiString: String { emojis.map { String($0) }.reduce("", +) }

	public var emojis: [Character] { filter { $0.isEmoji } }

	public var emojiScalars: [UnicodeScalar] { filter { $0.isEmoji }.flatMap { $0.unicodeScalars } }
}

extension String {
	/// stores the encoding along the serialization of the string to let decoders know which it is
	public func data(prefixedEncoding encoding: String.Encoding) -> Data? {
		// Java / Android compatibility: only use encodings defined in java.nio.charset.StandardCharsets
		var encoding = encoding
		switch encoding {
		case .utf8, .ascii, .utf16, .utf16BigEndian, .utf16LittleEndian, .isoLatin1:
			// conforms to standard
			break
		default:
			encoding = .utf8
		}

		guard let payload = self.data(using: encoding) else { return nil }

		// NOTE: MemoryLayout<String.Encoding.RawValue>.size would be depending on architecture (64 or 32 bits)
		var encodingRawValue = UInt32(encoding.rawValue)
		let data = Data(bytesNoCopy: &encodingRawValue, count: MemoryLayout<UInt32>.size, deallocator: Data.Deallocator.none)
		return data + payload
	}
	
	/// takes data encoded with <code>data(prefixedEncoding:)</code> and constructs a string with the serialized encoding
	public init?(dataPrefixedEncoding data: Data) {
		// NOTE: MemoryLayout<String.Encoding.RawValue>.size would be depending on architecture (64 or 32 bits)
		let encodingData = data.subdata(in: 0..<MemoryLayout<UInt32>.size)
		
		var encodingRawValue: UInt32 = UInt32(String.Encoding.utf8.rawValue)
		withUnsafeMutableBytes(of: &encodingRawValue) { pointer in
			pointer.copyBytes(from: encodingData)
		}
		
		let encoding = String.Encoding(rawValue: String.Encoding.RawValue(encodingRawValue))
		let suffix = data.suffix(from: MemoryLayout<UInt32>.size)
		self.init(data: suffix, encoding: encoding)
	}
	
	/// returns first count characters
	public func left(_ count: Int) -> String {
		let rightEnd = index(startIndex, offsetBy: count, limitedBy: endIndex) ?? endIndex
		return String(self[..<rightEnd])
	}
	
	/// returns last count characters
	public func right(_ count: Int) -> String {
		let leftEnd = index(endIndex, offsetBy: -count, limitedBy: startIndex) ?? startIndex
		return String(self[leftEnd...])
	}
	
	public var middleIndex: String.Index {
		return index(startIndex, offsetBy: count / 2, limitedBy: endIndex) ?? endIndex
	}

	/// Cap number of characters to <code>maxUtf8Length</code>. Use in <code>func textField(_: UITextField, shouldChangeCharactersIn: NSRange, replacementString: String) -> Bool</code>
	func allowChangeCharacters(in range: NSRange, replacementString string: String, maxUtf8Length: Int) -> Bool {
		let oldLength = self.utf8.count
		if (range.length + range.location > oldLength) {
			return false
		}
		return oldLength + string.utf8.count - range.length <= maxUtf8Length
	}
}

// Hex string parsing, e. g. useful for interaction with PostgreSQL's bytea type
// base on https://stackoverflow.com/questions/26501276/converting-hex-string-to-nsdata-in-swift
extension Data {
	public func hexString() -> String {
		return self.map { String(format: "%02x", $0) }.joined()
	}
	
	private static let hexRegex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)

	public init?(hexString: String) {
		guard hexString.count % 2 == 0 else { return nil }
		self.init(capacity: hexString.count / 2)

		// TODO sanity check, whether hexString is really only hex digits, and if not, return nil
		Data.hexRegex.enumerateMatches(in: hexString, range: NSRange(hexString.startIndex..., in: hexString)) { match, _, _ in
			let byteString = (hexString as NSString).substring(with: match!.range)
			let num = UInt8(byteString, radix: 16)!
			self.append(num)
		}
	}

	public init?(hexStringBroken hexString: String) {
		guard hexString.count % 2 == 0 else { return nil }


		let nsString = hexString as NSString
		let matches = Self.hexRegex.matches(in: hexString, options: [], range: NSRange(location: 0, length: nsString.length))
		let bytes = stride(from: 0, to: hexString.count, by: 2).compactMap { (i) -> UInt8? in
			let range = NSRange(location: i, length: 2)
			let byteString = nsString.substring(with: range)
			return UInt8(byteString, radix: 16)
		}

		// DOESN'T WORK!
		guard matches.count == 1, matches[0].range.location == 0, matches[0].range.length == hexString.count, bytes.count == hexString.count / 2 else {
			return nil
		}

		self.init(bytes)
	}

	public struct EmptyError: Error {}

	/// Allows operations on the binary data via an `UnsafePointer`.
	///
	/// This function is a replacement of the old `mutating func withUnsafeBytes<ResultType, ContentType>(_ body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType`.
	/// - Throws: An `EmptyError` error is thrown if `count` is zero, or the error thrown by `body`.
	public func withUnsafePointer<ResultType, ContentType>(_ body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType {
		return try self.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
			guard let bytePointer = bufferPointer.bindMemory(to: ContentType.self).baseAddress else { throw EmptyError() }
			return try body(bytePointer)
		}
	}

	/// Allows operations on the binary data via an `UnsafeMutablePointer`.
	///
	/// This function is a replacement of the old `mutating func withUnsafeMutableBytes<ResultType, ContentType>(_ body: (UnsafeMutablePointer<ContentType>) throws -> ResultType) rethrows -> ResultType`.
	/// - Throws: An `EmptyError` error is thrown if `count` is zero, or the error thrown by `body`.
	public mutating func withUnsafeMutablePointer<ResultType, ContentType>(_ body: (UnsafeMutablePointer<ContentType>) throws -> ResultType) rethrows -> ResultType {
		return try self.withUnsafeMutableBytes { (bufferPointer: UnsafeMutableRawBufferPointer) in
			guard let bytePointer = bufferPointer.bindMemory(to: ContentType.self).baseAddress else { throw EmptyError() }
			return try body(bytePointer)
		}
	}
}

extension UUID {
	public var binaryRepresentation: [UInt8] {
		return [
			uuid.0,
			uuid.1,
			uuid.2,
			uuid.3,
			uuid.4,
			uuid.5,
			uuid.6,
			uuid.7,
			uuid.8,
			uuid.9,
			uuid.10,
			uuid.11,
			uuid.12,
			uuid.13,
			uuid.14,
			uuid.15
		]
	}

	public init?<D: DataProtocol>(binaryRepresentation: D) {
		let b = binaryRepresentation
		guard b.count > 15 else { return nil }

		let firstIndex = b.startIndex

		self.init(uuid: (
			b[firstIndex],
			b[b.index(firstIndex, offsetBy: 1)],
			b[b.index(firstIndex, offsetBy: 2)],
			b[b.index(firstIndex, offsetBy: 3)],
			b[b.index(firstIndex, offsetBy: 4)],
			b[b.index(firstIndex, offsetBy: 5)],
			b[b.index(firstIndex, offsetBy: 6)],
			b[b.index(firstIndex, offsetBy: 7)],
			b[b.index(firstIndex, offsetBy: 8)],
			b[b.index(firstIndex, offsetBy: 9)],
			b[b.index(firstIndex, offsetBy: 10)],
			b[b.index(firstIndex, offsetBy: 11)],
			b[b.index(firstIndex, offsetBy: 12)],
			b[b.index(firstIndex, offsetBy: 13)],
			b[b.index(firstIndex, offsetBy: 14)],
			b[b.index(firstIndex, offsetBy: 15)]
		))
	}
}

extension Bool {
	/// Create an instance initialized to false, if <code>value</code> is zero, and true otherwise.
	public init<T: BinaryInteger>(_ value: T) {
		self.init(value != 0)
	}
	
	public var binaryRepresentation: Data {
		return self ? Data(repeating: UInt8(1), count: 1) : Data(count: 1)
	}
}

extension SignedInteger {
	/// Create an instance initialized to zero, if <code>value</code> is false, and 1 otherwise.
	public init(_ value: Bool) {
		self.init(value ? 1 : 0)
	}
}

extension UnsignedInteger {
	/// Create an instance initialized to zero, if <code>value</code> is false, and 1 otherwise.
	public init(_ value: Bool) {
		self.init(value ? 1 : 0)
	}
}

extension CGColor {
	public func inverted() -> CGColor? {
		guard var invertedComponents = components else { return nil }
		for index in invertedComponents.startIndex..<invertedComponents.index(before: invertedComponents.endIndex) {
			invertedComponents[index] = 1.0 - invertedComponents[index]
		}
		return CGColor(colorSpace: colorSpace!, components: invertedComponents)
	}
}

extension SecKey {
	/// Throws an error when `status` indicates a failure, otherwise does nothing.
	///
	/// - Parameter status: The status code returned by a security operation.
	/// - Parameter localizedError: The error message added as `NSLocalizedDescriptionKey` to the thrown error.
	///
	/// - Throws: An `NSError` when `status` is not `errSecSuccess`, with `NSLocalizedFailureReasonErrorKey` set to the error message corresponding to `status`.
	public static func check(status: OSStatus, localizedError: String) throws {
		guard status != errSecSuccess else { return }

		let msg = errorMessage(describing: status)
		NSLog("SecKey.Extension: OSStatus \(status) check failed: \(msg)")
		let userInfo: [String : Any] = [NSLocalizedDescriptionKey : localizedError,
								 NSLocalizedFailureReasonErrorKey : msg,
									   NSLocalizedFailureErrorKey : makeOSStatusError(from: status)]
		throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: userInfo)
	}
}

extension Collection where Element: Comparable {
	/// Returns whether the element was found, the index of the element, or the index where it needs to be inserted.
	public func binarySearch(_ element: Element) -> (Bool, Index) {
		var low = startIndex
		var high = endIndex
		while low < high {
			let mid = index(low, offsetBy: distance(from: low, to: high)/2)
			if self[mid] == element {
				return (true, mid)
			} else if self[mid] < element {
				low = index(after: mid)
			} else {
				high = mid
			}
		}

		return (false, low)
	}
}

public protocol GenEquatable {
	associatedtype Other

	static func == (lhs: Self, rhs: Other) -> Bool
}

public protocol GenComparable : GenEquatable {

	static func < (lhs: Self, rhs: Other) -> Bool

//	static func <= (lhs: Self, rhs: Other) -> Bool
//
//	static func >= (lhs: Self, rhs: Other) -> Bool
//
//	static func > (lhs: Self, rhs: Other) -> Bool
}

extension Collection where Element: GenComparable {
	/// Returns whether the element was found, the index of the element, or the index where it needs to be inserted.
	public func binarySearch(_ other: Element.Other) -> (Bool, Index) {
		var low = startIndex
		var high = endIndex
		while low < high {
			let mid = index(low, offsetBy: distance(from: low, to: high)/2)
			if self[mid] == other {
				return (true, mid)
			} else if self[mid] < other {
				low = index(after: mid)
			} else {
				high = mid
			}
		}

		return (false, low)
	}
}


import ImageIO
import CoreServices
extension CGImage {
	public static func from(url: URL) throws -> CGImage? {
		guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to create JPEG data source", code: -502)
		}
		return CGImageSourceCreateImageAtIndex(src, 0, nil)
	}

	public func jpgData(compressionQuality: CGFloat) throws -> Data {
		let jpgDataBuffer = NSMutableData()

		guard let dest = CGImageDestinationCreateWithData(jpgDataBuffer, "public.jpeg" as CFString /* kUTTypeJPEG */, 1, nil) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to create JPEG data destination", code: -503)
		}
		CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality : NSNumber(value: Float(compressionQuality))] as CFDictionary)
		CGImageDestinationAddImage(dest, self, nil)

		guard CGImageDestinationFinalize(dest) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to finalize image destination", code: -504)
		}

		return jpgDataBuffer as Data
	}

	public func save(to url: URL, compressionQuality: CGFloat) throws {
		guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString /* kUTTypeJPEG */, 1, nil) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to create JPEG URL destination", code: -503)
		}
		CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality : NSNumber(value: Float(compressionQuality))] as CFDictionary)
		CGImageDestinationAddImage(dest, self, nil)

		guard CGImageDestinationFinalize(dest) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to finalize image destination", code: -504)
		}
	}
}
