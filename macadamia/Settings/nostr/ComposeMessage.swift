import SwiftUI

struct ComposeMessage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nostrService: NostrService
    
    let contact: NostrContact
    let profile: NostrProfile?
    
    @State private var messageText: String
    @State private var useNIP17: Bool = true
    @State private var isSending: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    init(contact: NostrContact, profile: NostrProfile?, prefilledContent: String? = nil) {
        self.contact = contact
        self.profile = profile
        self._messageText = State(initialValue: prefilledContent ?? "")
    }
    
    private var recipientName: String {
        if let petname = contact.petname, !petname.isEmpty {
            return petname
        }
        if let profile = profile {
            return profile.displayName ?? profile.name ?? contact.contactPubkey.prefix(8) + "..."
        }
        return contact.contactPubkey.prefix(8) + "..."
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("To:")
                            .foregroundStyle(.secondary)
                        Text(recipientName)
                    }
                } header: {
                    Text("Recipient")
                }
                
                Section {
                    Toggle("Use NIP-17 (More Private)", isOn: $useNIP17)
                        .tint(.green)
                } header: {
                    Text("Protocol")
                } footer: {
                    Text(useNIP17 ? "NIP-17 provides better privacy by hiding the sender in a gift wrap." : "NIP-4 is the legacy encrypted DM format (deprecated).")
                }
                
                Section {
                    TextEditor(text: $messageText)
                        .frame(minHeight: 150)
                } header: {
                    Text("Message")
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await sendMessage()
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(messageText.isEmpty || isSending)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    @MainActor
    private func sendMessage() async {
        guard !messageText.isEmpty else { return }
        
        isSending = true
        
        do {
            if useNIP17 {
                try await nostrService.sendNIP17Message(
                    to: contact.contactPubkey,
                    content: messageText,
                    subject: nil
                )
            } else {
                try await nostrService.sendNIP4Message(
                    to: contact.contactPubkey,
                    content: messageText
                )
            }
            
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isSending = false
    }
}

#Preview {
    let service = NostrService()
    let contact = NostrContact(
        ownerPubkey: "test",
        contactPubkey: "recipienttest",
        petname: "Alice"
    )
    
    return ComposeMessage(contact: contact, profile: nil)
        .environmentObject(service)
}

