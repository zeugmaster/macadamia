import SwiftUI

struct Contacts: View {
    @EnvironmentObject var nostrService: NostrService
    
    var body: some View {
        List {
            if nostrService.contacts.isEmpty {
                Section {
                    if nostrService.isConnected {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "person.2.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No contacts found")
                                    .font(.headline)
                                Text("Your follow list is empty")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "wifi.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Not connected")
                                    .font(.headline)
                                Text("Connect to load your contacts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                }
            } else {
                Section {
                    ForEach(nostrService.contacts, id: \.id) { contact in
                        ContactRow(
                            contact: contact,
                            profile: nostrService.contactProfiles[contact.contactPubkey]
                        )
                    }
                }
            }
        }
        .navigationTitle("Contacts")
    }
}

struct ContactRow: View {
    let contact: NostrContact
    let profile: NostrProfile?
    @State private var showComposeMessage = false
    
    private var displayName: String {
        if let petname = contact.petname, !petname.isEmpty {
            return petname
        }
        if let profile = profile {
            return profile.displayName ?? profile.name ?? contact.contactPubkey.prefix(8) + "..."
        }
        return contact.contactPubkey.prefix(8) + "..."
    }
    
    private var subtitle: String {
        if let profile = profile, let address = profile.nostrAddress {
            return address
        }
        return contact.contactPubkey.prefix(16) + "..."
    }
    
    var body: some View {
        Button {
            showComposeMessage = true
        } label: {
            HStack {
                // Profile picture
                if let profile = profile,
                   let pictureURLString = profile.pictureURL,
                   let pictureURL = URL(string: pictureURLString) {
                    AsyncImage(url: pictureURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
                
                Spacer()
                
                Image(systemName: "message")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showComposeMessage) {
            ComposeMessage(contact: contact, profile: profile)
        }
    }
}

#Preview {
    NavigationStack {
        Contacts()
            .environmentObject(NostrService())
    }
}
