//
// DefaultAPI.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation

open class DefaultAPI: APIBase {
    /**
     Account Deletion
     
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func deleteAccount(completion: @escaping ((_ error: ErrorResponse?) -> Void)) {
        deleteAccountWithRequestBuilder().execute { (response, error) -> Void in
            completion(error);
        }
    }

    
    /**
     Account Deletion
     - DELETE /account
     - Deletes a user account. 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature

     - returns: RequestBuilder<Void>
     */
    open class func deleteAccountWithRequestBuilder() -> RequestBuilder<Void> {
        let path = "/account"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil
        
        let url = NSURLComponents(string: URLString)!

        let requestBuilder: RequestBuilder<Void>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .DELETE, url: url.url!, parameters: parameters)
    }

    /**
     Remove Account E-Mail
     
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func deleteAccountEmail(completion: @escaping ((_ error: ErrorResponse?) -> Void)) {
        deleteAccountEmailWithRequestBuilder().execute { (response, error) -> Void in
            completion(error);
        }
    }


    /**
     Remove Account E-Mail
     - DELETE /account/email
     - Removes email address from account. Caution: if the private key gets lost, say, when the Smartphone is lost, there will be no way of recovering this account! 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature

     - returns: RequestBuilder<Void> 
     */
    open class func deleteAccountEmailWithRequestBuilder() -> RequestBuilder<Void> {
        let path = "/account/email"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!


        let requestBuilder: RequestBuilder<Void>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .DELETE, url: url.url!, parameters: parameters)
    }
    
    /**
     Reset Sequence Number
     
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func deleteAccountSecuritySequenceNumber(completion: @escaping ((_ data: Int32?,_ error: ErrorResponse?) -> Void)) {
        deleteAccountSecuritySequenceNumberWithRequestBuilder().execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }
    
    
    /**
     Reset Sequence Number
     - DELETE /account/security/sequence_number
     - Generates a new random sequence number, which is a per-request incrementing integer number to prevent from replay attacks. This number has to be incremented by 1 after each request.  For this call the signature can be omitted as it should only be needed if the sequence numbers of the client and the server do not match any more and therefore the client anyway cannot compute the correct signature.
     - examples: [{contentType=application/json, example="aeiou"}]
     
     - returns: RequestBuilder<String>
     */
    open class func deleteAccountSecuritySequenceNumberWithRequestBuilder() -> RequestBuilder<Int32> {
        let path = "/account/security/sequence_number"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil
        
        let url = NSURLComponents(string: URLString)!
        
        
        let requestBuilder: RequestBuilder<Int32>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()
        
        return requestBuilder.init(method: .DELETE, url: url.url!, parameters: parameters, isValidated: false)
    }

    /**
     Request Public Key Reset
     
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func deleteAccountSecurityPublicKey(completion: @escaping ((_ error: ErrorResponse?) -> Void)) {
        deleteAccountSecurityPublicKeyWithRequestBuilder().execute { (response, error) -> Void in
            completion(error);
        }
    }


    /**
     Request Public Key Reset
     - DELETE /account/security/public_key
     - Sends a random number to the user's e-mail address, which has then to be passed along when resetting the public key in the PUT variant of this request. The key is only valid for 30 minutes. 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature

     - returns: RequestBuilder<Void> 
     */
    open class func deleteAccountSecurityPublicKeyWithRequestBuilder() -> RequestBuilder<Void> {
        let path = "/account/security/public_key"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!


        let requestBuilder: RequestBuilder<Void>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .DELETE, url: url.url!, parameters: parameters)
    }

    /**
     Pin Points of an User Account
     
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func getAccountPinPoints(completion: @escaping ((_ data: PinPoints?,_ error: ErrorResponse?) -> Void)) {
        getAccountPinPointsWithRequestBuilder().execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }


    /**
     Pin Points of an User Account
     - GET /account/pin_points
     - Retrieves the amount of Pin Points a user has available. 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature
     - examples: [{contentType=application/json, example=123}]

     - returns: RequestBuilder<PinPoints> 
     */
    open class func getAccountPinPointsWithRequestBuilder() -> RequestBuilder<PinPoints> {
        let path = "/account/pin_points"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!


        let requestBuilder: RequestBuilder<PinPoints>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .GET, url: url.url!, parameters: parameters)
    }

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
     Retrieve In-App Purchase Product Identifiers
     
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func getInAppPurchaseIosProductIds(completion: @escaping ((_ data: [String]?,_ error: ErrorResponse?) -> Void)) {
        getInAppPurchaseIosProductIdsWithRequestBuilder().execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }


    /**
     Retrieve In-App Purchase Product Identifiers
     - GET /in-app-purchase/ios/product_ids
     - Returns list of all product IDs. Note that at the moment neither peerID nor signature are being evaluated. 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature
     - examples: [{contentType=application/json, example=[ "aeiou" ]}]

     - returns: RequestBuilder<[String]> 
     */
    open class func getInAppPurchaseIosProductIdsWithRequestBuilder() -> RequestBuilder<[String]> {
        let path = "/in-app-purchase/ios/product_ids"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!


        let requestBuilder: RequestBuilder<[String]>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .GET, url: url.url!, parameters: parameters, isValidated: false)
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
     Account Creation
     
     - parameter email: (query) E-Mail for identity reset. The user may request to reset his/her credentials, resulting in a code sent to him to this address, which he must pass along when sending his new public key.  (optional)
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func putAccount(email: String? = nil, completion: @escaping ((_ data: Account?,_ error: ErrorResponse?) -> Void)) {
        putAccountWithRequestBuilder(email: email).execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }
    
    
    /**
     Account Creation
     - PUT /account
     - Creates a new user account with the provided public key and email address. The signature is the public key in this call! 
     - examples: [{contentType=application/json, example={
     "peerID" : { },
  "sequenceNumber" : 123
     }}]
     
     - parameter email: (query) E-Mail for identity reset. The user may request to reset his/her credentials, resulting in a code sent to him to this address, which he must pass along when sending his new public key.  (optional)
     
     - returns: RequestBuilder<Account>
     */
    open class func putAccountWithRequestBuilder(email: String? = nil) -> RequestBuilder<Account> {
        let path = "/account"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil
        
        let url = NSURLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems(values:[
            "email": email
        ])
        
        
        let requestBuilder: RequestBuilder<Account>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()
        
        return requestBuilder.init(method: .PUT, url: url.url!, parameters: parameters)
    }

    /**
     Set New E-Mail of Account
     
     - parameter email: (query) See description in account creation. If parameter is empty, this has same behavior as the DELETE operation.  
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func putAccountEmail(email: String, completion: @escaping ((_ error: ErrorResponse?) -> Void)) {
        putAccountEmailWithRequestBuilder(email: email).execute { (response, error) -> Void in
            completion(error);
        }
    }


    /**
     Set New E-Mail of Account
     - PUT /account/email
     - Sets new e-mail address of the account. 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature
     
     - parameter email: (query) See description in account creation. If parameter is empty, this has same behavior as the DELETE operation.  

     - returns: RequestBuilder<Void> 
     */
    open class func putAccountEmailWithRequestBuilder(email: String) -> RequestBuilder<Void> {
        let path = "/account/email"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems(values:[
            "email": email
        ])
        

        let requestBuilder: RequestBuilder<Void>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .PUT, url: url.url!, parameters: parameters)
    }

    /**
     Cash iOS In-App Purchase
     
     - parameter receiptData: (body) Data of the iOS In-App purchase receipt.  
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func putInAppPurchaseIosReceipt(receiptData: Data, completion: @escaping ((_ data: PinPoints?,_ error: ErrorResponse?) -> Void)) {
        putInAppPurchaseIosReceiptWithRequestBuilder(receiptData: receiptData).execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }


    /**
     Cash iOS In-App Purchase
     - PUT /in-app-purchase/ios/receipt
     - Transforms the iOS in-app purchase product into pin points. 
     - API Key:
       - type: apiKey peerID 
       - name: peerID
     - API Key:
       - type: apiKey signature 
       - name: signature
     - examples: [{contentType=application/json, example=123}]
     
     - parameter receiptData: (body) Data of the iOS In-App purchase receipt.  

     - returns: RequestBuilder<PinPoints> 
     */
    open class func putInAppPurchaseIosReceiptWithRequestBuilder(receiptData: Data) -> RequestBuilder<Int32> {
        let path = "/in-app-purchase/ios/receipt"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil

        let url = NSURLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems(values:[
            "receiptData": receiptData
        ])
        

        let requestBuilder: RequestBuilder<Int32>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()

        return requestBuilder.init(method: .PUT, url: url.url!, parameters: parameters)
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
     - Requests a *Pin*, reducing available pin points and notifies both parties, if a *Pin Match* occurred.
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

    /**
     Reset Public Key
     
     - parameter publicKey: (query) See PublicKey in Definitions.
     - parameter randomNumber: (query) The number sent to the user&#39;s e-mail in the delete variant of this request.
     - parameter completion: completion handler to receive the data and the error objects
     */
    open class func putSecurityPublicKey(publicKey: Data, randomNumber: String, completion: @escaping ((_ data: String?,_ error: ErrorResponse?) -> Void)) {
        putSecurityPublicKeyWithRequestBuilder(publicKey: publicKey, randomNumber: randomNumber).execute { (response, error) -> Void in
            completion(response?.body, error);
        }
    }
    
    
    /**
     Reset Public Key
     - PUT /account/security/public_key
     - Establishes a new public key for the user as well as a new sequence number. This request is intended to be used when the user moved to a new device. Note that the signature is optional here, as the user may has lost his phone. If it is passed, it still has to be computed with the current sequence number and private key!
     - API Key:
     - type: apiKey peerID
     - name: peerID
     - API Key:
     - type: apiKey signature
     - name: signature
     - examples: [{contentType=application/json, example="aeiou"}]
     
     - parameter publicKey: (query) See PublicKey in Definitions.
     - parameter randomNumber: (query) The number sent to the user&#39;s e-mail in the delete variant of this request.
     
     - returns: RequestBuilder<String>
     */
    open class func putSecurityPublicKeyWithRequestBuilder(publicKey: Data, randomNumber: String) -> RequestBuilder<String> {
        let path = "/account/security/public_key"
        let URLString = SwaggerClientAPI.basePath + path
        let parameters: [String:Any]? = nil
        
        let url = NSURLComponents(string: URLString)!
        url.queryItems = APIHelper.mapValuesToQueryItems(values:[
            "publicKey": publicKey,
            "randomNumber": randomNumber
        ])
        
        
        let requestBuilder: RequestBuilder<String>.Type = SwaggerClientAPI.requestBuilderFactory.getBuilder()
        
        return requestBuilder.init(method: .PUT, url: url.url!, parameters: parameters)
    }

}
