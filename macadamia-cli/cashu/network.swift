//
//  network.swift
//  macadamia-cli
//
//  Created by Dario Lass on 01.12.23.
//

import Foundation

// make network request, check responses
// pass data to model for parsing

enum NetworkError: Error {
    case connectionError
    case urlError
    case decodingError
    case encodingError
    case serverError(statusCode: Int)
    case meltError //TODO: rename
    case unknownError
}

enum Network {
    
    //MARK: - Download Keyset  /keys
    //TODO: load all keysets, mark one as current
    static func loadCurrentKeyset(fromMint mint:Mint, completion: @escaping (Result<Dictionary<String,String>,Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: URLRequest(url: mint.url.appending(path: "keys"))) { data, response, error in
            if data != nil {
                let dict = try! JSONSerialization.jsonObject(with: data!, options: []) as! [String: String]
                completion(.success(dict))
            } else if error != nil {
                completion(.failure(error!))
            }
        }
        task.resume()
    }

    //MARK: - MINT
    func mintRequest() {
        //GET + POST
    }

    func decodeMintRequestResponse() {
        
    }

    //MARK: - SPLIT
    func splitRequest() {
        // POST
    }

    func decodeSplitRequestResponse(_ data:Data) {
        
    }

    //MARK: - MELT
    static func meltRequest(mint:Mint, meltRequest:MeltRequest, completion: @escaping (Result<Void,Error>) -> Void) {
        // POST
        guard let payload = try? JSONEncoder().encode(meltRequest) else {
            completion(.failure(NetworkError.encodingError))
            return
        }
        var request = URLRequest(url: mint.url.appending(path: "melt"))
        request.httpMethod = "POST"
        request.httpBody = payload
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, httpResponse, error in
            if data != nil && error == nil {
                if let response = try? JSONDecoder().decode(MeltRequestResponse.self, from: data!), response.paid {
                    completion(.success(()))
                } else {
                    print(String(data: data!, encoding: .utf8)!)
                    completion(.failure(NetworkError.meltError))
                }
            } else {
                completion(.failure(error ?? NetworkError.decodingError))
            }
        }
        task.resume()
    }
    
    //MARK: - CHECK FEE /checkfee
    static func checkFee(mint:Mint, invoice:String, completion: @escaping (Result<Int,Error>) -> Void) {
        
        let jsonPayload: [String: String] = [
            "pr": invoice
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonPayload, options: []) else {
            print("whoops")
            return
        }
        
        var request = URLRequest(url: mint.url.appending(path: "checkfees"))
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if data != nil {
                if let result = try? JSONSerialization.jsonObject(with: data!) as? [String:Int] {
                    completion(.success(result["fee"]!))
                } else {
                    print("failed to decode fee as integer from response data")
                    completion(.failure(NetworkError.decodingError))
                }
            }
        }

        task.resume()

    }

    func decodeMeltRequestResponse() {
        
    }

    //MARK: - RESTORE
    static func restoreRequest(mintURL:URL, outputs:[Output_JSON]) async throws -> RestoreRequestResponse {
        // POST
        
        //construct payload
        let restoreRequest = PostMintRequest(outputs: outputs)
        
        guard let body = try? JSONEncoder().encode(restoreRequest) else {
            throw NetworkError.encodingError
        }
        
        //make request
        var httpRequest = URLRequest(url: mintURL.appending(path: "restore"))
        httpRequest.httpMethod = "POST"
        httpRequest.httpBody = body
        httpRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: httpRequest)
        //print(response)
        print(String(data: data, encoding: .utf8))
        
        let jsonObject = try! JSONSerialization.jsonObject(with: body, options: [])
        let prettyData = try! JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
        if let prettyString = String(data: prettyData, encoding: .utf8) {
            print(prettyString)
        }
        
        guard let decoded = try? JSONDecoder().decode(RestoreRequestResponse.self ,from: data) else {
            let error = parseHTTPErrorResponse(data: data, response: response)
            throw error
        }
        
        // return decoded result
        return decoded
    }

    func decodeRestoreRequestResponse() {
        
    }

    //MARK: - swap requests??

    //MARK: - Error handling
    static func parseHTTPErrorResponse(data:Data?, response:URLResponse) -> Error {
        //TODO: add real error parsing
        return NetworkError.unknownError
    }
}

