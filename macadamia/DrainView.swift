import CashuSwift
import SwiftData
import SwiftUI

struct DrainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }

    @State private var selectedMints: Set<String> = []
    @State private var tokens: [TokenInfo] = []
    @State private var makeTokenMultiMint = false
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    var body: some View {
        Form {
            if tokens.isEmpty {
                mintSelectionSection
                multiMintToggleSection
                createTokenSection
            } else {
                tokenListSection
                resetSection
            }
        }
        .onAppear(perform: loadMintList)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .navigationTitle("Drain")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mintSelectionSection: some View {
        Section {
            ForEach(activeWallet?.mints ?? [], id: \.url) { mint in
                Button(action: {
                    toggleMintSelection(mint)
                }) {
                    HStack {
                        Text(mint.url.absoluteString.dropFirst(8))
                        Spacer()
                        if selectedMints.contains(mint.url.absoluteString) {
                            Image(systemName: "checkmark")
                        } else {
                            Spacer(minLength: 30)
                        }
                    }
                }
            }
        } header: {
            Text("Mints")
        } footer: {
            Text("Select all mints you would like to drain funds from.")
        }
    }

    private var multiMintToggleSection: some View {
        Section {
            Toggle("Multi mint token", isOn: $makeTokenMultiMint)
                .padding(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
        } footer: {
            Text("Some wallets may not be able to accept V3 tokens containing proofs from multiple mints.")
        }
    }

    private var createTokenSection: some View {
        Section {
            Button(role: .destructive, action: createBackupToken) {
                Text("Create Drain Token")
            }
        } footer: {
            Text("Create a token that contains all proofs of the selected mints. WARNING: This will remove the proofs from the wallet database.")
        }
        .disabled(selectedMints.isEmpty)
    }

    private var tokenListSection: some View {
        ForEach(tokens) { token in
            Section {
                TokenView(token: token)
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(action: reset) {
                HStack {
                    Text("Reset")
                    Spacer()
                    Image(systemName: "arrow.circlepath")
                }
            }
        }
    }

    private func loadMintList() {
        guard let wallet = activeWallet else { return }
        selectedMints = Set(wallet.mints.map { $0.url.absoluteString })
    }

    private func toggleMintSelection(_ mint: Mint) {
        let mintURL = mint.url.absoluteString
        if selectedMints.contains(mintURL) {
            selectedMints.remove(mintURL)
        } else {
            selectedMints.insert(mintURL)
        }
    }

    private func createBackupToken() {
        guard let wallet = activeWallet else { return } // TODO: WARNING TO USER
        tokens = []
        do {
            guard let proofs = wallet.proofs, !proofs.isEmpty else {
                displayAlert(alert: AlertDetail(title: "Empty Wallet",
                                                description: "No drain token can be created from an empty wallet."))
                return
            }

            var proofContainers: [CashuSwift.ProofContainer] = []
            for mint in wallet.mints {
                guard let proofs = mint.proofs, !proofs.isEmpty else {
                    continue
                }
                let libProofs = proofs.map { CashuSwift.Proof($0) }
                let proofContainer = CashuSwift.ProofContainer(mint: mint.url.absoluteString,
                                                               proofs: libProofs)
                proofs.forEach { $0.state = .pending }
                proofContainers.append(proofContainer)
            }

            if makeTokenMultiMint {
                let token = CashuSwift.Token(token: proofContainers, memo: "Wallet Drain")
                var sum = 0
                for proofContainer in proofContainers {
                    sum += proofContainer.proofs.sum
                }
                tokens = try [TokenInfo(token: token.serialize(.V3), mint: "Multi Mint", amount: sum)]
            } else {
                for proofContainer in proofContainers {
                    let token = CashuSwift.Token(token: [proofContainer])
                    try tokens.append(TokenInfo(token: token.serialize(.V3),
                                                mint: proofContainer.mint,
                                                amount: proofContainer.proofs.sum))
                }
            }
        } catch {
            displayAlert(alert: AlertDetail(title: "Draining Wallet unsuccessful",
                                            description: String(describing: error)))
        }
    }

    private func reset() {
        tokens = []
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct TokenView: View {
    let token: TokenInfo
    @State private var didCopy = false

    var body: some View {
        Group {
            Text(token.token)
                .fontDesign(.monospaced)
                .lineLimit(1)
            HStack {
                Text("Amount: ")
                Spacer()
                Text("\(token.amount) sat")
            }
            HStack {
                Text("Mint: ")
                Spacer()
                Text(token.mint)
            }
        }
        .foregroundStyle(.secondary)

        Button(action: { copyToClipboard(token: token.token) }) {
            HStack {
                if didCopy {
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

    private func copyToClipboard(token: String) {
        UIPasteboard.general.string = token
        withAnimation {
            didCopy = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                didCopy = false
            }
        }
    }
}

struct TokenInfo: Identifiable, Hashable {
    let token: String
    let mint: String
    let amount: Int

    var id: String { token }
}

#Preview {
    DrainView()
}
