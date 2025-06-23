import SwiftUI
import SwiftData

struct MinimalEventList: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    // query events (transactions) if they are visible and in chronological order
    @Query(filter: #Predicate { event in
        event.visible == true
    },
    sort: [SortDescriptor(\Event.date, order: .reverse)]) private var events: [Event]
    
    private let shadowHeight: CGFloat = 10
    
    var activeWallet:Wallet? {
        wallets.first
    }
    
    var sortedEventsForActiveWallet: [Event] {
        events.filter({ $0.wallet == activeWallet })
    }
    
    var body: some View {
        List {
            if sortedEventsForActiveWallet.isEmpty {
                Text("No transactions yet.")
            } else {
                ForEach(sortedEventsForActiveWallet.prefix(5)) { event in
                    TransactionListRow(event: event)
                }
                if sortedEventsForActiveWallet.count > 5 {
                    NavigationLink("Show All", destination: EventList())
                        .listRowBackground(Color.clear)
                        .padding(.leading, 27)
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
            LinearGradient(gradient: Gradient(colors: [.black, Color.black.opacity(0)]),
                           startPoint: .top,
                           endPoint: .bottom)
            .frame(height: shadowHeight)
        }
        .safeAreaInset(edge: .bottom) {
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), .black]),
                           startPoint: .top,
                           endPoint: .bottom)
            .frame(height: shadowHeight)
        }
        .padding(.horizontal, 30)
    }
}

struct TransactionListRow: View {
    var event: Event

    init(event: Event) {
        self.event = event
    }

    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            VStack(alignment: .leading) {
                HStack {
                    Group {
                        switch event.kind {
                        case .pendingMelt, .pendingMint:
                            Image(systemName: "hourglass")
                        case .pendingReceive:
                            Image(systemName: "lock")
                        case .mint, .receive:
                            Image(systemName: "arrow.down.left")
                        case .melt, .send:
                            Image(systemName: "arrow.up.right")
                        case .restore:
                            Image(systemName: "clock.arrow.circlepath")
                        case .drain:
                            Image(systemName: "arrow.uturn.right")
                        }
                    }
                    .opacity(0.8)
                    .font(.caption)
                    .frame(width: 20, alignment: .leading)
                    Group {
                        Text(event.shortDescription)
                        if let memo = event.memo, !memo.isEmpty {
                            Text(memo)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amount = event.amount {
                            switch event.kind {
                            case .send, .drain, .melt, .pendingMelt:
                                Text(amountDisplayString(amount, unit: event.unit, negative: true))
                                    .foregroundStyle(.secondary)
                            case .receive, .pendingReceive, .mint, .restore, .pendingMint:
                                Text(amountDisplayString(amount, unit: event.unit, negative: false))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.body)
                }
                
                if let mints = event.mints, !mints.isEmpty {
                    HStack() {
                        Spacer().frame(width: 28)
                        ForEach(mints) { mint in
                            Text(mint.displayName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .listRowBackground(Color.clear)
        .lineLimit(1)
    }
}


