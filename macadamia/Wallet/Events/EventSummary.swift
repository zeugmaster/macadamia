//
//  EventSummary.swift
//  macadamia
//
//  Created by zm on 24.08.25.
//

import SwiftUI
import CashuSwift
import SwiftData

struct MintEventSummary: View {
    let event: Event
    @State private var showDetails = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Issued at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                HStack {
                    Text("Amount: ")
                    Spacer()
                    Text(String(event.amount ?? 0))
                }
                HStack {
                    Text("Unit: ")
                    Spacer()
                    Text(event.unit.rawValue)
                }
                if let text = event.bolt11MintQuote?.request {
                    CopyableRow(label: "Bolt11 Invoice", value: text)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        if showDetails {
                            Text("Hide details")
                        } else {
                            Text("Show details")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                    }
                    .opacity(0.8)
                }
                
                if showDetails {
                    CopyableRow(label: "Quote ID", value: event.bolt11MintQuote?.quote ?? "nil")
                }
            }
        }
    }
}

struct MeltEventSummary: View {
    let events: [Event]
    
    @State private var showDetails = false
    
    var totalAmount: Int {
        events.compactMap { $0.amount }.reduce(0, +)
    }
    
    var isMultiPath: Bool {
        events.count > 1
    }
    
    var body: some View {
        List {
            Section("Payment Summary") {
                HStack {
                    Text("Payment Date")
                    Spacer()
                    Text(events.first?.date.formatted() ?? "")
                }
                
                HStack {
                    Text("Total Amount")
                    Spacer()
                    Text("\(totalAmount) sats")
                }
                
                HStack {
                    Text("Payment Type")
                    Spacer()
                    HStack(spacing: 4) {
                        if isMultiPath {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption)
                        }
                        Text(isMultiPath ? "Multi-Path Payment" : "Single Payment")
                    }
                    .foregroundStyle(.secondary)
                }
                
                if isMultiPath {
                    HStack {
                        Text("Payment Parts")
                        Spacer()
                        Text("\(events.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                ForEach(events) { event in
                    HStack {
                        Text(event.mints?.first?.displayName ?? "nil")
                        Spacer()
                        Text(amountDisplayString(event.amount ?? 0, unit: .sat))
                            .monospaced()
                    }
                    .lineLimit(1)
                }
            } header: {
                HStack {
                    Text("Mint")
                    Spacer()
                    Text("Amount")
                }
            }
            
            Section {
                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        if showDetails {
                            Text("Hide details")
                        } else {
                            Text("Show details")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                    }
                    .opacity(0.8)
                }
                
                if showDetails {
                    ForEach(events) { event in
                        CopyableRow(label: (event.mints?.first?.displayName ?? "nil") + " - Quote ID", value: event.bolt11MeltQuote?.quote ?? "nil")
                    }
                    CopyableRow(label: "Preimage", value: events.first?.preImage ?? "nil")
                }
            }
        }
        .navigationTitle(isMultiPath ? "Multi-Path Payment" : "Payment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SendEventView: View {
    var event: Event
    
    @State private var tokenState: TokenState = .unknown
    
    enum TokenState {
        case unknown
        case spent
        case pending
    }
    
    var token: CashuSwift.Token? {
        if let token = event.token { return token }
        
        if let proofs = event.proofs,
           !proofs.isEmpty,
           let mints = event.mints,
           mints.count == 1 {
            
            return CashuSwift.Token(proofs: [mints.first!.url.absoluteString: proofs],
                                    unit: Unit.sat.rawValue,
                                    memo: event.memo)
        }
        return nil
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Created at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                if let mint = event.mints?.first {
                    HStack {
                        Text("Mint: ")
                        Spacer()
                        Text(mint.displayName)
                    }
                }
                if let memo = event.memo, !memo.isEmpty {
                    HStack {
                        Text("Memo: ")
                        Spacer()
                        Text(memo)
                    }
                }
                if let proofs = event.proofs {
                        switch tokenState {
                        case .unknown:
                            Button {
                                checkTokenState(with: proofs)
                            } label: {
                                HStack {
                                    Text("Check token state?")
                                    Spacer()
                                    Image(systemName: "arrow.counterclockwise")
                                }
                            }
                        case .spent:
                            HStack {
                                Text("Token was redeemed.")
                                Spacer()
                                Image(systemName: "checkmark.circle")
                            }
                        case .pending:
                            HStack {
                                Text("Token is pending.")
                                Spacer()
                                Image(systemName: "hourglass")
                            }
                        }
                    }
            }
            
            if let token {
                TokenShareView(token: token)
            }
        }
    }
    
    private func checkTokenState(with proofs:[Proof]) {
        
        guard let proofs = token?.proofsByMint.first?.value,
              let mintURLString = token?.proofsByMint.first?.key,
              let url = URL(string: mintURLString) else {
            return
        }
        
        Task {
            let result = try await CashuSwift.check(proofs, url: url)
            await MainActor.run {
                withAnimation {
                    if result.allSatisfy({ $0 == CashuSwift.Proof.ProofState.unspent }) {
                        tokenState = .pending
                    } else {
                        tokenState = .spent
                    }
                }
            }
        }
    }
}

struct ReceiveEventSummary: View {
    let event: Event
    
    var body: some View {
        List {
            HStack {
                Text("Received at: ")
                Spacer()
                Text(event.date.formatted())
            }
            HStack {
                Text("Amount: ")
                Spacer()
                Text(String(event.amount ?? 0))
            }
            HStack {
                Text("Unit: ")
                Spacer()
                Text(event.unit.rawValue)
            }
        }
    }
}

struct RestoreEventSummary: View {
    let event: Event
    
    var body: some View {
        List {
            HStack {
                Text("Restored at: ")
                Spacer()
                Text(event.date.formatted())
            }
            Text(event.longDescription ?? "No description.")
        }
    }
}

struct TransferEventSummary: View {
    let event: Event
    @State private var showDetails = false
    
    var body: some View {
        List {
            Section {
                TransferMintLabel(from: event.mints?[0].displayName ?? "Not found",
                                  to: event.mints?[1].displayName ?? "Not found")
            } header: {
                Text("Mints")
            }
            
            Section {
                Text("\(String(event.amount ?? 0)) \(event.unit.rawValue)")
                    .monospaced()
            } header: {
                Text("Amount")
            }
            
            Section {
                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        if showDetails {
                            Text("Hide details")
                        } else {
                            Text("Show details")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                    }
                    .opacity(0.8)
                }
            }
            
            if showDetails {
                Section {
                    CopyableRow(label: "Quote ID", value: event.bolt11MeltQuote?.quote ?? "nil")
                    CopyableRow(label: "Payment Preimage", value: event.bolt11MeltQuote?.paymentPreimage ?? "nil")
                    CopyableRow(label: "Fee Reserve", value: String(event.bolt11MeltQuote?.feeReserve ?? 0))
                } header: {
                    Text("Payment")
                }
                
                Section {
                    CopyableRow(label: "Quote ID", value: event.bolt11MintQuote?.quote ?? "nil")
                } header: {
                    Text("Ecash Created")
                }
            }
        }
    }
}
