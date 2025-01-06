//
//  Error.swift
//  macadamia
//
//  Created by zm on 11.12.24.
//

import Foundation

enum macadamiaError: Error {
    case databaseError(String)
    case unknownMint(String)
    case multiMintToken
}
