//
//  ProofDataView.swift
//  macadamia
//
//  Created by zm on 18.04.25.
//

import SwiftUI
import SwiftData

struct ProofDataView: View {
    
    var proof: Proof
    
    var body: some View {
        List {
            Section("Basic Information") {
                CopyableRow(label: "Proof ID", value: proof.proofID.uuidString)
                CopyableRow(label: "Amount", value: "\(proof.amount) \(proof.unit.rawValue)")
                CopyableRow(label: "State", value: proof.state.description)
                CopyableRow(label: "Created", value: proof.dateCreated.formatted())
            }
            
            Section("Cryptographic Data") {
                CopyableRow(label: "C (Commitment)", value: proof.C)
                CopyableRow(label: "Secret", value: proof.secret)
                CopyableRow(label: "Keyset ID", value: proof.keysetID)
            }
            
            if let dleq = proof.dleq {
                Section("DLEQ Proof") {
                    CopyableRow(label: "e", value: dleq.e)
                    CopyableRow(label: "s", value: dleq.s)
                }
            }
            
            Section("Fee Information") {
                CopyableRow(label: "Input Fee PPK", value: String(proof.inputFeePPK))
            }
            
            if let mint = proof.mint {
                Section("Mint Information") {
                    CopyableRow(label: "Mint Name", value: mint.displayName)
                    CopyableRow(label: "Mint URL", value: mint.url.absoluteString)
                }
            }
            
            if let wallet = proof.wallet {
                Section("Wallet Information") {
                    CopyableRow(label: "Wallet Name", value: wallet.name ?? "Unnamed Wallet")
                }
            }
        }
        .navigationTitle("Proof Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CopyableRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .lineLimit(1)
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = value
            }) {
                Text("Copy") + Text(" ") + Text(LocalizedStringKey(label))
                Image(systemName: "doc.on.clipboard")
            }
        }
        .onTapGesture(count: 2) {
            UIPasteboard.general.string = value
        }
    }
}

extension Proof.State {
    var description: String {
        switch self {
        case .valid:
            return "Valid"
        case .pending:
            return "Pending"
        case .spent:
            return "Spent"
        }
    }
}
