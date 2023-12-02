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
    
    let seed = "7aab38b466db2bdef68fbe4068fa7a2034602832c95252bcf9c0bacdd4132249c9b3e881390568333b32ebff738c4daa9793252cfd9fb840d38f81f277f6738f"
    print(childPrivateKeyForDerivationPath(seed: seed, derivationPath: "m/1/1'/1"))
  
    print("""
            Welcome to macadamia. Would you like to
            - mint
            - send
            - receive
            - melt or
            - balance?
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
        case "balance":
            print("not supported yet")
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
    
    func queryBalance() {
        
    }
}

dispatchGroup.enter()
start()
dispatchGroup.wait()
