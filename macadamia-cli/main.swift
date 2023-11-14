//
//  main.swift
//  macadamia-cli
//
//  Created by Dario Lass on 09.11.23.
//

import Foundation
import secp256k1

let dispatchGroup = DispatchGroup()

func start() {
    
    let wallet = Wallet()
    
    wallet.updateMints {mints in
        print("downloaded \(mints.count) mint(s)")
        
        wallet.mint(amount: 21) { prResult in
            print(prResult)
            print("press enter when invoice is payed")
            _ = readLine()
        } mintCompletion: { mintResult in
            print(mintResult)
            dispatchGroup.leave()
        }

        
    }
}

dispatchGroup.enter()
start()
dispatchGroup.wait()

//getMintKeyset { keyDictionary in
//    //print("keys: " + keyDictionary.description)
//    var amount:Int = 0
//    while amount == 0 {
//        print("Please enter amount to request: ", terminator: "")
//        if let input = readLine(), let inputAmount = Int(input) {
//            amount = inputAmount
//        } else {
//            print("Invalid input, try again")
//        }
//    }
//    requestMint(amount: amount) { paymentReq in
//        print(paymentReq ?? "nil")
//        print("when you have paid the invoice, press enter to proceed")
//        _ = readLine()
//        requestBlindedPromises(amount: amount, payReq: paymentReq!) { promises in
//            //print("promises: \(promises)")
//            let unblindedPromises = unblindPromises(promises: promises, mintPublicKeys: keyDictionary)
//            let tokenString = serializeTokens(tokens: unblindedPromises)
//            print(tokenString)
//            // end execution
//            dispatchGroup.leave()
//        }
//    }
//}
