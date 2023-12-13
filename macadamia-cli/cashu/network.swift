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
    //MARK: MINT INFO
    static func mintInfo(mintURL:URL) async throws -> MintInfo {
        let url = mintURL.appending(path: "info")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let decoded = try? JSONDecoder().decode(MintInfo.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decoded
    }
    
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
    
    //MARK: - STATE CHECK
    static func check(mint:Mint, proofs:[Proof]) async throws -> StateCheckResponse {
        let url = mint.url.appending(path: "check")
        guard let payload = try? JSONEncoder().encode(["proofs":proofs]) else {
            throw NetworkError.encodingError
        }
        let httpReq = URLRequest.post(url: url, body: payload)
        let (data, response) = try await URLSession.shared.data(for: httpReq)
        guard let decoded = try? JSONDecoder().decode(StateCheckResponse.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decoded
    }

    //MARK: - MELT    
    static func melt(mint:Mint, meltRequest:MeltRequest) async throws -> MeltRequestResponse {
        guard let payload = try? JSONEncoder().encode(meltRequest) else {
            throw NetworkError.encodingError
        }
        var httpReq = URLRequest(url: mint.url.appending(path: "melt"))
        httpReq.httpMethod = "POST"
        httpReq.httpBody = payload
        httpReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: httpReq)
        guard let decoded = try? JSONDecoder().decode(MeltRequestResponse.self, from: data) else {
            throw parseHTTPErrorResponse(data: data, response: response)
        }
        return decoded
    }
    
    //MARK: - CHECK FEE /checkfee
    static func checkFee(mint:Mint, invoice:String) async throws -> Int {
        let jsonPayload: [String: String] = [
            "pr": invoice
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonPayload, options: []) else {
            throw NetworkError.encodingError
        }
        let httpReq = URLRequest.post(url: mint.url.appending(path: "checkfees"), body: jsonData)
        let (data, httpResponse) = try await URLSession.shared.data(for: httpReq)
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String:Int],
              let fee = decoded["fee"] else {
            throw parseHTTPErrorResponse(data: data, response: httpResponse)
        }
        return fee
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

extension URLRequest {
    static func post(url:URL, body:Data) -> URLRequest {
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.httpBody = body
        httpRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return httpRequest
    }
}
