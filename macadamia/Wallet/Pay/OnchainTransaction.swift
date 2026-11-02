//
//  OnchainTXView.swift
//  macadamia
//
//  Created by zm on 02.11.26.
//

import SwiftUI

struct OnchainTransaction: View {
    
    public struct TransactionState {
        public enum Block: Equatable {
            case mempool
            case confirmations(Int)
        }
        
        let txid: String
        let block: Block
    }
    
    let address: String
    
    @State private var firstTransactionState: TransactionState?
    
    // column 0 = mempool cube, 1 = divider, 2...4 = confirmations 1...3, nil = none or beside the last cube
    private var arrowColumn: Int? {
        switch firstTransactionState?.block {
        case .mempool: 0
        case .confirmations(let n) where n <= 3: 1 + max(n, 1)
        default: nil
        }
    }
    
    // more than 3 confirmations: chevron sits beside the last cube, pointing right
    private var pointsRight: Bool {
        if case .confirmations(let n) = firstTransactionState?.block { n > 3 } else { false }
    }
    
    private var chevron: some View {
        Image(systemName: "chevron.up")
            .rotationEffect(.degrees(pointsRight ? 90 : 0))
            .font(.title3)
            .bold()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Grid(verticalSpacing: 12) {
                GridRow {
                    Image(systemName: "cube")
                    Rectangle()
                        .frame(width: 2)
                        .gridCellUnsizedAxes(.vertical)
                    Image(systemName: "cube.fill")
                    Image(systemName: "cube.fill")
                    Image(systemName: "cube.fill")
                        .overlay(alignment: .trailing) {
                            chevron
                                .opacity(pointsRight ? 1 : 0)
                                .alignmentGuide(.trailing) { $0[.leading] - 8 }
                        }
                }
                GridRow {
                    ForEach(0..<5) { column in
                        chevron.opacity(column == arrowColumn ? 1 : 0)
                    }
                }
            }
            .font(.title)
            .animation(.default, value: firstTransactionState?.block)
            Spacer()
        }
        .task {
            firstTransactionState = try? await Self.getTransactionStates(for: address).first
        }
    }
    
    /// Esplora API roots that can know the address, chosen by its network prefix. The test networks
    /// share prefixes, so all three are asked. Empty for unknown networks: only quote polling reports then.
    static func explorerAPIURLs(for address: String) -> [URL] {
        let prefix = address.lowercased()   // base58 is case-sensitive, so only the check is lowercased
        let hosts: [String]
        if prefix.hasPrefix("bc1") || prefix.hasPrefix("1") || prefix.hasPrefix("3") {
            hosts = ["mempool.space"]
        } else if prefix.hasPrefix("tb1") || prefix.hasPrefix("m") || prefix.hasPrefix("n") || prefix.hasPrefix("2") {
            hosts = ["mempool.space/testnet4", "mempool.space/testnet", "mempool.space/signet"]
        } else if prefix.hasPrefix("bcrt1") {
            hosts = ["mempool.regtest.macadamia.cash"]
        } else {
            return []
        }
        return hosts.compactMap { URL(string: "https://\($0)/api") }
    }
    
    /// True once an explorer lists a transaction funding the address, in the mempool or confirmed.
    static func explorerSawPayment(to address: String) async -> Bool {
        struct Stats: Decodable { let funded_txo_count: Int }
        struct Address: Decodable { let chain_stats: Stats, mempool_stats: Stats }
        for api in explorerAPIURLs(for: address) {
            // Short timeout: an unreachable explorer must not hold up polling the mint.
            guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: api.appending(path: "address/\(address)"), timeoutInterval: 5)),
                  let stats = try? JSONDecoder().decode(Address.self, from: data) else { continue }
            if stats.chain_stats.funded_txo_count + stats.mempool_stats.funded_txo_count > 0 { return true }
        }
        return false
    }
    
    /// Transactions paying the address, newest first, from the first explorer that knows of any. Empty: no tx found.
    static public func getTransactionStates(for address: String) async throws -> [TransactionState] {
        for api in explorerAPIURLs(for: address) {
            let states = try await transactionStates(at: api, for: address)
            if !states.isEmpty { return states }
        }
        return []
    }
    
    /// Esplora lookup against one API root. Spends from the address are dropped; confirmations count from the tip.
    static func transactionStates(at api: URL, for address: String) async throws -> [TransactionState] {
        struct Tx: Decodable {
            struct Status: Decodable { let block_height: Int? }
            struct Output: Decodable { let scriptpubkey_address: String? }
            let txid: String, status: Status, vout: [Output]
        }
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: api.appending(path: "address/\(address)/txs"), timeoutInterval: 10))
        let txs = try JSONDecoder().decode([Tx].self, from: data)
            .filter { tx in tx.vout.contains { $0.scriptpubkey_address?.lowercased() == address.lowercased() } }
        guard !txs.isEmpty else { return [] }
        let (tipData, _) = try await URLSession.shared.data(for: URLRequest(url: api.appending(path: "blocks/tip/height"), timeoutInterval: 10))
        guard let tip = Int(String(decoding: tipData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.cannotParseResponse)
        }
        return txs.map { tx in
            // max(1): the tip can lag a block the explorer already indexed
            TransactionState(txid: tx.txid, block: tx.status.block_height.map { .confirmations(max(1, tip - $0 + 1)) } ?? .mempool)
        }
    }
}

#Preview {
    OnchainTransaction(address: "gabagooool")
}
