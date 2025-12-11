import SwiftUI
import NostrSDK

struct Relays: View {
    
    @Binding var urls: [URL]
    @EnvironmentObject private var nostrService: NostrService
    
    @State private var newURL = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            Section {
                ForEach(urls, id: \.self) { url in
                    RelayRow(url: url, connectionState: nostrService.connectionStates[url])
                }
                .onDelete(perform: deleteRelay)
            } header: {
                Text("Relays")
            } footer: {
                connectionSummaryText
            }
            
            Section {
                TextField("", text: $newURL, prompt: Text("wss://relay..."))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        addRelay()
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Add") {
                                addRelay()
                            }
                            .disabled(newURL.isEmpty)
                        }
                    }
            } header: {
                Text("Add Relay")
            }
        }
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Invalid URL", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var connectionSummaryText: some View {
        let connected = nostrService.connectionStates.filter { $0.value == .connected }.count
        let total = urls.count
        
        if total == 0 {
            Text("No relays configured. Add a relay to connect to Nostr.")
        } else if connected == 0 {
            Text("Not connected to any relays.")
        } else if connected == total {
            Text("Connected to all \(total) relay\(total == 1 ? "" : "s").")
        } else {
            Text("Connected to \(connected) of \(total) relay\(total == 1 ? "" : "s").")
        }
    }
    
    private func addRelay() {
        guard !newURL.isEmpty else { return }
        
        // Check for websocket prefix
        guard newURL.lowercased().hasPrefix("ws://") || newURL.lowercased().hasPrefix("wss://") else {
            errorMessage = "Relay URL must start with ws:// or wss://"
            showError = true
            return
        }
        
        guard let url = URL(string: newURL) else {
            errorMessage = "Invalid URL format"
            showError = true
            return
        }
        
        // Check if URL already exists
        guard !urls.contains(url) else {
            errorMessage = "This relay is already in your list"
            showError = true
            return
        }
        
        // Add via NostrService for real-time pool update
        nostrService.addRelay(url)
        urls.append(url)
        newURL = ""
    }
    
    private func deleteRelay(at offsets: IndexSet) {
        // Remove via NostrService for real-time pool update
        for index in offsets {
            let url = urls[index]
            nostrService.removeRelay(url)
        }
        urls.remove(atOffsets: offsets)
    }
}

// MARK: - Relay Row

struct RelayRow: View {
    let url: URL
    let connectionState: Relay.State?
    
    var body: some View {
        HStack {
            connectionIndicator
            
            Text(url.absoluteString)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            if let state = connectionState {
                Text(stateLabel(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var connectionIndicator: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
    }
    
    private var indicatorColor: Color {
        guard let state = connectionState else {
            return .gray.opacity(0.5)
        }
        
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .error:
            return .red
        case .notConnected:
            return .gray.opacity(0.5)
        @unknown default:
            return .gray.opacity(0.5)
        }
    }
    
    private func stateLabel(for state: Relay.State) -> String {
        switch state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .error:
            return "Error"
        case .notConnected:
            return "Disconnected"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var urls = [
            URL(string: "wss://relay.to")!,
            URL(string: "wss://damuswasrein.io")!,
            URL(string: "wss://relayasdf.io")!,
        ]
        
        var body: some View {
            NavigationStack {
                Relays(urls: $urls)
                    .environmentObject(NostrService())
            }
        }
    }
    
    return PreviewWrapper()
}
