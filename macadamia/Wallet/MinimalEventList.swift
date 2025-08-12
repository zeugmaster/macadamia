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
    
    var sortedEventsForActiveWallet: [EventGroup] {
        let walletEvents = events.filter({ $0.wallet == activeWallet })
        
        // Group events by groupingID
        var groupedEvents: [UUID?: [Event]] = [:]
        var standaloneEvents: [Event] = []
        
        for event in walletEvents {
            // Only group melt events with a groupingID
            if event.kind == .melt, let groupingID = event.groupingID {
                groupedEvents[groupingID, default: []].append(event)
            } else {
                standaloneEvents.append(event)
            }
        }
        
        // Convert to EventGroup array
        var eventGroups: [EventGroup] = []
        
        // Add grouped events
        for (_, events) in groupedEvents {
            eventGroups.append(EventGroup(events: events))
        }
        
        // Add standalone events
        for event in standaloneEvents {
            eventGroups.append(EventGroup(events: [event]))
        }
        
        // Sort by most recent date
        return eventGroups.sorted { $0.mostRecentDate > $1.mostRecentDate }
    }
    
    var body: some View {
        List {
            if sortedEventsForActiveWallet.isEmpty {
                Text("No transactions yet.")
            } else {
                ForEach(Array(sortedEventsForActiveWallet.prefix(5).enumerated()), id: \.offset) { _, eventGroup in
                    TransactionListRow(eventGroup: eventGroup)
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
    var eventGroup: EventGroup

    init(eventGroup: EventGroup) {
        self.eventGroup = eventGroup
    }

    var body: some View {
        NavigationLink(destination: EventDetailView(event: eventGroup.primaryEvent)) {
            VStack(alignment: .leading) {
                HStack {
                    Group {
                        switch eventGroup.primaryEvent.kind {
                        case .pendingMelt, .pendingMint:
                            Image(systemName: "hourglass")
                        case .pendingReceive:
                            Image(systemName: "lock")
                        case .mint, .receive:
                            Image(systemName: "arrow.down.left")
                        case .melt, .send:
                            if eventGroup.isGrouped {
                                Image(systemName: "arrow.triangle.branch")
                            } else {
                                Image(systemName: "arrow.up.right")
                            }
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
                        HStack(spacing: 4) {
                            if eventGroup.isGrouped {
                                Text("Payment")
                                Text("• MPP")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(eventGroup.primaryEvent.shortDescription)
                            }
                        }
                        if let memo = eventGroup.primaryEvent.memo, !memo.isEmpty {
                            Text(memo)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amount = eventGroup.totalAmount {
                            switch eventGroup.primaryEvent.kind {
                            case .send, .drain, .melt, .pendingMelt:
                                Text(amountDisplayString(amount, unit: eventGroup.primaryEvent.unit, negative: true))
                                    .foregroundStyle(.secondary)
                            case .receive, .pendingReceive, .mint, .restore, .pendingMint:
                                Text(amountDisplayString(amount, unit: eventGroup.primaryEvent.unit, negative: false))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.body)
                }
                
                let mints = eventGroup.allMints
                if !mints.isEmpty {
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


