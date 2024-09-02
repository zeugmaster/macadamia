//
//  TransactionDetailView.swift
//  macadamia
//
//  Created by zeugmaster on 07.01.24.
//

import SwiftUI

struct EventDetailView: View {
    let event: Event
    
    var body: some View {
        List {
            Section(header: Text("Base Event Properties")) {
                Text("ID: \(event.id.uuidString)")
                Text("Date: \(event.date, formatter: dateFormatter)")
                Text("Unit: \(unitString(event.unit))")
                Text("Short Description: \(event.shortDescription)")
            }
            
            Section(header: Text("Specific Event Properties")) {
                switch event {
                case let pendingMint as PendingMintEvent:
                    Text("Amount: \(pendingMint.amount)")
                    Text("Expiration: \(pendingMint.expiration, formatter: dateFormatter)")
                    
                case let mint as MintEvent:
                    Text("Amount: \(mint.amount)")
                    Text("Long Description: \(mint.longDescription)")
                    
                case let send as SendEvent:
                    Text("Amount: \(send.amount)")
                    Text("Long Description: \(send.longDescription)")
                    Text("Redeemed: \(send.redeemed ? "Yes" : "No")")
                    if let memo = send.memo {
                        Text("Memo: \(memo)")
                    }
                    
                case let receive as ReceiveEvent:
                    Text("Amount: \(receive.amount)")
                    Text("Long Description: \(receive.longDescription)")
                    if let memo = receive.memo {
                        Text("Memo: \(memo)")
                    }
                    
                case let pendingMelt as PendingMeltEvent:
                    Text("Amount: \(pendingMelt.amount)")
                    Text("Expiration: \(pendingMelt.expiration, formatter: dateFormatter)")
                    
                case let melt as MeltEvent:
                    Text("Amount: \(melt.amount)")
                    Text("Long Description: \(melt.longDescription)")
                    
                case let restore as RestoreEvent:
                    Text("Long Description: \(restore.longDescription)")
                    
                default:
                    Text("Unknown Event Type")
                }
            }
        }
    }
    
    private func unitString(_ unit: Unit) -> String {
        switch unit {
        case .sat: return "Satoshi"
        case .usd: return "USD"
        case .eur: return "EUR"
        case .mixed: return "Mixed"
        case .other: return "Other"
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    EventDetailView(event: SendEvent(amount: 21, longDescription: "this was a send event", redeemed: false, proofs: [], unit: .sat, shortDescription: "Melt"))
}
