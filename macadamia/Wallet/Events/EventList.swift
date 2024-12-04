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
    
    var readableMintName: String {
        if let mints = event.mints {
            if mints.isEmpty {
                return ""
            } else if mints.count == 1 {
                if let mint = mints.first {
                    return mint.nickName ?? mint.url.host() ?? mint.url.absoluteString
                }
            } else {
                return "Multiple"
            }
        }
        return ""
    }
    
    var amountString: String {
        amountDisplayString(event.amount ?? 0, unit: event.unit)
    }
    
    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            RowLayout(mintLabel: readableMintName,
                      description: event.shortDescription,
                      amountString: amountString,
                      dateLabel: event.date.formatted(),
                      memo: event.memo)
        }
    }
}

struct RowLayout: View {
    
    let mintLabel: String
    let description: String
    let amountString: String
    let dateLabel: String
    
    let memo: String?
    
    var body: some View {
        VStack {
            HStack {
                Text("\(Image(systemName:"building.columns.fill")) \(mintLabel)")
                Spacer()
                Text(dateLabel)
            }
            .font(.caption)
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            HStack {
                if let memo, !memo.isEmpty {
                    Text(description + ": \(memo)")
                } else {
                    Text(description)
                }
                Spacer()
                Text(amountString)
                    .monospaced()
                    .fontWeight(.semibold)
            }
        }
        .lineLimit(1)
    }
}

#Preview {
    RowLayout(mintLabel: "mint.macadamia.cash",
              description: "Send",
              amountString: "- 420 sat",
              dateLabel: "6.2.24, 14:32", memo: "tenks u")
}
