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
  
    Task {
        try await wallet.updateMints()
    }
    
    print(convertKeysetID(keysetID: "bCPftxOiyYyz"))
    print(convertHexKeysetID(keysetID: "007c3ce974db912b"))
        
    print("""
            Welcome to macadamia. Would you like to
            - mint
            - send
            - receive
            - melt 
            - restore or
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
        case "restore":
            restore()
        default:
            print("invalid input. please try again")
            askInput()
        }
    }
        
    func startMint() {
        Task {
            let chosenAmount = numberInput()
            let pr = try await wallet.getQuote(from:wallet.database.mints[0], for:chosenAmount)
            print(pr)
            print("press enter when invoice is payed")
            _ = readLine()
            try await wallet.requestMint(from: wallet.database.mints[0], for: pr, with: chosenAmount)
            dispatchGroup.leave()
        }
    }
    
    func send() {
        Task {
            let amount = numberInput()
            do {
                let token = try await wallet.sendTokens(from:wallet.database.mints[0], amount:amount)
                print("here is your token: \(token)")
            } catch {
                print(error)
            }
            dispatchGroup.leave()
        }
    }
    
    func receive() {
        print("paste your token")
        let token = readLine()!
        Task {
            do {
                try await wallet.receiveToken(tokenString: token)
            } catch {
                print("whoops! error: \(error)")
            }
            dispatchGroup.leave()
        }
    }
    
    func melt() {
        Task {
            print("enter the bolt11 invoice and press enter")
            let invoice = readLine()!
            do {
                let paid = try await wallet.melt(mint: wallet.database.mints[0], invoice: invoice)
                print(paid)
            } catch {
                print(error)
            }
        }
    }
    
    func restore() {
        print("please enter new mnemonic:")
        let input = readLine()!
        Task {
            do {
                try await wallet.restoreWithMnemonic(mnemonic: input)
            } catch {
                print(error)
            }
            dispatchGroup.leave()
        }
    }
    
    @Sendable func numberInput() -> Int {
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
