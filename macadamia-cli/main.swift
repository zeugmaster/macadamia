//
//  main.swift
//  macadamia-cli
//
//  Created by Dario Lass on 09.11.23.
//

import Foundation
import secp256k1

let dispatchGroup = DispatchGroup()

dispatchGroup.enter()

getMintKeyset { keyDictionary in
    print("keys: " + keyDictionary.description)
    dispatchGroup.leave()
}

_ = dispatchGroup.wait(timeout: .now() + 5)
