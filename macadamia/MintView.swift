import CashuSwift
import SwiftData
import SwiftUI

struct MintView: View {
    @State var quote: CashuSwift.Bolt11.MintQuote?
    var navigationPath: Binding<NavigationPath>?
    @State var pendingMintEvent: Event?

    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }

    @State var amountString = ""
    @State var mintList = [String]()
    @State var selectedMintString = ""

    @State var loadingInvoice = false

    @State var minting = false
    @State var mintSuccess = false

    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?

    @State private var isCopied = false
    @FocusState var amountFieldInFocus: Bool

    init(quote: CashuSwift.Bolt11.MintQuote? = nil, pendingMintEvent: Event? = nil, navigationPath: Binding<NavigationPath>? = nil) {
        _quote = State(initialValue: quote)
        self.navigationPath = navigationPath
        _pendingMintEvent = State(initialValue: pendingMintEvent)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    if let quote, quote.requestDetail != nil {
                        Text(String(quote.requestDetail!.amount))
                            .monospaced()
                        Text("sats")
                            .monospaced()
                    } else {
                        TextField("enter amount", text: $amountString)
                            .keyboardType(.numberPad)
                            .monospaced()
                            .focused($amountFieldInFocus)
                            .onSubmit {
                                amountFieldInFocus = false
                            }
                            .onAppear(perform: {
                                amountFieldInFocus = true
                            })
                            .disabled(quote != nil)
                        Text("sats")
                            .monospaced()
                    }
                }
                if !mintList.isEmpty {
                    Picker("Mint", selection: $selectedMintString) {
                        ForEach(mintList, id: \.self) { mint in
                            Text(mint)
                        }
                    }
                } else {
                    Text("No mints available")
                }
            }
            if let quote {
                Section {
                    HStack {
                        Text("Expires at: ")
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(quote.expiry)).formatted())
                    }
                    .foregroundStyle(.secondary)
                    StaticQR(qrCode: generateQRCode(from: quote.request))
                        .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
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
                    Button {
                        reset()
                    } label: {
                        HStack {
                            Text("Reset")
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Mint")
        .toolbar(.hidden, for: .tabBar)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear(perform: {
            if let activeWallet {
                mintList = activeWallet.mints.map { $0.url.absoluteString } // TODO: drop leading https or http for readability
                if !mintList.isEmpty { selectedMintString = mintList.first! }
            }
        })

        if quote == nil {
            Button(action: {
                requestQuote()
                amountFieldInFocus = false
            }, label: {
                HStack {
                    if !loadingInvoice {
                        Text("Request Invoice")
                    } else {
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Loading Invoice...")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
            })
            .buttonStyle(.bordered)
            .padding()
            .disabled(amountString.isEmpty || amount == 0 || loadingInvoice)
        } else {
            Button(action: {
                requestMint()
            }, label: {
                HStack {
                    if minting {
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Minting Tokens...")
                    } else if mintSuccess {
                        Text("Success!")
                            .foregroundStyle(.green)
                    } else {
                        Text("I have paid the \(Image(systemName: "bolt.fill")) Invoice")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
            })
            .buttonStyle(.bordered)
            .padding()
            .disabled(minting || mintSuccess)
        }
    }

    // MARK: - LOGIC
    
    func copyToClipboard() {
        UIPasteboard.general.string = quote?.request
        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }

    var selectedMint: Mint? {
        activeWallet?.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) })
    }

    var amount: Int {
        return Int(amountString) ?? 0
    }

    func requestQuote() {
        
        // TODO: check continually whether the quote was paid
        
        guard let selectedMint, let activeWallet else {
            print("could not request quote: selectedMint or activeWallet are nil")
            return
        }
        
        loadingInvoice = true
        Task {
            do {
                let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: self.amount)
                quote = try await CashuSwift.getQuote(mint: selectedMint, quoteRequest: quoteRequest) as? CashuSwift.Bolt11.MintQuote
                loadingInvoice = false

                let event = Event.pendingMintEvent(unit: Unit(quote?.requestDetail?.unit) ?? .other,
                                                   shortDescription: "Mint Quote",
                                                   wallet: activeWallet,
                                                   quote: quote!, // FIXME: SAFE UNWRAPPING
                                                   amount: quote?.requestDetail?.amount ?? 0,
                                                   expiration: Date(timeIntervalSince1970: TimeInterval(quote!.expiry))) // FIXME: SAFE UNWRAPPING
                // -- main thread
                try await MainActor.run {
                    pendingMintEvent = event
                    modelContext.insert(event)
                    try modelContext.save()
                }
                
            } catch {
                displayAlert(alert: AlertDetail(title: "Error",
                                                description: String(describing: error)))
                loadingInvoice = false
            }
        }
    }

    func requestMint() {
        guard let quote,
              let activeWallet,
              let selectedMint else {
            return
        }
        
        minting = true
        Task {
            do {
                let proofs: [Proof] = try await CashuSwift.issue(for: quote, on: selectedMint, seed: activeWallet.seed).map { p in
                    let unit = Unit(quote.requestDetail?.unit ?? "other") ?? .other
                    return Proof(p, unit: unit, inputFeePPK: 0, state: .valid, mint: selectedMint, wallet: activeWallet)
                }
                
                // replace keyset to persist derivation counter
                selectedMint.increaseDerivationCounterForKeysetWithID(proofs.first!.keysetID, by: proofs.count)
                let keysetFee = selectedMint.keysets.first(where: { $0.keysetID == proofs.first?.keysetID })?.inputFeePPK ?? 0
                proofs.forEach({ $0.inputFeePPK = keysetFee })
                
                // FIXME: for some reason SwiftData does not manage the inverse relationship here, so we have to do it ourselves
                selectedMint.proofs?.append(contentsOf: proofs)
                
                try await MainActor.run {
                    proofs.forEach { modelContext.insert($0) }
                    let event = Event.mintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                                shortDescription: "Minting",
                                                wallet: activeWallet,
                                                amount: quote.requestDetail?.amount ?? 0)
                    modelContext.insert(event)
                    if let pendingMintEvent { pendingMintEvent.visible = false }
                    try modelContext.save()
                    minting = false
                    mintSuccess = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let navigationPath, !navigationPath.wrappedValue.isEmpty {
                        navigationPath.wrappedValue.removeLast()
                    }
                }
            } catch {
                displayAlert(alert: AlertDetail(title: "Error",
                                                description: String(describing: error)))
                minting = false
            }
        }
    }

    func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }

    func reset() {
        quote = nil
        amountString = ""
        minting = false
        mintSuccess = false
    }
}

#Preview {
    MintView()
}
