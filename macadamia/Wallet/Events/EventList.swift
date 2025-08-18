import SwiftUI
import SwiftData

struct EventList: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Query private var allEvents: [Event]

    @State private var eventGroups: [EventGroup] = []

    var body: some View {
        List {
            ForEach(eventGroups, id: \.primaryEvent.id) { eventGroup in
                EventListRow(eventGroup: eventGroup)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            deleteEventGroup(eventGroup)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.white)
                        }
                        .tint(Color.black)
                    }
            }
        }
        .onAppear {
            updateEvents()
        }
        .onChange(of: wallets.first) { _, _ in
            updateEvents()
        }
        .onChange(of: allEvents) { _, _ in
            updateEvents()
        }
    }

    private func updateEvents() {
        if let activeWallet = wallets.first {
            let walletEvents = allEvents.filter { $0.wallet == activeWallet && $0.visible == true }
            
            // Group events by groupingID
            var groupedEvents: [UUID?: [Event]] = [:]
            var standaloneEvents: [Event] = []
            
            for event in walletEvents {
                // Group melt and pending melt events with a groupingID
                if (event.kind == .melt || event.kind == .pendingMelt), let groupingID = event.groupingID {
                    groupedEvents[groupingID, default: []].append(event)
                } else {
                    standaloneEvents.append(event)
                }
            }
            
            // Convert to EventGroup array
            var groups: [EventGroup] = []
            
            // Add grouped events
            for (_, events) in groupedEvents {
                groups.append(EventGroup(events: events))
            }
            
            // Add standalone events
            for event in standaloneEvents {
                groups.append(EventGroup(events: [event]))
            }
            
            // Sort by most recent date
            eventGroups = groups.sorted { $0.mostRecentDate > $1.mostRecentDate }
        } else {
            eventGroups = []
        }
    }

    private func deleteEventGroup(_ eventGroup: EventGroup) {
        withAnimation {
            // Delete all events in the group
            for event in eventGroup.events {
                modelContext.delete(event)
            }
            // Update local state
            updateEvents()
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save context after deletion: \(error)")
        }
    }
}

struct EventListRow: View {
    
    let eventGroup: EventGroup
    
    @ViewBuilder
    var destination: some View {
        if eventGroup.primaryEvent.kind == .pendingMelt {
            // For pending melt events, navigate to MultiMeltView with all events in the group
            MultiMeltView(pendingMeltEvents: eventGroup.events)
        } else {
            EventDetailView(event: eventGroup.primaryEvent)
        }
    }
    
    var readableMintName: String {
        let mints = eventGroup.allMints
        if mints.isEmpty {
            return ""
        } else if mints.count == 1 {
            return mints.first?.displayName ?? ""
        } else {
            return "Multiple"
        }
    }
    
    var amountString: String? {
        let event = eventGroup.primaryEvent
        switch event.kind {
        case .restore, .drain:
            return nil
        case .send, .melt, .pendingMelt:
            return amountDisplayString(eventGroup.totalAmount ?? 0, unit: event.unit, negative: true)
        case .receive, .pendingReceive, .mint, .pendingMint:
            return amountDisplayString(eventGroup.totalAmount ?? 0, unit: event.unit)
        }
    }
    
    var shortenedDateString: String {
        let now = Date()
        let dayPassed = Calendar.current.dateComponents([.hour],
                                                        from: eventGroup.mostRecentDate,
                                                        to: now).hour ?? 0 > 24
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = dayPassed ? .short : .none
        return dateFormatter.string(from: eventGroup.mostRecentDate)
    }
    
    var description: String {
        let event = eventGroup.primaryEvent
        if eventGroup.isGrouped && (event.kind == .melt || event.kind == .pendingMelt) {
            return event.kind == .pendingMelt ? "Pending Payment • MPP" : "Payment • MPP"
        } else {
            return event.shortDescription
        }
    }
    
    var body: some View {
        NavigationLink(destination: destination) {
            RowLayout(mintLabel: readableMintName,
                      description: description,
                      amountString: amountString,
                      dateLabel: shortenedDateString,
                      memo: eventGroup.primaryEvent.memo,
                      isGrouped: eventGroup.isGrouped)
        }
    }
}

struct RowLayout: View {
    
    let mintLabel: String
    let description: String
    let amountString: String?
    let dateLabel: String
    
    let memo: String?
    var isGrouped: Bool = false
    
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
                HStack(spacing: 4) {
                    if isGrouped {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                    }
                    if let memo, !memo.isEmpty {
                        Text(description + ": \(memo)")
                    } else {
                        Text(description)
                    }
                }
                Spacer()
                if let amountString {
                    Text(amountString)
                        .monospaced()
                }
            }
        }
        .lineLimit(1)
    }
}

#Preview {
    RowLayout(mintLabel: "mint.macadamia.cash",
              description: "Send",
              amountString: "- 420 sat",
              dateLabel: "6.2.24, 14:32", 
              memo: "tenks u",
              isGrouped: false)
}
