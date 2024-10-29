import SwiftUI

struct EventDetailView: View {
    let event: Event

    var body: some View {
        switch event.kind {
        case .pendingMint:
            if let quote = event.bolt11MintQuote {
                MintView(quote: quote, pendingMintEvent: event)
            } else {
                Text("No quote set.")
            }
        case .mint:
            Text("mint event")
        case .send:
            Text("send")
        case .receive:
            Text("receive")
        case .pendingMelt:
            MeltView(quote: event.bolt11MeltQuote, pendingMeltEvent: event)
        case .melt:
            Text("melt")
        case .restore:
            Text("restore")
        case .drain:
            Text("drain")
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

// #Preview {
//    EventDetailView(event: Event)
// }
