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
                Text("Date: \(event.date, formatter: dateFormatter)")
                Text("Unit: \(unitString(event.unit))")
                Text("Short Description: \(event.shortDescription)")
            }
            
            Section(header: Text("Specific Event Properties")) {
                switch event.kind {
                case .pendingMint:
                    Text("pending mint")
                case .mint:
                    Text("mint event")
                case .send:
                    Text("send")
                case .receive:
                    Text("receive")
                case .pendingMelt:
                    Text("pending melt")
                case .melt:
                    Text("melt")
                case .restore:
                    Text("restore")
                case .drain:
                    Text("drain")
                }
            }
        }
    }
    
    private func unitString(_ unit: Unit) -> String {
        switch unit {
        case .sat: return "sat"
        case .usd: return "USD"
        case .eur: return "EUR"
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

//#Preview {
//    EventDetailView(event: Event)
//}
