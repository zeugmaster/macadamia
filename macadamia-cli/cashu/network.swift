//
//  network.swift
//  macadamia-cli
//
//  Created by Dario Lass on 01.12.23.
//

import Foundation

// make network request, check responses
// pass data to model for parsing

enum Network {
    //MARK: - Download Keyset (call for [allMints]
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
    func meltRequest() {
        // POST
    }

    func decodeMeltRequestResponse() {
        
    }

    //MARK: - RESTORE
    func restoreRequest() {
        // POST
    }

    func decodeRestoreRequestResponse() {
        
    }

    //MARK: - swap requests??

    //MARK: - Error handling
    func parseErrorResponse() {
        
    }

}

