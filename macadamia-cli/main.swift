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
  
    wallet.updateMints { result in
        
    }
    
    print(convertKeysetID(keysetID: "I2yN+iRYfkzT"))
    
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
            melt()
        case "balance":
            print("not supported yet")
        default:
            print("invalid input. please try again")
            askInput()
        }
    }
        
    func startMint() {
        wallet.mint(amount: numberInput(), mint: wallet.database.mints[0]) { prResult in
            print(prResult)
            print("press enter when invoice is payed")
            _ = readLine()
        } mintCompletion: { mintResult in
            //print(mintResult)
            dispatchGroup.leave()
        }
    }
    
    func send() {
        wallet.sendTokens(mint: wallet.database.mints[0], amount: numberInput()) { result in
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
            dispatchGroup.leave()
        }
    }
    
    func melt() {
        print("enter the bolt11 invoice and press enter")
        let invoice = readLine()!
        //check validity
        wallet.melt(mint: wallet.database.mints[0], invoice: invoice) { meltReqResult in
            switch meltReqResult {
            case .success():
                print("yyyyeeeeaaaahhh")
            case .failure(let error):
                print("something went wrong: \(error)")
            }
            dispatchGroup.leave()
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
