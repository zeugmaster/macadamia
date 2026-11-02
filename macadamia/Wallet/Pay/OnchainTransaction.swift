//
//  OnchainTXView.swift
//  macadamia
//
//  Created by zm on 02.11.26.
//

import SwiftUI

struct OnchainTransaction: View {
    
    public struct TransactionState {
        public enum Block {
            case mempool
            case confirmations(Int)
        }
        
        let txid: String
        let block: Block
    }
    
    let address: String
    
    @State private var firstTransactionState: TransactionState?
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "cube")
                Rectangle()
                    .frame(width: 2, height: 30)
                Image(systemName: "cube.fill")
                Image(systemName: "cube.fill")
                Image(systemName: "cube.fill")
            }
            .font(.title)
            Spacer()
        }
    }
    
    static public func getTransactionStates(for address: String) async throws -> [TransactionState] {
        // replace with real lookup, needs support for different known block explorers.
        // for regtest use https://mempool.regtest.macadamia.cash/api
        return [TransactionState(txid: "bc1asdfasdfasdf",
                                 block: .confirmations(2))]
    }
}

#Preview {
    OnchainTransaction(address: "gabagooool")
}
