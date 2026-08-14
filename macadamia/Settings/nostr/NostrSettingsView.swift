//
//  NostrSettingsView.swift
//  macadamia
//
//  Nostr settings: relay management and the per-request receive keys
//

import SwiftUI

let defaultRelayURLs = [
    URL(string: "wss://relay.snort.social")!,
    URL(string: "wss://nostr.wine")!,
    URL(string: "wss://nos.lol")!,
    URL(string: "wss://relay.damus.io")!,
]

struct NostrSettingsView: View {
    @AppStorage("savedURLs") private var savedURLsData: Data = {
        return try! JSONEncoder().encode(defaultRelayURLs)
    }()
    @AppStorage("nostrAutoConnectEnabled") private var autoConnectEnabled: Bool = true

    private var savedURLs: Binding<[URL]> {
        Binding(
            get: { (try? JSONDecoder().decode([URL].self, from: savedURLsData)) ?? defaultRelayURLs },
            set: { newValue in
                savedURLsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        )
    }

    @EnvironmentObject private var nostrService: NostrService

    var body: some View {
        List {
            Section {
                Toggle("Auto-connect to Relays", isOn: $autoConnectEnabled)

                NavigationLink(destination: Relays(urls: savedURLs)) {
                    HStack {
                        Text("Relays")
                        Spacer()
                        connectionStatusBadge
                    }
                }
            } header: {
                Text("Network")
            } footer: {
                Text("When enabled, the app automatically connects to relays to receive ecash payments via Nostr.")
            }

            Section {
                NavigationLink(destination: NostrKeyListView()) {
                    Text("Receive Keys")
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("A one-time key is generated for every payment request. Keys receive payments for 90 days.")
            }
        }
        .navigationTitle("Nostr")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        let connected = nostrService.connectionStates.filter { $0.value == .connected }.count
        let total = savedURLs.wrappedValue.count

        HStack(spacing: 4) {
            Circle()
                .fill(connected > 0 ? .green : .gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text("\(connected)/\(total)")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        NostrSettingsView()
            .environmentObject(NostrService())
    }
}
