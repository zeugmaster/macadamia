import SwiftUI

let defaultRelayURLs = [
    URL(string: "wss://nostr.mutinywallet.com")!,
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
    }
}

#Preview {
    Profile()
}
