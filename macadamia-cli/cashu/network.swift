//
//  network.swift
//  macadamia-cli
//
//  Created by Dario Lass on 01.12.23.
//

import Foundation

// make network request, check responses
// pass data to model for parsing

//MARK: - Download Keyset (call for [allMints]
func loadCurrentKeyset(fromMint mint:Mint) {
    //check also wether loaded keyset and last keyset/keysetID have changed
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
