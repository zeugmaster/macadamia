//
//  MeltView.swift
//  macadamia
//
//  Created by zeugmaster on 05.01.24.
//

import CashuSwift
import CodeScanner
import SwiftData
import SwiftUI

struct MeltView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }

    @State var quote: CashuSwift.Bolt11.MeltQuote?
    @State var pendingMeltEvent: Event?

    @State var invoiceString: String = ""
    @State var loading = false
    @State var success = false

    @State var mintList: [String] = [""]
    @State var selectedMintString: String = ""
    @State var selectedMintBalance = 0

    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?

    var navigationPath: Binding<NavigationPath>? // Changed to non-optional

    init(quote: CashuSwift.Bolt11.MeltQuote? = nil,
         pendingMeltEvent: Event? = nil,
         navigationPath: Binding<NavigationPath>? = nil)
    {
        self.navigationPath = navigationPath
        self.pendingMeltEvent = pendingMeltEvent
        self.quote = quote
    }

    var body: some View {
        VStack {
            // MARK: This check is necessary to prevent a bug in URKit (or the system, who knows)

            // MARK: from crashing the app when using the camera on an Apple Silicon Mac

            if !ProcessInfo.processInfo.isiOSAppOnMac {
                CodeScannerView(codeTypes: [.qr], scanMode: .oncePerCode) { result in
                    print(result)
                    processScanViewResult(result: result)
                }
                .padding()
            }
            List {
                Section {
                    TextField("tap to enter LN invoice", text: $invoiceString)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .onSubmit {
                            getQuote()
                        }
                    if !invoiceString.isEmpty {
                        HStack {
                            Text("Amount: ")
                            Spacer()
                            Text(String(invoiceAmount ?? 0) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        if quote != nil {
                            HStack {
                                Text("Lightning Fee: ")
                                Spacer()
                                Text(String(quote?.feeReserve ?? 0) + " sats")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Mint", selection: $selectedMintString) {
                        ForEach(mintList, id: \.self) {
                            Text($0)
                        }
                    }.onAppear(perform: {
                        fetchMintInfo()
                    })
                    .onChange(of: selectedMintString) { _, _ in
                        updateBalance()
                    }
                    HStack {
                        Text("Balance: ")
                        Spacer()
                        Text(String(selectedMintBalance))
                            .monospaced()
                        Text("sats")
                    }
                    .foregroundStyle(.secondary)
                } footer: {
                    Text("The invoice will be payed by the mint you select.")
                }
            }
            Button(action: {
                melt()
            }, label: {
                if loading {
                    Text("Melting...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if success {
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Melt Tokens")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(invoiceString.isEmpty || loading || success)
            .navigationTitle("Melt")
            .navigationBarTitleDisplayMode(.inline)
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        }
    }

    var selectedMint: Mint? {
        activeWallet?.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) })
    }

    func processScanViewResult(result: Result<ScanResult, ScanError>) {
        guard var text = try? result.get().string.lowercased() else {
            return
        }
        if text.hasPrefix("lightning:") {
            text.removeFirst("lightning:".count)
        }
        guard text.hasPrefix("lnbc") else {
            displayAlert(alert: AlertDetail(title: "Invalid QR",
                                            description: "The QR code you scanned does not seem to be of a valid Lighning Network invoice. Please try again."))
            return
        }
        invoiceString = text
        getQuote()
    }

    func updateBalance() {
        guard let activeWallet,
              let selectedMint
        else {
            return
        }
        selectedMintBalance = selectedMint.proofs.sum
    }

    var invoiceAmount: Int? {
        try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString)
    }

    func getQuote() {
        guard let activeWallet,
              let selectedMint
        else {
            print("unable to get quote, activeWallet or selectedMint is nil")
            return
        }

        Task {
            quote = try await CashuSwift.getQuote(mint: selectedMint,
                                                  quoteRequest: CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", // TODO: REMOVE HARD CODED UNIT
                                                                                                   request: invoiceString,
                                                                                                   options: nil)) as? CashuSwift.Bolt11.MeltQuote
        }
    }

    func fetchMintInfo() {
        guard let activeWallet else {
            return
        }

        for mint in activeWallet.mints {
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
        selectedMintString = mintList[0]
    }

    func melt() {
        guard let selectedMint,
              let activeWallet,
              let quote
        else {
            return
        }

//        #error("1. handle pending melt with quote")

//        #error("3. handle proofs -> pending and success event")

        let worstInputFee = (CashuSwift.activeKeysetForUnit("sat", mint: selectedMint)?.inputFeePPK ?? 0 * worstCaseInputCount(for: UInt(quote.amount + quote.feeReserve)) + 999) / 1000
        let targetAmount = quote.amount + quote.feeReserve + worstInputFee

        // TODO: ADD FEE AMOUNT UI AND INFO

        guard let selection = CashuSwift.pick(selectedMint.proofs, amount: targetAmount, mint: selectedMint) else {
            displayAlert(alert: AlertDetail(title: "Insufficient funds.",
                                            description: "The wallet could not collect enough ecash to settle this payment."))
            return
        }

        let proofsToSent = selection.selected.map { $0 as! Proof }

        proofsToSent.forEach { $0.state = .pending }
        #warning("make sure this actually updates the DB")

        // create a pending melt event that

        // SAVE AT THIS POINT

        loading = true

        Task {
            do {
                let meltResult = try await CashuSwift.melt(mint: selectedMint, quote: quote, proofs: proofsToSent, seed: activeWallet.seed)
                // TODO: WHILE THIS IS RUNNING KEEP SCREEN OPEN

                if meltResult.paid {
                    loading = false
                    success = true

                    proofsToSent.forEach { $0.state = .spent }

                    // make pending melt event non visible and create melt event for history

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if let navigationPath, !navigationPath.wrappedValue.isEmpty {
                            navigationPath.wrappedValue.removeLast()
                        }
                    }
                } else {
                    // pending event remains

                    proofsToSent.forEach { $0.state = .valid }

                    loading = false
                    success = false
                    displayAlert(alert: AlertDetail(title: "Unsuccessful",
                                                    description: "The Lighning invoice could not be payed by the mint. Please try again (later)."))
                }
            } catch {
                // pending event also remains
                // TODO: UI for when quote expires etc.

                loading = false
                success = false
                displayAlert(alert: AlertDetail(title: "Error",
                                                description: String(describing: error)))
            }
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }

    func worstCaseInputCount(for n: UInt) -> Int {
        guard n > 0 else { return 1 }

        let bitsNeeded = n.bitWidth - n.leadingZeroBitCount
        let isPowerOfTwo = (n & (n - 1)) == 0
        let maxBitsInRange = isPowerOfTwo ? bitsNeeded : bitsNeeded
        return maxBitsInRange + 1
    }
}

#Preview {
    MeltView()
}
