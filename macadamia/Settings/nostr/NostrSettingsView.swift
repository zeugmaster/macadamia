//
//  NostrSettingsView.swift
//  macadamia
//
//  Simplified Nostr settings for wallet-specific key management
//

import SwiftUI
import NostrSDK

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
    @State private var npubKey: String = ""
    @State private var showCopiedAlert = false
    
    var body: some View {
        List {
            Section {
                if NostrKeychain.hasNsec() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Public Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text(npubKey.isEmpty ? "Loading..." : npubKey)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = npubKey
                                showCopiedAlert = true
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.blue)
                            }
                            .disabled(npubKey.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    NavigationLink(destination: KeyInput()) {
                        Text("Replace Key")
                    }
                } else {
                    NavigationLink(destination: KeyInput()) {
                        HStack {
                            Image(systemName: "key")
                                .foregroundStyle(.blue)
                            Text("Set up Nostr Key")
                        }
                    }
                }
            } header: {
                Text("Identity")
            } footer: {
                if NostrKeychain.hasNsec() {
                    Text("This wallet-specific key is used for Nostr functionality.")
                } else {
                    Text("A wallet-specific Nostr key will be generated when you set it up.")
                }
            }
            
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
        }
        .navigationTitle("Nostr")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadNpubKey()
        }
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Public key copied to clipboard")
        }
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
    
    private func loadNpubKey() {
        guard NostrKeychain.hasNsec() else {
            npubKey = ""
            return
        }
        
        do {
            let nsecString = try NostrKeychain.getNsec()
            let trimmed = nsecString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse the keypair
            let keypair: Keypair?
            if trimmed.lowercased().hasPrefix("nsec") {
                keypair = Keypair(nsec: trimmed)
            } else {
                keypair = Keypair(hex: trimmed)
            }
            
            if let keypair = keypair {
                npubKey = keypair.publicKey.npub
            } else {
                npubKey = "Invalid key"
            }
        } catch {
            npubKey = "Error loading key"
        }
    }
}

#Preview {
    NavigationStack {
        NostrSettingsView()
            .environmentObject(NostrService())
    }
}

