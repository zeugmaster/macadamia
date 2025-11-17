//
//  KeyInput.swift
//  macadamia
//
//  Created by zm on 08.11.25.
//

import SwiftUI
import secp256k1
import Bech32Swift
import NostrSDK

struct KeyInput: View {
    @EnvironmentObject var nostrService: NostrService
    
    @State private var nsecInput: String = ""
    @State private var validationMessage: String = ""
    @State private var isValidKey: Bool = false
    @State private var showValidation: Bool = false
    @State private var hasStoredKey: Bool = false
    @State private var generatedNpub: String = ""
    
    var body: some View {
        List {
            if hasStoredKey && !generatedNpub.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your wallet public key (npub)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(generatedNpub)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Generated Key")
                } footer: {
                    Text("A wallet-specific Nostr key has been generated for you. You can replace it with your own key below if desired.")
                }
            }
            
            Section(header: Text("Replace with Custom Key")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Enter nsec1... or 64-char hex key", text: $nsecInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
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
                    Text(hasStoredKey ? "Replace Key" : "Save Key")
                        .frame(maxWidth: .infinity)
                }
                .disabled(nsecInput.isEmpty)
                
                if hasStoredKey {
                    Button(role: .destructive, action: deleteKey) {
                        Text("Delete Key")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Nostr Key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkStoredKey()
            generateKeyIfNeeded()
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
            // Clear Nostr cache and disconnect service
            nostrService.clearCacheAndStop()
            
            // Delete the key from keychain
            try NostrKeychain.deleteNsec()
            
            hasStoredKey = false
            isValidKey = false
            generatedNpub = ""
            validationMessage = "Key deleted and cache cleared"
            showValidation = true
        } catch {
            validationMessage = "Failed to delete key: \(error.localizedDescription)"
            showValidation = true
        }
    }
    
    private func generateKeyIfNeeded() {
        // Only generate if no key exists
        guard !NostrKeychain.hasNsec() else {
            loadNpubFromStoredKey()
            return
        }
        
        // Generate a new keypair
        guard let keypair = Keypair() else {
            validationMessage = "Failed to generate keypair"
            isValidKey = false
            showValidation = true
            return
        }
        
        let nsecString = keypair.privateKey.nsec
        
        // Save to keychain
        do {
            try NostrKeychain.saveNsec(nsecString)
            hasStoredKey = true
            generatedNpub = keypair.publicKey.npub
            
            isValidKey = true
            validationMessage = "Wallet key generated successfully"
            showValidation = true
        } catch {
            validationMessage = "Failed to generate key: \(error.localizedDescription)"
            isValidKey = false
            showValidation = true
        }
    }
    
    private func loadNpubFromStoredKey() {
        guard NostrKeychain.hasNsec() else {
            generatedNpub = ""
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
                generatedNpub = keypair.publicKey.npub
            } else {
                generatedNpub = "Invalid key"
            }
        } catch {
            generatedNpub = "Error loading key"
        }
    }
}

#Preview {
    NavigationStack {
        KeyInput()
            .environmentObject(NostrService())
    }
}
