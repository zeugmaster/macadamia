//
//  EventListV2.swift
//  macadamia
//
//  Created by zm on 23.08.25.
//

import SwiftUI
import SwiftData

struct EventList: View {
    
    struct EventGroup: Identifiable {
        let events: [Event]
        let date: Date // hold the latest date for the group for chronological sorting
        let id: UUID
    }
    
    enum Style { case minimal, full }
    let style: Style
    
    let shortListLength = 10
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allEvents: [Event]
    @Query private var wallets: [Wallet]
    
    @State private var showHidden = false
    
    private let shadowHeight: CGFloat = 10
    
    private var activeWallet: Wallet? {
        wallets.first { $0.active }
    }
    
    private var events: [Event] {
        allEvents.filter { $0.wallet == activeWallet }
                 .filter({ $0.visible || showHidden })
    }
    
    private var eventGroups: [EventGroup] {
        var out: [EventGroup] = []
        var seen = Set<AnyHashable>()
        for e in events {
            if let gid = e.groupingID {
                let key = AnyHashable(gid)
                if seen.contains(key) { continue }
                let grouped = events.filter { $0.groupingID == gid }
                out.append(EventGroup(events: grouped,
                                      date: grouped.first?.date ?? e.date,
                                      id: gid))
                seen.insert(key)
            } else {
                out.append(EventGroup(events: [e],
                                      date: e.date,
                                      id: e.eventID))
            }
        }
        return out.sorted(by: { $0.date > $1.date })
    }
    
    var body: some View {
        Group {
            switch style {
            case .minimal:
                List {
                    if eventGroups.isEmpty {
                        Text("No transactions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(eventGroups.prefix(shortListLength)) { group in
                            MinimalRow(eventGroup: group)
                        }
                        if eventGroups.count > shortListLength {
                            NavigationLink(destination: EventList(style: .full),
                                           label: {
                                HStack {
                                    Spacer().frame(width: 28)
                                    Text("Show all")
                                }
                            })
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
            case .full:
                List {
                    ForEach(eventGroups) { group in
                        FullRow(eventGroup: group)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                deleteEvents(of: group)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.white)
                            }
                            .tint(Color.black)
                        }
                    }
                }
            }
        }
        .lineLimit(1)
    }
    
    struct MinimalRow: View {
        let eventGroup: EventGroup
        
        var body: some View {
            NavigationLink(destination: destination(for: eventGroup)) {
                VStack(alignment: .leading) {
                    HStack {
                        image
                            .opacity(0.8)
                            .font(.caption)
                            .frame(width: 20, alignment: .leading)
                        let (main, secondary) = description(for: eventGroup)
                        Text(main)
                        if let secondary {
                            Text(secondary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amountString = amountString(for: eventGroup) {
                            Text(amountString)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.body)
                    HStack {
                        Spacer().frame(width: 28)
                        mintLabel
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        
        private var image: Image {
            switch eventGroup.events.first?.kind {
            case .pendingMelt, .pendingMint:
                Image(systemName: "hourglass")
            case .pendingReceive:
                Image(systemName: "lock")
            case .mint, .receive:
                Image(systemName: "arrow.down.left")
            case .melt, .send:
                if eventGroup.events.count > 1 {
                    Image(systemName: "arrow.triangle.branch")
                } else {
                    Image(systemName: "arrow.up.right")
                }
            case .restore:
                Image(systemName: "clock.arrow.circlepath")
            case .drain:
                Image(systemName: "arrow.uturn.right")
            case .none:
                Image(systemName: "xmark")
            case .transfer, .pendingTransfer:
                Image(systemName: "arrow.down.left.arrow.up.right")
            }
        }
        
        private var mintLabel: Text {
            switch eventGroup.events.first?.kind {
            case .pendingTransfer, .transfer:
                if let from = eventGroup.events.first?.mints?[0],
                   let to = eventGroup.events.first?.mints?[1] {
                    return Text("\(from.displayName) ") + Text(Image(systemName: "arrow.right")) + Text(" \(to.displayName)")
                } else {
                    return Text("...")
                }
            case nil:
                return Text("")
            default:
                let mints = eventGroup.events.compactMap { $0.mints }.flatMap { $0 }
                let names = mints.map(\.displayName)
                return Text(names.joined(separator: ", "))
            }
        }
    }

    struct FullRow: View {
        let eventGroup: EventGroup
        
        var body: some View {
            NavigationLink(destination: destination(for: eventGroup)) {
                VStack {
                    HStack {
                        Image(systemName: "building.columns.fill")
                        
                        let mints = eventGroup.events.compactMap { $0.mints }.flatMap { $0 }
                        ForEach(mints) { mint in
                            Text(mint.displayName)
                        }
                        
                        Spacer()
                        Text(shortenedDateString)
                    }
                    .font(.caption)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    HStack {
                        HStack(spacing: 4) {
                            let (main, secondary) = description(for: eventGroup)
                            Text(main)
                            if let secondary {
                                Text(secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let amountString = amountString(for: eventGroup) {
                            Text(amountString)
                                .monospaced()
                        }
                    }
                }
            }
        }
        
        var shortenedDateString: String {
            let now = Date()
            let dayPassed = Calendar.current.dateComponents([.hour],
                                                            from: eventGroup.date,
                                                            to: now).hour ?? 0 > 24
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            dateFormatter.dateStyle = dayPassed ? .short : .none
            return dateFormatter.string(from: eventGroup.date)
        }
    }
    
    private func deleteEvents(of group: EventGroup) {
        withTransaction(Transaction(animation: .default)) {
            group.events.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }
    }

    
    private static func description(for eventGroup: EventGroup) -> (main: String,
                                                                   secondary: String?) {
        guard let primaryEvent = eventGroup.events.first else {
            return ("Empty", nil)
        }
        switch primaryEvent.kind {
        case .pendingMint:      return ("Pending Ecash", nil)
        case .mint:             return ("Ecash created", nil)
        case .send:             return ("Send", primaryEvent.memo)
        case .receive:          return ("Receive", primaryEvent.memo)
        case .pendingReceive:   return ("Locked Token", nil)
        case .pendingMelt:      return ("Pending Payment", nil)
        case .melt:             return ("Payment", nil)
        case .restore:          return ("Restore", nil)
        case .drain:            return ("Drain", nil)
        case .pendingTransfer:  return ("Pending Transfer", nil)
        case .transfer:         return ("Transfer", nil)
        }
    }
    
    private static func amountString(for group: EventGroup) -> String? {
        let negative: Bool
        switch group.events.first?.kind {
        case .send, .drain, .melt, .pendingMelt: negative = true
        case .restore: return nil
        default: negative = false
        }
        let sum = group.events.reduce(0, { $0 + ($1.amount ?? 0) })
        return amountDisplayString(sum, unit: .sat, negative: negative)
    }
    
    @ViewBuilder
    private static func destination(for group: EventGroup) -> some View {
        switch group.events.first?.kind {
        case .pendingMint:
            MintView(pendingMintEvent: group.events.first)
        case .mint:
            if let e = group.events.first { MintEventSummary(event: e) } else { Text("No mint event provided.") }
        case .send:
            if let e = group.events.first { SendEventView(event: e) } else { Text("No send event provided.") }
        case .receive:
            if let e = group.events.first { ReceiveEventSummary(event: e) } else { Text("No receive event provided.") }
        case .pendingReceive:
            if let e = group.events.first { RedeemLaterView(event: e) } else { Text("No pending receive event provided.") }
        case .pendingMelt:
            MeltView(events: group.events)
        case .melt:
            MeltEventSummary(events: group.events)
        case .restore:
            if let e = group.events.first { RestoreEventSummary(event: e) } else { Text("No restore event provided.") }
        case .transfer:
            if let e = group.events.first { TransferEventSummary(event: e) } else { Text("No transfer event provided.")}
        case .pendingTransfer:
            if let e = group.events.first { TransferView(pendingTransferEvent: e) } else { Text("No pending transfer event provided.") }
        default:
            Text("Unknown event kind.")
        }
    }
}
