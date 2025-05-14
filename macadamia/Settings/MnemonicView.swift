import BIP39
import SwiftData
import SwiftUI

struct MnemonicView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var mnemonic: [String] {
        activeWallet?.mnemonic.components(separatedBy: " ") ?? []
    }

    func copyMnemonic() {
        UIPasteboard.general.string = mnemonic.joined(separator: " ")
    }

    @State private var isCopied = false

    var body: some View {
        List {
            Section {
                ForEach(Array(mnemonic.enumerated()), id: \.offset) { (index, word) in
                    HStack {
                        Text("\(index + 1).")
                            .frame(minWidth: 26, alignment: .trailing)
                        Text(word)
                    }
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            } header: {
                Text("12 Word backup seed phrase")
            }
            Section {
                Button {
                    copyToClipboard()
                } label: {
                    HStack {
                        if isCopied {
                            Text("Copied!")
                                .transition(.opacity)
                        } else {
                            Text("Copy to clipboard")
                                .transition(.opacity)
                        }
                        Spacer()
                        Image(systemName: "list.clipboard")
                    }
                }
            }
            Section {
                if let mints = activeWallet?.mints {
                    ForEach(mints.filter({ $0.hidden == false })) { mint in
                        HStack {
                            Text(mint.displayName)
                        }
                    }
                    .disabled(true)
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text("""
                    macadamia can only restore ecash from the mints it knows about. \
                    Make sure to include their URLs in the backup of your seed phrase.
                    """)
            }
        }
    }

    func copyToClipboard() {
        // Perform the actual copy operation here
        copyMnemonic()

        // Change button text with animation
        withAnimation {
            isCopied = true
        }

        // Revert button text after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    MnemonicView()
}
