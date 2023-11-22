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
  
    wallet.updateMints { mints in
        print("downloaded \(mints.count) mint(s)")
    }
  
    print("""
            Welcome to macadamia. Would you like to
            - mint
            - send
            - receive or
            - melt?
            """)
    askInput()
    
    func askInput() {
        let input = readLine()
        switch input {
        case "mint":
            startMint()
        case "send":
            send()
        case "receive":
            receive()
        case "melt":
            print("not yet supported")
        default:
            print("invalid input. please try again")
            askInput()
        }
    }
    
    #warning("make sure to call dispatchGroup.leave() in every scenario")
    
    func startMint() {
        wallet.mint(amount: numberInput()) { prResult in
            print(prResult)
            print("press enter when invoice is payed")
            _ = readLine()
        } mintCompletion: { mintResult in
            //print(mintResult)
            dispatchGroup.leave()
        }
    }
    
    func send() {
        wallet.sendTokens(amount: numberInput()) { result in
            switch result {
            case.success(let tokenString):
                print("here is your token: \(tokenString)")
            case .failure(let error):
                print(error)
            }
            dispatchGroup.leave()
        }
    }
    
    func receive() {
        print("paste your token")
        let token = readLine()!
        wallet.receiveTokens(tokenString: token) { result in
            print(result)
        }
    }
    
    func numberInput() -> Int {
        var amount = 0
        while amount == 0 {
            print("Please enter amount: ", terminator: "")
            if let input = readLine(), let inputAmount = Int(input) {
                amount = inputAmount
            } else {
                print("Invalid input, try again")
            }
        }
        return amount
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
