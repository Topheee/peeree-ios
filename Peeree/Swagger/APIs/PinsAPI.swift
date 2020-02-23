//
// PinsAPI.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation



open class PinsAPI {
    /**
	 Retrieve All Pinned Users
	 
	 - parameter completion: completion handler to receive the data and the error objects
	 */
	open class func getAccountPins(completion: @escaping ((_ data: [Pin]?,_ error: ErrorResponse?) -> Void)) {
		getAccountPinsWithRequestBuilder().execute { (response, error) -> Void in
			completion(response?.body, error);
		}
	}


	/**
	 Retrieve All Pinned Users
	 - GET /account/pins
	 - Sends all list of all uuid's and public keys to the client. This request should not be needed, except for a new device is installed.
	 - API Key:
	   - type: apiKey peerID
	   - name: peerID
	 - API Key:
	   - type: apiKey signature
	   - name: signature
	 - examples: [{contentType=application/json, example=[ {
  "peerID" : { },
  "match" : true,
  "publicKey" : { }
} ]}]

	 - returns: RequestBuilder<[Pin]>
	 */
	open class func getAccountPinsWithRequestBuilder() -> RequestBuilder<[Pin]> {
		let path = "/account/pins"
		let URLString = SwaggerClientAPI.basePath + path
		let parameters: [String:Any]? = nil

		let url = NSURLComponents(string: URLString)!


		let requestBuilder: RequestBuilder<[Pin]>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

		return requestBuilder.init(method: .GET, url: url.url!, parameters: parameters)
	}
    
    /**
     Pin Status Query
     
     - parameter pinnedID: (query) The PeerID of the opposite user.
     - parameter pinnedKey: (query) See PublicKey in Definitions.
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func getPin(pinnedID: UUID, pinnedKey: Data, completion: @escaping ((_ data: Int32?,_ error: ErrorResponse?) -> Void)) {
        getPinWithRequestBuilder(pinnedID: pinnedID, pinnedKey: pinnedKey).execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }
    
    
    /**
     Pin Status Query
     - GET /pin
     - Returns, whether a the requested peer is pinnend and a pin match occured.
     - API Key:
     - type: apiKey peerID
     - name: peerID
     - API Key:
     - type: apiKey signature
     - name: signature
     - examples: [{contentType=application/json, example=0}]
     
     - parameter pinnedID: (query) The PeerID of the opposite user.
     - parameter pinnedKey: (query) See PublicKey in Definitions.
     
     - returns: RequestBuilder<Int32>
     */
    open class func getPinWithRequestBuilder(pinnedID: UUID, pinnedKey: Data) -> RequestBuilder<Int32> {
        let path = "/pin"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil
        
        let url = NSURLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems(values:[
            "pinnedID": pinnedID,
            "pinnedKey": pinnedKey
            ])
        
        
        let requestBuilder: RequestBuilder<Int32>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()
        
        return requestBuilder.init(method: .GET, url: url.url!, parameters: parameters)
    }

    /**
     Pin Another User
     
     - parameter pinnedID: (query) The PeerID of the opposite user.
     - parameter pinnedKey: (query) See PublicKey in Definitions.
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func putPin(pinnedID: UUID, pinnedKey: Data, completion: @escaping ((_ data: Bool?,_ error: ErrorResponse?) -> Void)) {
        putPinWithRequestBuilder(pinnedID: pinnedID, pinnedKey: pinnedKey).execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }


    /**
     Pin Another User
     - PUT /pin
     - Requests a *Pin*. Notifies both parties, if a *Pin Match* occurred.
     - API Key:
     - type: apiKey peerID
     - name: peerID
     - API Key:
     - type: apiKey signature
     - name: signature
     - examples: [{contentType=application/json, example=true}]
     
     - parameter pinnedID: (query) The PeerID of the opposite user.
     - parameter pinnedKey: (query) See PublicKey in Definitions.
     
     - returns: RequestBuilder<Bool>
     */
    open class func putPinWithRequestBuilder(pinnedID: UUID, pinnedKey: Data) -> RequestBuilder<Bool> {
        let path = "/pin"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems(values:[
            "pinnedID": pinnedID,
            "pinnedKey": pinnedKey
        ])
        

        let requestBuilder: RequestBuilder<Bool>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .PUT, url: url.url!, parameters: parameters)
    }

}
