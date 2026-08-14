//
//  NostrKeyListView.swift
//  macadamia
//
//  Read-only list of the active wallet's per-request nostr receive keys.
//

import SwiftUI
import SwiftData

struct NostrKeyListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var nostrService: NostrService

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Query(sort: \NostrKeypair.dateCreated, order: .reverse) private var allKeys: [NostrKeypair]

    private var activeWallet: Wallet? {
        wallets.first
    }

    private var keys: [NostrKeypair] {
        allKeys.filter { $0.wallet?.walletID == activeWallet?.walletID }
    }

    var body: some View {
        List {
            if keys.isEmpty {
                Text("No receive keys yet. A key is generated whenever you create a payment request with Nostr enabled.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(keys) { key in
                        keyRow(key)
                    }
                    .onDelete(perform: deleteKeys)
                } footer: {
                    Text("Deleting a key stops the wallet from receiving payments sent to it.")
                }
            }
        }
        .navigationTitle("Receive Keys")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func keyRow(_ key: NostrKeypair) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if key.isLegacy {
                    Text("Legacy key")
                } else if let paymentId = key.paymentId {
                    Text("Request \(paymentId)")
                } else {
                    Text("Receive key")
                }
                Spacer()
                if key.isActive {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Expired")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(key.dateCreated.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            let redeemedCount = key.messages.filter { $0.outcome == .redeemed }.count
            if redeemedCount > 0 {
                Text("Redeemed messages: \(redeemedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteKeys(at offsets: IndexSet) {
        let selected = offsets.map { keys[$0] }
        selected.forEach { modelContext.delete($0) } // cascade also removes ledger rows
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to delete nostr receive key: \(error)")
        }
        nostrService.refreshSubscriptions()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        NostrKeyListView()
            .previewEnvironment()
    }
}
#endif
