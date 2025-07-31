//
//  Error.swift
//  macadamia
//
//  Created by zm on 11.12.24.
//

import Foundation

enum macadamiaError: Error, Sendable {
    case databaseError(String)
    case unknownMint(String?)
    case multiMintToken
    case mintVerificationError(String?)
    
    case unknownKeyset(String)
    
    case lockedToken
    case unsupportedUnit
}
