// Models.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation

protocol JSONEncodable {
    func encodeToJSON() -> Any
}

public enum ErrorResponse : Error {
    case Error(Int, Data?, Error)
}

open class Response<T> {
    open let statusCode: Int
    open let header: [String: String]
    open let body: T?

    public init(statusCode: Int, header: [String: String], body: T?) {
        self.statusCode = statusCode
        self.header = header
        self.body = body
    }

    public convenience init(response: HTTPURLResponse, body: T?) {
        let rawHeader = response.allHeaderFields
        var header = [String:String]()
        for (key, value) in rawHeader {
            header[key as! String] = value as? String
        }
        self.init(statusCode: response.statusCode, header: header, body: body)
    }
}

private var once = Int()
class Decoders {
    static fileprivate var decoders = Dictionary<String, ((AnyObject) -> AnyObject)>()

    static func addDecoder<T>(clazz: T.Type, decoder: @escaping ((AnyObject) -> T)) {
        let key = "\(T.self)"
        decoders[key] = { decoder($0) as AnyObject }
    }

    static func decode<T>(clazz: T.Type, discriminator: String, source: AnyObject) -> T {
        let key = discriminator;
        if let decoder = decoders[key] {
            return decoder(source) as! T
        } else {
            fatalError("Source \(source) is not convertible to type \(clazz): Maybe swagger file is insufficient")
        }
    }

    static func decode<T>(clazz: [T].Type, source: AnyObject) -> [T] {
        let array = source as! [AnyObject]
        return array.map { Decoders.decode(clazz: T.self, source: $0) }
    }

    static func decode<T, Key: Hashable>(clazz: [Key:T].Type, source: AnyObject) -> [Key:T] {
        let sourceDictionary = source as! [Key: AnyObject]
        var dictionary = [Key:T]()
        for (key, value) in sourceDictionary {
            dictionary[key] = Decoders.decode(clazz: T.self, source: value)
        }
        return dictionary
    }

    static func decode<T>(clazz: T.Type, source: AnyObject) -> T {
        initialize()
        if T.self is Int32.Type && source is NSNumber {
            return (source as! NSNumber).int32Value as! T;
        }
        if T.self is Int64.Type && source is NSNumber {
            return source.int64Value as! T;
        }
        if T.self is UUID.Type && source is String {
            return UUID(uuidString: source as! String) as! T
        }
        if source is T {
            return source as! T
        }
        if T.self is Data.Type && source is String {
            return Data(base64Encoded: source as! String) as! T
        }

        let key = "\(T.self)"
        if let decoder = decoders[key] {
           return decoder(source) as! T
        } else {
            fatalError("Source \(source) is not convertible to type \(clazz): Maybe swagger file is insufficient")
        }
    }

    static func decodeOptional<T>(clazz: T.Type, source: AnyObject?) -> T? {
        if source is NSNull {
            return nil
        }
        return source.map { (source: AnyObject) -> T in
            Decoders.decode(clazz: clazz, source: source)
        }
    }

    static func decodeOptional<T>(clazz: [T].Type, source: AnyObject?) -> [T]? {
        if source is NSNull {
            return nil
        }
        return source.map { (someSource: AnyObject) -> [T] in
            Decoders.decode(clazz: clazz, source: someSource)
        }
    }

    static func decodeOptional<T, Key: Hashable>(clazz: [Key:T].Type, source: AnyObject?) -> [Key:T]? {
        if source is NSNull {
            return nil
        }
        return source.map { (someSource: AnyObject) -> [Key:T] in
            Decoders.decode(clazz: clazz, source: someSource)
        }
    }

    private static var __once: () = {
        let formatters = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss"
        ].map { (format: String) -> DateFormatter in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            return formatter
        }
        // Decoder for Date
        Decoders.addDecoder(clazz: Date.self) { (source: AnyObject) -> Date in
           if let sourceString = source as? String {
                for formatter in formatters {
                    if let date = formatter.date(from: sourceString) {
                        return date
                    }
                }
            }
            if let sourceInt = source as? Int64 {
                // treat as a java date
                return Date(timeIntervalSince1970: Double(sourceInt / 1000) )
            }
            fatalError("formatter failed to parse \(source)")
        } 

        // Decoder for [Account]
        Decoders.addDecoder(clazz: [Account].self) { (source: AnyObject) -> [Account] in
            return Decoders.decode(clazz: [Account].self, source: source)
        }
        // Decoder for Account
        Decoders.addDecoder(clazz: Account.self) { (source: AnyObject) -> Account in
            let sourceDictionary = source as! [AnyHashable: Any]

            let instance = Account()
            instance.peerID = Decoders.decodeOptional(clazz: PeerID.self, source: sourceDictionary["peerID"] as AnyObject?)
            instance.sequenceNumber = Decoders.decodeOptional(clazz: Int32.self, source: sourceDictionary["sequenceNumber"] as AnyObject?)
            return instance
        }


        // Decoder for [PeerID]
        Decoders.addDecoder(clazz: [PeerID].self) { (source: AnyObject) -> [PeerID] in
            return Decoders.decode(clazz: [PeerID].self, source: source)
        }
        // Decoder for PeerID
        Decoders.addDecoder(clazz: PeerID.self) { (source: AnyObject) -> PeerID in
            if let source = source as? UUID {
                return source
            }
            fatalError("Source \(source) is not convertible to typealias PeerID: Maybe swagger file is insufficient")
        }


        // Decoder for [Pin]
        Decoders.addDecoder(clazz: [Pin].self) { (source: AnyObject) -> [Pin] in
            return Decoders.decode(clazz: [Pin].self, source: source)
        }
        // Decoder for Pin
        Decoders.addDecoder(clazz: Pin.self) { (source: AnyObject) -> Pin in
            let sourceDictionary = source as! [AnyHashable: Any]

            let instance = Pin()
            instance.peerID = Decoders.decodeOptional(clazz: PeerID.self, source: sourceDictionary["peerID"] as AnyObject?)
            instance.publicKey = Decoders.decodeOptional(clazz: PublicKey.self, source: sourceDictionary["publicKey"] as AnyObject?)
            instance.match = Decoders.decodeOptional(clazz: Bool.self, source: sourceDictionary["match"] as AnyObject?)
            return instance
        }


        // Decoder for [PinPoints]
        Decoders.addDecoder(clazz: [PinPoints].self) { (source: AnyObject) -> [PinPoints] in
            return Decoders.decode(clazz: [PinPoints].self, source: source)
        }
        // Decoder for PinPoints
        Decoders.addDecoder(clazz: PinPoints.self) { (source: AnyObject) -> PinPoints in
            if let source = source as? Int32 {
                return source
            }
            fatalError("Source \(source) is not convertible to typealias PinPoints: Maybe swagger file is insufficient")
        }


        // Decoder for [PublicKey]
        Decoders.addDecoder(clazz: [PublicKey].self) { (source: AnyObject) -> [PublicKey] in
            return Decoders.decode(clazz: [PublicKey].self, source: source)
        }
        // Decoder for PublicKey
        Decoders.addDecoder(clazz: PublicKey.self) { (source: AnyObject) -> PublicKey in
            if let source = source as? Data {
                return source
            }
            fatalError("Source \(source) is not convertible to typealias PublicKey: Maybe swagger file is insufficient")
        }
    }()

    static fileprivate func initialize() {
        _ = Decoders.__once
    }
}
