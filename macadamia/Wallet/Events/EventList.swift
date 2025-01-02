import SwiftUI
import SwiftData

struct EventList: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Query private var allEvents: [Event]

    @State private var events: [Event] = []

    var body: some View {
        List {
            ForEach(events) { event in
                EventListRow(event: event)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            deleteEvent(event)
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
            events = allEvents.filter { $0.wallet == activeWallet && $0.visible == true }
                              .sorted { $0.date > $1.date }
        } else {
            events = []
        }
    }

    private func deleteEvent(_ event: Event) {
        withAnimation {
            modelContext.delete(event)
            events.removeAll { $0.id == event.id }
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save context after deletion: \(error)")
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
                    return mint.displayName
                }
            } else {
                return "Multiple"
            }
        }
        return ""
    }
    
    var amountString: String? {
        switch event.kind {
        case .restore, .drain:
            return nil
        case .send, .melt, .pendingMelt:
            return amountDisplayString(event.amount ?? 0, unit: event.unit, negative: true)
        case .receive, .mint, .pendingMint:
            return amountDisplayString(event.amount ?? 0, unit: event.unit)
        }
    }
    
    var shortenedDateString: String {
        let now = Date()
        let dayPassed = Calendar.current.dateComponents([.hour],
                                                        from: event.date,
                                                        to: now).hour ?? 0 > 24
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = dayPassed ? .short : .none
        return dateFormatter.string(from: event.date)
    }
    
    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            RowLayout(mintLabel: readableMintName,
                      description: event.shortDescription,
                      amountString: amountString,
                      dateLabel: shortenedDateString,
                      memo: event.memo)
        }
    }
}

struct RowLayout: View {
    
    let mintLabel: String
    let description: String
    let amountString: String?
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
              dateLabel: "6.2.24, 14:32", memo: "tenks u")
}
