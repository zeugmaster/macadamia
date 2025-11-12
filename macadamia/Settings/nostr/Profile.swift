import SwiftUI
import NostrSDK
import Combine

let defaultRelayURLs = [
    URL(string: "wss://relay.snort.social")!,
    URL(string: "wss://nostr.wine")!,
    URL(string: "wss://nos.lol")!,
    URL(string: "wss://relay.damus.io")!,
]

struct Profile: View {

    @AppStorage("savedURLs") private var savedURLsData: Data = {
        return try! JSONEncoder().encode(defaultRelayURLs)
    }()

    private var savedURLs: Binding<[URL]> {
        Binding(
            get: { (try? JSONDecoder().decode([URL].self, from: savedURLsData)) ?? defaultRelayURLs },
            set: { newValue in
                savedURLsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        )
    }
    
    @StateObject private var relayPool: RelayPool = try! RelayPool(relayURLs: Set(defaultRelayURLs))
    @State private var cancellables = Set<AnyCancellable>()
    
    // Add this to force view updates when relay states change
    @State private var relayStatesHash: Int = 0
    
    private enum RelayConnectionStates {
        case allConnected, noneConnected, partial
    }
    
    private var relayConnectionStates: RelayConnectionStates {
        // Reference relayStatesHash to make this computed property depend on it
        _ = relayStatesHash
        
        if relayPool.relays.isEmpty {
            return .noneConnected
        } else if relayPool.relays.allSatisfy({ $0.state == .connected }) {
            return .allConnected
        } else if relayPool.relays.allSatisfy({ $0.state == .notConnected}) {
            return .noneConnected
        } else {
            return .partial
        }
    }
    
    var body: some View {
        List {
            Section {
                NavigationLink(destination: KeyInput()) {
                    HStack {
                        Image(systemName: "person")
                            .font(.title2)
                            .padding()
                        VStack(alignment: .leading) {
                            if NostrKeychain.hasNsec() {
                                Text("User Name")
                            } else {
                                Text("Securely add NSEC")
                            }
                            Text("Subline")
                                .font(.caption)
                        }
                    }
                }
            }
            
            Section {
                ForEach(Array(relayPool.relays), id: \.url) { relay in
                    RelayRow(relay: relay)
                        // Listen to each relay's state changes
                        .onReceive(relay.$state) { _ in
                            updateRelayStatesHash()
                        }
                }
            }
            
            Section {
                switch relayConnectionStates {
                case .allConnected:
                    Button {
                        relayPool.disconnect()
                    } label: {
                        Text("Disconnect")
                    }
                case .noneConnected:
                    Button {
                        relayPool.connect()
                    } label: {
                        Text("Connect")
                    }
                case .partial:
                    Text("Partially connected.")
                }
                Button {
                    subscribeToProfile()
                } label: {
                    Text("Load profile events")
                }
            }
            
            Section {
                NavigationLink(destination: Relays(urls: savedURLs)) {
                    HStack {
                        Text("Relays")
                        Spacer()
                        Text("\(savedURLs.wrappedValue.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                NavigationLink(destination: Contacts()) {
                    HStack {
                        Text("Contacts")
                        Spacer()
                        Text("123")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            // Initial hash update
            updateRelayStatesHash()
            
        }
    }
    
    private func subscribeToProfile() {
        guard let keyString = try? NostrKeychain.getNsec() else {
            return
        }
        
        guard let keypair = keyString.lowercased().contains("nsec") ? Keypair(nsec: keyString) : Keypair(hex: keyString) else {
            return
        }
        
        let publicKey = keypair.publicKey.hex
        
        guard let filter = Filter(authors: [publicKey], kinds: [0], limit: 1) else {
            return
        }
        
        let subID = relayPool.subscribe(with: filter)
        print("subscribed with id \(subID)")
        
        relayPool.events
            .receive(on: DispatchQueue.main)
            .sink { relayEvent in
                // Try to cast to MetadataEvent
                if let metadataEvent = relayEvent.event as? MetadataEvent {
                    print("Name: \(metadataEvent.name ?? "N/A")")
                    print("Display Name: \(metadataEvent.displayName ?? "N/A")")
                    print("About: \(metadataEvent.about ?? "N/A")")
                    print("Picture URL: \(metadataEvent.pictureURL?.absoluteString ?? "N/A")")
                    print("NIP-05: \(metadataEvent.nostrAddress ?? "N/A")")
                    print("Website: \(metadataEvent.websiteURL?.absoluteString ?? "N/A")")
                    print("Lightning Address: \(metadataEvent.lightningAddress ?? "N/A")")
                }
            }
            .store(in: &cancellables)
        
    }
    
    private func updateRelayStatesHash() {
        // Create a hash based on all relay states
        relayStatesHash = relayPool.relays.map { relay in
            switch relay.state {
            case .connected: return 1
            case .connecting: return 2
            case .notConnected: return 3
            case .error: return 4
            }
        }.reduce(0, { $0 ^ $1 })
    }
}

struct RelayRow: View {
    @ObservedObject var relay: Relay
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(relay.url.absoluteString)
            Text(String(describing: relay.state))
        }
    }
}

#Preview {
    Profile()
}
