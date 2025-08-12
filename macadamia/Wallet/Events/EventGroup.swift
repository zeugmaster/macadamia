import SwiftUI
import SwiftData

struct EventGroup {
    let events: [Event]
    
    init(events: [Event]) {
        precondition(!events.isEmpty, "EventGroup must be initialized with at least one event")
        self.events = events
    }
    
    var mostRecentDate: Date {
        events.map { $0.date }.max() ?? Date()
    }
    
    var totalAmount: Int? {
        let amounts = events.compactMap { $0.amount }
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }
    
    var allMints: [Mint] {
        let allMints = events.flatMap { $0.mints ?? [] }
        // Remove duplicates while preserving order
        var seen = Set<UUID>()
        return allMints.filter { mint in
            guard !seen.contains(mint.mintID) else { return false }
            seen.insert(mint.mintID)
            return true
        }
    }
    
    var primaryEvent: Event {
        // Safe to force unwrap due to precondition in init
        events.first!
    }
    
    var isGrouped: Bool {
        events.count > 1
    }
}