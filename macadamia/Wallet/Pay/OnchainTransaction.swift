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
        /// Paid to the address, in sat.
        let amount: Int
        /// Mining fee the sender paid, in sat.
        let fee: Int?
        /// API root of the explorer that knows the transaction.
        let explorer: URL
    }
    
    enum Network: String {
        case mainnet = "Mainnet", testnet = "Testnet", regtest = "Regtest"
    }
    
    let address: String
    /// Minting: confirmations the mint waits for before issuing. Also sets the number of cubes.
    let requiredConfirmations: Int?
    let quoteID: String?
    
    @Environment(\.openURL) private var openURL
    @State private var firstTransactionState: TransactionState?
    @State private var lookupFailed = false
    @State private var showDetails = false
    @State private var copiedValue: String?
    
    /// `state`: a known state to show instead of looking one up (previews, callers that already fetched).
    init(address: String, requiredConfirmations: Int? = nil, quoteID: String? = nil, state: TransactionState? = nil) {
        self.address = address
        self.requiredConfirmations = requiredConfirmations
        self.quoteID = quoteID
        _firstTransactionState = State(initialValue: state)
    }
    
    private var cubeCount: Int { min(max(requiredConfirmations ?? 3, 1), 6) }
    
    // column 0 = mempool cube, 1 = divider, 2... = confirmation cubes, nil = none or beside the last cube
    private var arrowColumn: Int? {
        switch firstTransactionState?.block {
        case .mempool: 0
        case .confirmations(let n) where n <= cubeCount: 1 + max(n, 1)
        default: nil
        }
    }
    
    // more confirmations than cubes: chevron sits beside the last cube, pointing right
    private var pointsRight: Bool {
        if case .confirmations(let n) = firstTransactionState?.block { n > cubeCount } else { false }
    }
    
    private var isConfirmed: Bool {
        if case .confirmations(let n) = firstTransactionState?.block { n >= (requiredConfirmations ?? 1) } else { false }
    }
    
    private var stateTitle: String {
        if lookupFailed { return String(localized: "Explorer unreachable") }
        switch firstTransactionState?.block {
        case nil:
            return String(localized: "No transaction yet")
        case .mempool:
            return String(localized: "In the mempool")
        case .confirmations(let n):
            if let requiredConfirmations, n < requiredConfirmations {
                return String(localized: "\(n) of \(requiredConfirmations) confirmations")
            }
            return String(localized: "Confirmed")
        }
    }
    
    private var stateDetail: String? {
        if lookupFailed { return String(localized: "The block explorer did not answer.") }
        switch firstTransactionState?.block {
        case nil:
            return String(localized: "Waiting for a transaction to the address.")
        case .mempool:
            return String(localized: "Waiting for the first confirmation.")
        case .confirmations:
            guard let requiredConfirmations else { return nil }
            return isConfirmed
                ? String(localized: "The mint can issue ecash now.")
                : String(localized: "The mint issues ecash after \(requiredConfirmations) confirmations.")
        }
    }
    
    private var titleColor: Color {
        if lookupFailed { return .failureRed }
        return isConfirmed ? .successGreen : .primary
    }
    
    private var explorerWebURL: URL? {
        guard let state = firstTransactionState else { return nil }
        return state.explorer.deletingLastPathComponent().appending(path: "tx/\(state.txid)")
    }
    
    private var chevron: some View {
        Image(systemName: "chevron.up")
            .rotationEffect(.degrees(pointsRight ? 90 : 0))
            .font(.title3)
            .bold()
    }
    
    /// Label, middle-truncated value and a copy glyph on one line; the whole line copies.
    private func copyRow(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation { copiedValue = value }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { if copiedValue == value { copiedValue = nil } }
            }
        } label: {
            HStack {
                Text(label.uppercased())
                    .layoutPriority(1)
                Spacer()
                Text(value)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copiedValue == value
                      ? "rectangle.portrait.on.rectangle.portrait.fill"
                      : "rectangle.portrait.on.rectangle.portrait")
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
    
    private var cubes: some View {
        Grid(verticalSpacing: 12) {
            GridRow {
                Image(systemName: "cube")
                Rectangle()
                    .frame(width: 2)
                    .gridCellUnsizedAxes(.vertical)
                ForEach(0..<cubeCount, id: \.self) { index in
                    Image(systemName: "cube.fill")
                        // Unconditional overlay: wrapping it in `if` drops the alignment guide and draws over the cube.
                        .overlay(alignment: .trailing) {
                            chevron
                                .opacity(pointsRight && index == cubeCount - 1 ? 1 : 0)
                                .alignmentGuide(.trailing) { $0[.leading] - 8 }
                        }
                }
            }
            GridRow {
                ForEach(0..<(cubeCount + 2), id: \.self) { column in
                    chevron.opacity(column == arrowColumn ? 1 : 0)
                }
            }
        }
        .font(.title)
        .animation(.default, value: firstTransactionState?.block)
        .accessibilityHidden(true)
    }
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    cubes
                    VStack(spacing: 6) {
                        Text(stateTitle)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(titleColor)
                        if let stateDetail {
                            Text(stateDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }
            
            Section {
                // One row keeps the lines tight, like the Mint/Status block in DepositQuoteView.
                VStack(spacing: 8) {
                    HStack {
                        Text("Network".uppercased())
                        Spacer()
                        Text(Self.network(for: address)?.rawValue ?? String(localized: "Unknown"))
                    }
                    if let requiredConfirmations {
                        HStack {
                            Text("Confirmations required".uppercased())
                            Spacer()
                            Text("\(requiredConfirmations)")
                        }
                    }
                    if let state = firstTransactionState {
                        if case .confirmations(let n) = state.block {
                            HStack {
                                Text("Confirmations".uppercased())
                                Spacer()
                                Text("\(n)")
                            }
                        }
                        HStack {
                            Text("Amount".uppercased())
                            Spacer()
                            AmountView(amount: state.amount, unit: .sat)
                        }
                        if let fee = state.fee {
                            HStack {
                                Text("Network Fee".uppercased())
                                Spacer()
                                AmountView(amount: fee, unit: .sat)
                            }
                        }
                    }
                }
                
                Button {
                    withAnimation { showDetails.toggle() }
                } label: {
                    HStack {
                        Text(showDetails ? "Hide details" : "Show details")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                
                if showDetails {
                    VStack(spacing: 8) {
                        if let txid = firstTransactionState?.txid {
                            copyRow(String(localized: "Transaction ID"), txid)
                        }
                        if let quoteID {
                            copyRow(String(localized: "Quote ID"), quoteID)
                        }
                        copyRow(String(localized: "Address"), address)
                    }
                }
            }
            .listRowBackground(EmptyView())
            .listRowSeparator(.hidden)
            .font(.footnote)
            
            if let explorerWebURL {
                Section {
                    // Plain button like DepositQuoteView's actions: the app's accent color is white, so a tinted Link vanishes.
                    Button {
                        openURL(explorerWebURL)
                    } label: {
                        Label("View in Block Explorer", systemImage: "safari")
                            .labelStyle(.titleAndIcon)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard firstTransactionState == nil else { return }   // a known state was handed in
            do {
                if let first = try await Self.getTransactionStates(for: address).first {
                    firstTransactionState = first
                }
            } catch {
                lookupFailed = true
            }
        }
    }
    
    static func network(for address: String) -> Network? {
        let prefix = address.lowercased()   // base58 is case-sensitive, so only the check is lowercased
        if prefix.hasPrefix("bcrt1") { return .regtest }
        if prefix.hasPrefix("bc1") || prefix.hasPrefix("1") || prefix.hasPrefix("3") { return .mainnet }
        if prefix.hasPrefix("tb1") || prefix.hasPrefix("m") || prefix.hasPrefix("n") || prefix.hasPrefix("2") { return .testnet }
        return nil
    }
    
    /// Esplora API roots that can know the address. The test networks share prefixes, so all three are asked.
    /// Empty for unknown networks: only quote polling reports then.
    static func explorerAPIURLs(for address: String) -> [URL] {
        let hosts: [String] = switch network(for: address) {
        case .mainnet: ["mempool.space"]
        case .testnet: ["mempool.space/testnet4", "mempool.space/testnet", "mempool.space/signet"]
        case .regtest: ["mempool.regtest.macadamia.cash"]
        case nil: []
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
            struct Output: Decodable { let scriptpubkey_address: String?, value: Int }
            let txid: String, fee: Int?, status: Status, vout: [Output]
        }
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: api.appending(path: "address/\(address)/txs"), timeoutInterval: 10))
        let funding = try JSONDecoder().decode([Tx].self, from: data).compactMap { tx -> (tx: Tx, amount: Int)? in
            let paid = tx.vout.filter { $0.scriptpubkey_address?.lowercased() == address.lowercased() }.map(\.value).reduce(0, +)
            return paid > 0 ? (tx, paid) : nil
        }
        guard !funding.isEmpty else { return [] }
        let (tipData, _) = try await URLSession.shared.data(for: URLRequest(url: api.appending(path: "blocks/tip/height"), timeoutInterval: 10))
        guard let tip = Int(String(decoding: tipData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.cannotParseResponse)
        }
        return funding.map { tx, amount in
            // max(1): the tip can lag a block the explorer already indexed
            TransactionState(txid: tx.txid,
                             block: tx.status.block_height.map { .confirmations(max(1, tip - $0 + 1)) } ?? .mempool,
                             amount: amount, fee: tx.fee, explorer: api)
        }
    }
}

#if DEBUG
private extension OnchainTransaction.TransactionState {
    static func preview(_ block: Block) -> Self {
        .init(txid: "5f0b5a4a6a1d7c8e4f12a3b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9", block: block,
              amount: 25_000, fee: 312, explorer: URL(string: "https://mempool.space/api")!)
    }
}

private func previewTransaction(_ block: OnchainTransaction.TransactionState.Block) -> some View {
    let quote = DepositQuotePreview.onchain
    return NavigationStack {
        OnchainTransaction(address: quote.request, requiredConfirmations: quote.option.requiredConfirmations,
                           quoteID: quote.quoteID, state: .preview(block))
    }
}

#Preview("Mempool") { previewTransaction(.mempool) }
#Preview("Confirming") { previewTransaction(.confirmations(2)) }
#Preview("Confirmed") { previewTransaction(.confirmations(7)) }

// Live lookup against the regtest explorer: the waiting state when it answers, the unreachable one when it does not.
#Preview("Live Regtest") {
    NavigationStack {
        OnchainTransaction(address: "bcrt1qdvk49syy2mml59w8sa8qw55rswrf00hpl8nu38", requiredConfirmations: 3)
    }
}
#endif
