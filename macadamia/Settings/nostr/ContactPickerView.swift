import SwiftUI
import NostrSDK

struct ContactPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nostrService: NostrService
    
    let tokenString: String
    
    @State private var manualInput: String = ""
    @State private var selectedContact: NostrContact?
    @State private var showComposeMessage = false
    @State private var validationError: String?
    
    private var isValidInput: Bool {
        validateInput() != nil
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("npub or hex pubkey", text: $manualInput)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .monospaced()
                        
                        if !manualInput.isEmpty {
                            Button {
                                manualInput = ""
                                validationError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if !manualInput.isEmpty && isValidInput {
                        Button {
                            sendToManualEntry()
                        } label: {
                            HStack {
                                Text("Send to this pubkey")
                                Spacer()
                                Image(systemName: "paperplane.fill")
                            }
                        }
                    }
                } header: {
                    Text("Enter Recipient")
                } footer: {
                    Text("Paste an npub or hex public key to send to someone not in your contacts")
                }
                
                if !nostrService.contacts.isEmpty {
                    Section {
                        ForEach(nostrService.contacts, id: \.id) { contact in
                            Button {
                                selectedContact = contact
                                showComposeMessage = true
                            } label: {
                                ContactPickerRow(
                                    contact: contact,
                                    profile: nostrService.contactProfiles[contact.contactPubkey]
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Your Contacts")
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "person.2.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No contacts found")
                                    .font(.headline)
                                Text("Enter a pubkey above or add contacts in your Nostr profile")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Send Token via Nostr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showComposeMessage) {
                if let contact = selectedContact {
                    ComposeMessage(
                        contact: contact,
                        profile: nostrService.contactProfiles[contact.contactPubkey],
                        prefilledContent: tokenString
                    )
                    .environmentObject(nostrService)
                }
            }
            .onChange(of: manualInput) { _, _ in
                validateInputAndUpdateError()
            }
        }
    }
    
    private func validateInput() -> String? {
        let trimmed = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return nil
        }
        
        // Try npub first
        if trimmed.lowercased().hasPrefix("npub") {
            if let publicKey = PublicKey(npub: trimmed) {
                return publicKey.hex
            }
        }
        
        // Try hex
        if trimmed.count == 64, trimmed.allSatisfy({ $0.isHexDigit }) {
            if let _ = PublicKey(hex: trimmed) {
                return trimmed
            }
        }
        
        return nil
    }
    
    private func validateInputAndUpdateError() {
        let trimmed = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            validationError = nil
            return
        }
        
        if validateInput() == nil {
            validationError = "Invalid npub or hex pubkey"
        } else {
            validationError = nil
        }
    }
    
    private func sendToManualEntry() {
        guard let validHex = validateInput() else {
            return
        }
        
        let contact = NostrContact(
            ownerPubkey: nostrService.currentProfile?.pubkey ?? "",
            contactPubkey: validHex,
            petname: nil,
            relayURL: nil
        )
        
        selectedContact = contact
        showComposeMessage = true
    }
}

struct ContactPickerRow: View {
    let contact: NostrContact
    let profile: NostrProfile?
    
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
            
            Image(systemName: "paperplane")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContactPickerView(tokenString: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vOC4zMy4...")
        .environmentObject(NostrService())
}

