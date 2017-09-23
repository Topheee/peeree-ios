// APIs.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation

public protocol SecurityDataSource {
    func getSignature() -> String
    func getPeerID() -> String
}

open class SwaggerClientAPI {
    open static var dataSource: SecurityDataSource?
    
    open static let `protocol` = "https"
    open static let host = "131.234.244.1" // "172.20.10.2" // "127.0.0.1" //"rest.peeree.com" // "192.168.12.190" // "www.peeree.com"
    open static let basePath = "\(`protocol`)://\(host)/v1"
    open static let baseURL = URL(string: basePath)!
    open static var credential: URLCredential?
    open static var customHeaders: [String:String] = [:]
    static var requestBuilderFactory: RequestBuilderFactory = AlamofireRequestBuilderFactory()
}

open class APIBase {
    func toParameters(_ encodable: JSONEncodable?) -> [String: Any]? {
        let encoded: Any? = encodable?.encodeToJSON()

        if encoded! is [Any] {
            var dictionary = [String:Any]()
            for (index, item) in (encoded as! [Any]).enumerated() {
                dictionary["\(index)"] = item
            }
            return dictionary
        } else {
            return encoded as? [String:Any]
        }
    }
}

public enum HTTPMethod: String {
    case GET, PUT, POST, DELETE, OPTIONS, HEAD, PATCH
}

open class RequestBuilder<T> {
    var credential: URLCredential?
    var headers: [String:String]
    let parameters: [String:Any]?
    let body: Data?
    let method: HTTPMethod
    let url: URL
    var URLString: String {
        return url.absoluteString
    }
    
    /// Optional block to obtain a reference to the request's progress instance when available.
//    public var onProgressReady: ((Progress) -> ())?

    required public init(method: HTTPMethod, url: URL, parameters: [String:Any]?, headers: [String:String] = [:], body: Data? = nil, isValidated: Bool = true) {
        self.method = method
        self.url = url
        self.parameters = parameters
        self.body = body
        self.headers = headers
        self.credential = nil
        
        addHeaders(SwaggerClientAPI.customHeaders)
    }
    
    open func addHeaders(_ aHeaders:[String:String]) {
        for (header, value) in aHeaders {
            headers[header] = value
        }
    }
    
    open func execute(_ completion: @escaping (_ response: Response<T>?, _ error: ErrorResponse?) -> Void) { }

    public func addHeader(name: String, value: String) -> Self {
        if !value.isEmpty {
            headers[name] = value
        }
        return self
    }
    
    open func addCredential() -> Self {
        self.credential = SwaggerClientAPI.credential
        return self
    }
}

public protocol RequestBuilderFactory {
    func getBuilder<T>() -> RequestBuilder<T>.Type
}
