import SwiftUI
import secp256k1
import Bech32Swift

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
    
    @State private var nsecInput: String = ""
    @State private var validationMessage: String = ""
    @State private var isValidKey: Bool = false
    @State private var showValidation: Bool = false
    @State private var hasStoredKey: Bool = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person")
                        .font(.title2)
                        .padding()
                    VStack(alignment: .leading) {
                        Text("User Name")
                        Text("Subline")
                            .font(.caption)
                    }
                }
            }
            
            Section(header: Text("Nostr Private Key")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Enter nsec1... or 64-char hex key", text: $nsecInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: nsecInput) { oldValue, newValue in
                            showValidation = false
                        }
                    
                    if showValidation {
                        HStack {
                            Image(systemName: isValidKey ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isValidKey ? .green : .red)
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundColor(isValidKey ? .green : .red)
                        }
                    }
                    
                    if hasStoredKey {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.green)
                            Text("Private key is stored")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Button(action: validateAndSaveKey) {
                    Text(hasStoredKey ? "Update Key" : "Save Key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(nsecInput.isEmpty)
                
                if hasStoredKey {
                    Button(role: .destructive, action: deleteKey) {
                        Text("Delete Key")
                            .frame(maxWidth: .infinity)
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
        .onAppear {
            checkStoredKey()
        }
    }
    
    private func checkStoredKey() {
        hasStoredKey = NostrKeychain.hasNsec()
    }
    
    private func validateAndSaveKey() {
        let trimmedInput = nsecInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to validate as hex private key (64 characters)
        if trimmedInput.count == 64 {
            if validateHexKey(trimmedInput) {
                saveKey(trimmedInput)
                return
            }
        }
        
        // Try to decode as nsec (bech32)
        if trimmedInput.lowercased().hasPrefix("nsec1") {
            if let hexKey = decodeNsec(trimmedInput) {
                if validateHexKey(hexKey) {
                    saveKey(trimmedInput) // Store the original nsec format
                    return
                }
            }
        }
        
        // If we get here, validation failed
        isValidKey = false
        validationMessage = "Invalid private key format"
        showValidation = true
    }
    
    private func validateHexKey(_ hexKey: String) -> Bool {
        // Try to parse as hex and create a secp256k1 private key
        do {
            guard let keyData = try? hexKey.bytes else {
                isValidKey = false
                validationMessage = "Invalid hex format"
                showValidation = true
                return false
            }
            
            // Verify it's a valid secp256k1 private key
            _ = try secp256k1.Signing.PrivateKey(dataRepresentation: keyData)
            return true
        } catch {
            isValidKey = false
            validationMessage = "Invalid secp256k1 private key"
            showValidation = true
            return false
        }
    }
    
    private func decodeNsec(_ nsec: String) -> String? {
        do {
            // Try using the decode method
            let decoded = try Bech32.decode(nsec)
            
            // Verify the HRP (Human Readable Part) is "nsec"
            guard decoded.hrp == "nsec" else {
                isValidKey = false
                validationMessage = "Invalid nsec prefix"
                showValidation = true
                return nil
            }
            
            // Convert the decoded data to bytes
            let keyData = Data(decoded.data)
            
            // Verify it's 32 bytes (256 bits) as expected for secp256k1 private key
            guard keyData.count == 32 else {
                isValidKey = false
                validationMessage = "Invalid key length"
                showValidation = true
                return nil
            }
            
            // Convert to hex string
            let hexKey = String(bytes: keyData)
            return hexKey
        } catch {
            isValidKey = false
            validationMessage = "Failed to decode nsec: \(error.localizedDescription)"
            showValidation = true
            return nil
        }
    }
    
    private func saveKey(_ key: String) {
        do {
            try NostrKeychain.saveNsec(key)
            isValidKey = true
            validationMessage = "Key saved successfully"
            showValidation = true
            hasStoredKey = true
            nsecInput = ""
        } catch {
            isValidKey = false
            validationMessage = "Failed to save key: \(error.localizedDescription)"
            showValidation = true
        }
    }
    
    private func deleteKey() {
        do {
            try NostrKeychain.deleteNsec()
            hasStoredKey = false
            isValidKey = false
            validationMessage = "Key deleted"
            showValidation = true
        } catch {
            validationMessage = "Failed to delete key: \(error.localizedDescription)"
            showValidation = true
        }
    }
}

#Preview {
    Profile()
}
