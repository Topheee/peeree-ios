//
//  GenericFunctions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 20.12.15.
//  Copyright © 2015 Kobusch. All rights reserved.
//

import Foundation
import CoreGraphics

// MARK: - Functions

func archiveObjectInUserDefs<T: NSSecureCoding>(_ object: T, forKey: String) {
	#if TESTING
	PeereeTests.UserDefaultsMock.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
	#else
	UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: object), forKey: forKey)
	#endif
}

func unarchiveObjectFromUserDefs<T: NSSecureCoding>(_ forKey: String) -> T? {
	#if TESTING
	guard let data = UserDefaultsMock.standard.object(forKey: forKey) as? Data else { return nil }
	#else
	guard let data = UserDefaults.standard.object(forKey: forKey) as? Data else { return nil }
	#endif
	
	return NSKeyedUnarchiver.unarchiveObject(with: data) as? T
}

/// create a plist and add it to copied resources. In the file, make the root entry to an array and add string values to it
func arrayFromBundle(name: String) -> [String]? {
	guard let url = Bundle.main.url(forResource: name, withExtension:"plist") else { return nil }
	return NSArray(contentsOf: url) as? [String]
}

func createApplicationError(localizedDescription: String, code: Int = -1) -> Error {
	return NSError(domain: Bundle.main.bundleIdentifier ?? Bundle.main.bundlePath, code: code, userInfo: [NSLocalizedDescriptionKey : localizedDescription])
}

func createSystemError() -> Error? {
	let code = errno
	guard let errorCString = strerror(code), let errorString = String(utf8String: errorCString) else { return nil }

	return createApplicationError(localizedDescription: errorString, code: Int(code))
}

func errorMessage(for status: OSStatus) -> String {
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

func generateRandomData(length: Int) throws -> Data {
	var nonce = Data(count: length)
	let status = nonce.withUnsafeMutablePointer({ SecRandomCopyBytes(kSecRandomDefault, length, $0) })
	if status == errSecSuccess {
		return nonce
	} else {
		throw createApplicationError(localizedDescription: errorMessage(for: status), code: Int(status))
	}
}

//"Swift 2" - not working
///// Objective-C __bridge cast
//func bridge<T : AnyObject>(_ obj : T) -> UnsafeRawPointer {
//	return UnsafePointer(Unmanaged.passUnretained(obj).toOpaque())
//	// return unsafeAddressOf(obj) // ***
//}
//
///// Objective-C __bridge cast
//func bridge<T : AnyObject>(_ ptr : UnsafeRawPointer) -> T {
//	return Unmanaged<T>.fromOpaque(OpaquePointer(ptr)).takeUnretainedValue()
//	// return unsafeBitCast(ptr, T.self) // ***
//}
//
///// Objective-C __bridge_retained equivalent. Casts the object pointer to a void pointer and retains the object.
//func bridgeRetained<T : AnyObject>(_ obj : T) -> UnsafeRawPointer {
//	return UnsafePointer(Unmanaged.passRetained(obj).toOpaque())
//}
//
///// Objective-C __bridge_transfer equivalent. Converts the void pointer back to an object pointer and consumes the retain.
//func bridgeTransfer<T : AnyObject>(_ ptr : UnsafeRawPointer) -> T {
//	return Unmanaged<T>.fromOpaque(OpaquePointer(ptr)).takeRetainedValue()
//}

//Swift 1.2
/// Objective-C __bridge cast
func bridge<T : AnyObject>(obj : T) -> UnsafeRawPointer {
	return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

/// Objective-C __bridge cast
func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
	return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

/// Objective-C __bridge_retained equivalent. Casts the object pointer to a void pointer and retains the object.
func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
	return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
}

/// Objective-C __bridge_transfer equivalent. Converts the void pointer back to an object pointer and consumes the retain.
func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
	return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
}


// MARK: - Extensions

extension CGRect {
	var center: CGPoint {
		return CGPoint(x: midX, y: midY)
	}
	
	init(squareEdgeLength: CGFloat) {
		self.init(x: 0.0, y: 0.0, width: squareEdgeLength, height: squareEdgeLength)
	}
}

extension CGSize {
	init(squareEdgeLength: CGFloat) {
		self.init(width: squareEdgeLength, height: squareEdgeLength)
	}
}

extension RawRepresentable where Self.RawValue == String {
	var localizedRawValue: String {
		return Bundle.main.localizedString(forKey: rawValue, value: nil, table: nil)
	}
	
	public func addObserver(usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
		return NotificationCenter.addObserverOnMain(self.rawValue, usingBlock: block)
	}
}

extension NotificationCenter {
	class func addObserverOnMain(_ name: String?, usingBlock block: @escaping (Notification) -> Void) -> NSObjectProtocol {
		return NotificationCenter.default.addObserver(forName: name.map { NSNotification.Name(rawValue: $0) }, object: nil, queue: OperationQueue.main, using: block)
	}
}

extension String {
	/// stores the encoding along the serialization of the string to let decoders know which it is
	func data(prefixedEncoding encoding: String.Encoding) -> Data? {
		// Java / Android compatibility: only use encodings defined in java.nio.charset.StandardCharsets
		var encoding = encoding
		switch encoding {
		case .utf8, .ascii, .utf16, .utf16BigEndian, .utf16LittleEndian, .isoLatin1:
			// conforms to standard
			break
		default:
			encoding = .utf8
		}
		// NOTE: all the sizes where MemoryLayout<String.Encoding.RawValue>.size, but that is depending on architecture (64 or 32 bits), so we choose 32 bits (4 bytes) fixed
		// PERFORMANCE: let size = MemoryLayout<UInt32>.size + nickname.lengthOfBytes(using: encoding)
		var encodingRawValue = UInt32(encoding.rawValue)
		var data = Data(bytesNoCopy: &encodingRawValue, count: MemoryLayout<UInt32>.size, deallocator: Data.Deallocator.none)
		
		guard let payload = self.data(using: encoding) else { return nil }
		data.append(payload)
		return data
	}
	
	/// takes data encoded with <code>data(prefixedEncoding:)</code> and constructs a string with the serialized encoding
	init?(dataPrefixedEncoding data: Data) {
		// NOTE: all the sizes where MemoryLayout<String.Encoding.RawValue>.size, but that is depending on architecture (64 or 32 bits), so we choose 32 bits (4 bytes) fixed
		// PEFORMANCE
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
	func left(_ count: Int) -> String {
		let rightEnd = index(startIndex, offsetBy: count, limitedBy: endIndex) ?? endIndex
		return String(self[..<rightEnd])
	}
	
	/// returns last count characters
	func right(_ count: Int) -> String {
		let leftEnd = index(endIndex, offsetBy: -count, limitedBy: startIndex) ?? startIndex
		return String(self[leftEnd...])
	}
	
	var middleIndex: String.Index {
		return index(startIndex, offsetBy: count / 2, limitedBy: endIndex) ?? endIndex
	}
}

// Hex string parsing, e. g. useful for interaction with PostgreSQL's bytea type
// base on https://stackoverflow.com/questions/26501276/converting-hex-string-to-nsdata-in-swift
extension Data {
	func hexString() -> String {
		return self.map { String(format: "%02x", $0) }.joined()
	}
	
	private static let hexRegex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
	
	init?(hexString: String) {
		guard hexString.count % 2 == 0 else { return nil }
		self.init(capacity: hexString.count / 2)

		// TODO sanity check, whether hexString is really only hex digits, and if not, return nil
		Data.hexRegex.enumerateMatches(in: hexString, range: NSRange(hexString.startIndex..., in: hexString)) { match, _, _ in
			let byteString = (hexString as NSString).substring(with: match!.range)
			let num = UInt8(byteString, radix: 16)!
			self.append(num)
		}
	}

	struct EmptyError: Error {}
	/**
	replacement of the old `mutating func withUnsafeBytes<ResultType, ContentType>(_ body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType`. Use only when `count` > 0, otherwise an `EmptyError` error is thrown.
	*/
	func withUnsafePointer<ResultType, ContentType>(_ body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType {
		return try self.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
			guard let bytePointer = bufferPointer.bindMemory(to: ContentType.self).baseAddress else { throw EmptyError() }
			return try body(bytePointer)
		}
	}
	/**
	replacement of the old `mutating func withUnsafeMutableBytes<ResultType, ContentType>(_ body: (UnsafeMutablePointer<ContentType>) throws -> ResultType) rethrows -> ResultType`. Use only when `count` > 0, otherwise an `EmptyError` error is thrown.
	*/
	mutating func withUnsafeMutablePointer<ResultType, ContentType>(_ body: (UnsafeMutablePointer<ContentType>) throws -> ResultType) rethrows -> ResultType {
		return try self.withUnsafeMutableBytes { (bufferPointer: UnsafeMutableRawBufferPointer) in
			guard let bytePointer = bufferPointer.bindMemory(to: ContentType.self).baseAddress else { throw EmptyError() }
			return try body(bytePointer)
		}
	}
}

extension HTTPURLResponse {
	var isFailure: Bool { return statusCode > 399 && statusCode < 600 }
	var isSuccess: Bool { return statusCode > 199 && statusCode < 300 }
}

extension Bool {
	/// Create an instance initialized to false, if <code>value</code> is zero, and true otherwise.
	init<T: BinaryInteger>(_ value: T) {
		self.init(value != 0)
	}
	
	var binaryRepresentation: Data {
		return self ? Data(repeating: UInt8(1), count: 1) : Data(count: 1)
	}
}

extension SignedInteger {
	/// Create an instance initialized to zero, if <code>value</code> is false, and 1 otherwise.
	init(_ value: Bool) {
		self.init(value ? 1 : 0)
	}
}

extension UnsignedInteger {
	/// Create an instance initialized to zero, if <code>value</code> is false, and 1 otherwise.
	init(_ value: Bool) {
		self.init(value ? 1 : 0)
	}
}

extension CGColor {
	func inverted() -> CGColor? {
		guard var invertedComponents = components else { return nil }
		for index in invertedComponents.startIndex..<invertedComponents.index(before: invertedComponents.endIndex) {
			invertedComponents[index] = 1.0 - invertedComponents[index]
		}
		return CGColor(colorSpace: colorSpace!, components: invertedComponents)
	}
}


import ImageIO
import CoreServices
extension CGImage {
	static func from(url: URL) throws -> CGImage? {
		guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to create JPEG data source", code: -502)
		}
		return CGImageSourceCreateImageAtIndex(src, 0, nil)
	}

	func jpgData(compressionQuality: CGFloat) throws -> Data {
		let jpgDataBuffer = NSMutableData()

		guard let dest = CGImageDestinationCreateWithData(jpgDataBuffer, kUTTypeJPEG, 1, nil) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to create JPEG data destination", code: -503)
		}
		CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality : NSNumber(value: Float(compressionQuality))] as CFDictionary)
		CGImageDestinationAddImage(dest, self, nil)

		guard CGImageDestinationFinalize(dest) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to finalize image destination", code: -504)
		}

		return jpgDataBuffer as Data
	}

	func save(to url: URL, compressionQuality: CGFloat) throws {
		guard let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to create JPEG URL destination", code: -503)
		}
		CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality : NSNumber(value: Float(compressionQuality))] as CFDictionary)
		CGImageDestinationAddImage(dest, self, nil)

		guard CGImageDestinationFinalize(dest) else {
			throw createApplicationError(localizedDescription: "ERROR: failed to finalize image destination", code: -504)
		}
	}
}
