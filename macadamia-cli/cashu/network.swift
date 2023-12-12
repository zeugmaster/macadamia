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
    //MARK: - Keysets
    static func loadAllKeysetIDs(mintURL:URL) async throws -> KeysetIDResponse {
        let (data, response) = try await URLSession.shared.data(from: mintURL.appending(path: "keysets"))
        //TODO: check response for errors
        guard let decodedResponse = try? JSONDecoder().decode(KeysetIDResponse.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decodedResponse
    }
    
    static func loadKeyset(mintURL:URL, keysetID:String?) async throws -> Dictionary<String,String> {
        var url = mintURL.appending(path: "keys")
        if keysetID != nil {
            if keysetID!.count == "8wktXIto+zu/".count {
                url.append(path: keysetID!.makeURLSafe())
            } else {
                url.append(path: keysetID!)
            }
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        //TODO: check response for errors
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return dict
    }

    //MARK: - MINT
    static func requestQuote(for amount:Int, from mint:Mint) async throws -> QuoteRequestResponse {
        let urlString = mint.url.absoluteString + "/mint?amount=\(String(amount))"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let decoded = try? JSONDecoder().decode(QuoteRequestResponse.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decoded
    }
    
    static func requestSignature(mint:Mint, outputs:[Output], amount:Int, invoiceHash:String) async throws -> [Promise] {
        //POST
        let url = URL(string: mint.url.absoluteString + "/mint?hash=" + invoiceHash)!
        guard let payload = try? JSONEncoder().encode(PostMintRequest(outputs: outputs)) else {
            throw NetworkError.encodingError
        }
        var httpReq = URLRequest(url: url)
        httpReq.httpMethod = "POST"
        httpReq.httpBody = payload
        httpReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: httpReq)
        guard let decoded = try? JSONDecoder().decode(SignatureRequestResponse.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decoded.promises
    }

    //MARK: - SPLIT
    static func split(for mint:Mint, proofs:[Proof], outputs:[Output]) async throws -> [Promise] {
        // POST
        let url = mint.url.appending(path: "/split")
        guard let payload = try? JSONEncoder().encode(SplitRequest_JSON(proofs: proofs, outputs: outputs)) else {
            throw NetworkError.encodingError
        }
        var httpReq = URLRequest(url: url)
        httpReq.httpMethod = "POST"
        httpReq.httpBody = payload
        httpReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: httpReq)
        guard let decoded = try? JSONDecoder().decode(SignatureRequestResponse.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decoded.promises
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

    //MARK: - RESTORE
    static func restoreRequest(mintURL:URL, outputs:[Output]) async throws -> RestoreRequestResponse {
        // POST
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
        
        guard let decoded = try? JSONDecoder().decode(RestoreRequestResponse.self ,from: data) else {
            let error = parseHTTPErrorResponse(data: data, response: response)
            throw error
        }
        
        // return decoded result
        return decoded
    }

    //MARK: - inter mint swap requests (?)

    //MARK: - Error handling
    static func parseHTTPErrorResponse(data:Data?, response:URLResponse) -> Error {
        //TODO: add real error parsing
        print("PARSING ERROR:")
        print("Data returned from http request:" + (String(data: data!, encoding: .utf8) ?? "could not turn data to string"))
        print("http response: " + String(describing: response))
        return NetworkError.unknownError
    }
}

