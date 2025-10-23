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
    
    var body: some View {
        List {
            HStack {
                Text("Minted at: ")
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
                TokenText(text: text)
                    .frame(idealHeight: 70)
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = text
                        }) {
                            Text("Copy")
                            Spacer()
                            Image(systemName: "clipboard")
                        }
                    }
            }
        }
    }
}

struct MeltEventSummary: View {
    let events: [Event]
    
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
            
            if isMultiPath {
                Section("Payment Parts") {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Part \(index + 1)")
                                    .font(.headline)
                                Spacer()
                                Text("\(event.amount ?? 0) sats")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let mint = event.mints?.first {
                                HStack {
                                    Text("Mint:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(mint.displayName)
                                        .font(.caption)
                                }
                            }
                            
                            if let preImage = event.preImage {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Preimage:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(preImage)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .contextMenu {
                                            Button(action: {
                                                UIPasteboard.general.string = preImage
                                            }) {
                                                Text("Copy Preimage")
                                                Image(systemName: "doc.on.clipboard")
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if index < events.count - 1 {
                            Divider()
                        }
                    }
                }
            } else {
                // Single payment
                if let mint = events.first?.mints?.first {
                    Section("Payment Details") {
                        HStack {
                            Text("Mint")
                            Spacer()
                            Text(mint.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if let preImage = events.first?.preImage {
                    Section("Payment Proof") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preimage")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TokenText(text: preImage)
                                .frame(idealHeight: 70)
                                .contextMenu {
                                    Button(action: {
                                        UIPasteboard.general.string = preImage
                                    }) {
                                        Text("Copy Preimage")
                                        Image(systemName: "doc.on.clipboard")
                                    }
                                }
                        }
                    }
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
        .onAppear {
            print(String(describing: token))
        }
    }
    
    private func checkTokenState(with proofs:[Proof]) {
        guard let firstMint = proofs.first?.mint,
              proofs.allSatisfy({ $0.mint == firstMint }) else {
            logger.error("function to check proofs can not handle proofs from different mints!")
            return
        }
        
        Task {
            let result = try await CashuSwift.check(proofs.sendable(), mint: CashuSwift.Mint(firstMint))
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
                        Text("\(showDetails ? "Hide" : "Show") details")
                            .opacity(0.8)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                    }
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
