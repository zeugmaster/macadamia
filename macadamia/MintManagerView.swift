import CashuSwift
import SwiftData
import SwiftUI

struct MintManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @Query private var allProofs: [Proof]  // All proofs are monitored

    @State var newMintURLString = ""
    @State var showAlert: Bool = false

    @State var currentAlert: AlertDetail?

    var activeWallet: Wallet? {
        wallets.first
    }

    var body: some View {
        NavigationView {
            if let activeWallet {
                Form {
                    Section {
                        List(activeWallet.mints, id: \.url) { mint in
                            NavigationLink(destination: MintDetailView(mint: mint)) {
                                // Pass proofs related to the mint to MintInfoRowView
                                MintInfoRowView(mint: mint, proofs: proofsForMint(mint))
                            }
                        }
                    }
                    Section {
                        TextField("Add new Mint URL...", text: $newMintURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onSubmit {
                                addMint()
                            }
                    } footer: {
                        Text("Enter a URL to add a new mint to the wallet, hit Return to save.")
                    }
                }
                .navigationTitle("Mints")
                .onAppear {
                    print("MintManagerView appeared")
                }
            } else {
                Text("No wallet initialized yet.")
            }
        }
    }

    // Filter proofs for a specific mint
    func proofsForMint(_ mint: Mint) -> [Proof] {
        allProofs.filter { $0.mint == mint && $0.state == .valid }
    }

    func addMint() {
        let trimmedURLString = newMintURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedURLString.starts(with: "http://") || trimmedURLString.starts(with: "https://"),
              let url = URL(string: trimmedURLString), url.host != nil else {
            displayAlert(alert: AlertDetail(title: "Invalid URL", description: "URL must start with http:// or https:// and include a valid host"))
            return
        }

        Task {
            do {
                let mint = try await CashuSwift.loadMint(url: url, type: Mint.self)
                mint.wallet = activeWallet
                modelContext.insert(mint)
                try modelContext.save()
                DispatchQueue.main.async {
                    newMintURLString = ""
                }
            } catch {
                DispatchQueue.main.async {
                    displayAlert(alert: AlertDetail(title: "Could not add mint.", description: String(describing: error)))
                }
            }
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct MintInfoRowView: View {
    var mint: Mint
    var proofs: [Proof]  // Pass the relevant proofs

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    // Calculate balances from the provided proofs
    var sumsByUnit: [Unit: Int] {
        proofs.reduce(into: [Unit: Int]()) { result, proof in
            result[proof.unit, default: 0] += proof.amount
        }
    }

    // Format the sums for display
    var stringForSums: String? {
        if sumsByUnit.isEmpty { return "No Balance" }
        return sumsByUnit.map { (unit, amount) in
            "\(amount) \(unit.rawValue)"
        }.joined(separator: " | ")
    }

    var body: some View {
        HStack {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "building.columns")
                    .foregroundColor(.white)
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(mint.url.host(percentEncoded: false)!)
                    .bold()
                    .dynamicTypeSize(.xLarge)
                Text(stringForSums ?? "No Balance")
                    .foregroundStyle(.gray)
            }
        }
    }
}
