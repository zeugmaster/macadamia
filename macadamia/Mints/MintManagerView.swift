import CashuSwift
import SwiftData
import SwiftUI

struct MintManagerView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var mints: [Mint]
    
    @Query(animation: .default) private var allProofs: [Proof]
    
    @State private var balanceStrings = [UUID: String?]()
    
    @State var newMintURLString = ""
    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var sortedMintsOfActiveWallet: [Mint] {
        mints.filter({ $0.wallet == activeWallet && $0.hidden == false})
             .sorted(by: { $0.userIndex ?? 0 < $1.userIndex ?? 0})
    }

    var body: some View {
        NavigationView {
            if let _ = activeWallet {
                Form {
                    if !mints.isEmpty {
                        Section {
                            List {
                                ForEach(sortedMintsOfActiveWallet) { mint in
                                    NavigationLink(destination: MintInfoView(mint: mint)) {
                                        // Pass proofs related to the mint to MintInfoRowView
                                        MintInfoRowView(mint: mint,
                                                        amountDisplayString: balanceStrings[mint.mintID] ?? nil)
                                    }
                                }
                                .onMove { source, destination in
                                    var m = sortedMintsOfActiveWallet
                                    m.move(fromOffsets: source, toOffset: destination)
                                    for (index, mint) in m.enumerated() {
                                        mint.userIndex = index
                                    }
                                    
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Error saving order: \(error)")
                                    }
                                }
                            }
                        } footer: {
                            Text("""
                                 Hold and drag to change the order. The first mint will be \
                                 the default selected across the application.
                                 """)
                        }
                    }
                    Section {
                        TextField("Add new Mint URL...", text: $newMintURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onSubmit {
                                addMint(urlString: newMintURLString)
                            }
                    } footer: {
                        Text("""
                             Enter a URL to add a new mint to the wallet, hit Return to save. 
                             macadamia Wallet is not affiliated with any mint and does not custody user funds. 
                             You can find a list of mints on [bitcoinmints.com](https://bitcoinmints.com)
                             """)
                    }
                    .onTapGesture(count: 3) {
                        addMint(urlString: "https://testmint.macadamia.cash")
                        addMint(urlString: "https://testnut.cashu.space")
                    }
                }
                .navigationTitle("Mints")
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text(currentAlert?.title ?? "Error"),
                        message: Text(currentAlert?.alertDescription ?? "An unknown error occurred"),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .onAppear {
                    calculateBalanceStrings()
                    reIndex()
                }
            } else {
                Text("No wallet initialized yet.")
            }
        }
    }
    
    func calculateBalanceStrings() {
        balanceStrings = activeWallet!.mints.reduce(into: [UUID: String?]()) { result, mint in
            let proofsOfMint = allProofs.filter({ $0.mint == mint && $0.state == .valid })
            let sumsByUnit = proofsOfMint.reduce(into: [Unit: Int]()) { result, proof in
                result[proof.unit, default: 0] += proof.amount
            }
            result[mint.mintID] = sumsByUnit.isEmpty ? nil : sumsByUnit.map { (unit, amount) in
                "\(amount) \(unit.rawValue)"
            }.joined(separator: " | ")
        }
    }
    
    func proofsForMint(_ mint: Mint) -> [Proof] {
        return allProofs.filter { proof in
            proof.mint == mint && proof.state == .valid
        }
    }

    func addMint(urlString: String) {
        guard let activeWallet else {
            return
        }
        
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedURLString.starts(with: "http://") || trimmedURLString.starts(with: "https://"),
              let url = URL(string: trimmedURLString), url.host != nil else {
            logger.warning("user tried to add a URL that does not start with https:// or http:// which is not supported")
            displayAlert(alert: AlertDetail(title: "Invalid URL",
                                            description: """
                                                         URL must start with http:// or https:// \
                                                         and include a valid host.
                                                         """))
            return
        }
        
        if let knownMint = activeWallet.mints.first(where: { $0.url.absoluteString == trimmedURLString && $0.hidden == true}) {
            // unhide and re-index
            logger.info("user added mint that is already known. \(knownMint.url.absoluteString)")
            knownMint.userIndex = activeWallet.mints.filter({ $0.hidden == false }).count
            knownMint.hidden = false
            newMintURLString = ""
            
            try? modelContext.save()
            return
        }
        
        guard !activeWallet.mints.contains(where: { $0.url == url }) else {
            logger.warning("user tried to add a mint with a url that is already in the list of mints.")
            displayAlert(alert: AlertDetail(title: "Duplicate Mint",
                                            description: """
                                                         The mint you are trying to add is already \
                                                         known to the wallet. Please add each mint only once.
                                                         """))
            return
        }

        Task {
            do {
                let sendableMint = try await CashuSwift.loadMint(url: url)
                try await MainActor.run {
                    let mint = Mint(url: sendableMint.url, keysets: sendableMint.keysets)
                    mint.wallet = activeWallet
                    mint.userIndex = activeWallet.mints.count - 1
                    modelContext.insert(mint)
                    try modelContext.save()
                    logger.info("added new mint with URL \(mint.url.absoluteString)")
                    newMintURLString = ""
                }
            } catch {
                logger.error("could not add mint due to error \(error)")
                DispatchQueue.main.async {
                    displayAlert(alert: AlertDetail(title: "Could not add mint.",
                                                    description: """
                                                                 The wallet was unable to load this mint's keysets. 
                                                                 Please make sure the URL is correct and 
                                                                 the mint online, then try again.
                                                                 """))
                }
            }
        }
    }
    
    // fixes wrong indexing
    private func reIndex() {
        var current = 0
        for mint in sortedMintsOfActiveWallet {
            mint.userIndex = current
            current += 1
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct MintInfoRowView: View {
    let mint: Mint
    let amountDisplayString: String?

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

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
                Text(mint.nickName ?? mint.url.host(percentEncoded: false) ?? mint.url.absoluteString)
                    .bold()
                    .dynamicTypeSize(.xLarge)
                Text(amountDisplayString ?? "No Balance")
                    .foregroundStyle(.gray)
            }
//            Spacer()
//            Text(String(mint.userIndex ?? 404))
        }
    }
}

