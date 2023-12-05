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
    
    let lnInvoice = "lnbc1234560n1pjk7kyrpp53m3grlnj3pt3qflt4xlh0792wp57ns76tca0ml73snkpl6wwj2yscqpjsp59nhdpp03gh7650efsjg4ukjrt7n89czadql9kjwf585sss95eg7q9q7sqqqqqqqqqqqqqqqqqqqsqqqqqysgqdqs09jk2etvd3kx7mm0mqz9gxqyjw5qrzjqwryaup9lh50kkranzgcdnn2fgvx390wgj5jd07rwr3vxeje0glcllezhk2zechxl5qqqqlgqqqqqeqqjq478hj38clvjzc4jvnsuu3w4xdrp28mmlha86rt7jz4v54qxd5vzrd8aqy8vlz654rz9w9x8uyw7taurpg6fcj85e4excxwuug9y5m5qpcfuxa7"
    print(PaymentRequest.satAmountFromEncodedPR(pr: lnInvoice))
    
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
