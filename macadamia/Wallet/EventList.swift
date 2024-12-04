import SwiftUI
import SwiftData

struct EventList: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var allEvents: [Event]
    
    var visibleEventsForActiveWallet: [Event] {
        allEvents.filter({ $0.wallet == wallets.first && $0.visible == true })
                 .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        List {
            ForEach(visibleEventsForActiveWallet) { event in
                EventListRow(event: event)
            }
        }
    }
}

struct EventListRow: View {
    
    let event: Event
    
    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            VStack {
                HStack {
                    Text(event.shortDescription)
                    Text(event.date.formatted())
                    if let memo = event.memo {
                        Text(memo)
                    }
                }
                HStack {
                    if let mints = event.mints, mints.count == 1 {
                        Text("\(Image(systemName: "building.columns.fill")) \(readableName(mint: mints.first!))")
                    }
                    if let amount = event.amount {
                        switch event.kind {
                        case .send, .drain, .melt, .pendingMelt:
                            Text(amountDisplayString(amount, unit: event.unit, negative: true))
                        case .receive, .mint, .restore, .pendingMint:
                            Text(amountDisplayString(amount, unit: event.unit, negative: false))
                        }
                    }
                }
            }
            .lineLimit(1)
        }
    }
    
    private func readableName(mint: Mint) -> String {
        mint.nickName ?? mint.url.host() ?? mint.url.absoluteString
    }
}

#Preview {
    EventList()
}
