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
    
    @EnvironmentObject private var nostrService: NostrService
    
    private var displayName: String {
        if let profile = nostrService.currentProfile {
            return profile.displayName ?? profile.name ?? "User Name"
        }
        return "User Name"
    }
    
    private var subtitle: String {
        if NostrKeychain.hasNsec() {
            if let profile = nostrService.currentProfile, let address = profile.nostrAddress {
                return address
            }
            return "Connected"
        }
        return "Not connected"
    }
    
    var body: some View {
        List {
            Section {
                NavigationLink(destination: KeyInput()) {
                    HStack {
                        // Profile picture
                        if let pictureURLString = nostrService.currentProfile?.pictureURL,
                           let pictureURL = URL(string: pictureURLString) {
                            AsyncImage(url: pictureURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                            .padding(.trailing, 8)
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .padding(.trailing, 8)
                        }
                        
                        VStack(alignment: .leading) {
                            if NostrKeychain.hasNsec() {
                                Text(displayName)
                            } else {
                                Text("Securely add NSEC")
                            }
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    switch nostrService.connectionStatus {
                    case .connected:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .connecting:
                        Label("Connecting", systemImage: "circle.dotted")
                            .foregroundStyle(.orange)
                    case .disconnected:
                        Label("Disconnected", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    case .error:
                        Label("Error", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                
                if nostrService.isConnected {
                    Button {
                        nostrService.stop()
                    } label: {
                        Text("Disconnect")
                    }
                } else {
                    Button {
                        nostrService.start()
                    } label: {
                        Text("Connect")
                    }
                }
                
                Button {
                    nostrService.refreshProfile()
                } label: {
                    Text("Refresh Profile")
                }
                .disabled(!nostrService.isConnected)
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
                        Text("\(nostrService.contacts.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    Profile()
        .environmentObject(NostrService())
}
