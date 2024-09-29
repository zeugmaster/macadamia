import SwiftUI
import CashuSwift
import SwiftData

struct MintView: View {
    @State var quote:CashuSwift.Bolt11.MintQuote?
    var navigationPath:Binding<NavigationPath>?
    
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
        
    var activeWallet:Wallet? {
        get {
            wallets.first
        }
    }
    
    @State var amountString = ""
    @State var mintList = [String]()
    @State var selectedMintString = ""
    
    @State var loadingInvoice = false
    
    @State var minting = false
    @State var mintSuccess = false
    
    @State var showAlert:Bool = false
    @State var currentAlert:AlertDetail?
    
    @State private var isCopied = false
    @FocusState var amountFieldInFocus:Bool
    
    init(quote:CashuSwift.Bolt11.MintQuote? = nil, navigationPath: Binding<NavigationPath>? = nil) {
        self.quote = quote
        self.navigationPath = navigationPath
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
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
            if quote != nil {
                Section {
                    StaticQR(qrCode: generateQRCode(from: quote!.request))
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
                mintList = activeWallet.mints.map( { $0.url.absoluteString } ) // TODO: drop leading https or http for readability
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
    
    var selectedMint:Mint? {
        activeWallet?.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) })
    }
    
    var amount: Int {
        return Int(amountString) ?? 0
    }
    
    func requestQuote() {
        guard let selectedMint,
              let activeWallet else {
            return
        }
        loadingInvoice = true
        Task {
            do {
                let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: self.amount)
                quote = try await CashuSwift.getQuote(mint: selectedMint, quoteRequest: quoteRequest) as? CashuSwift.Bolt11.MintQuote
                loadingInvoice = false
                
                #warning("add quote to transactions")
                
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
                let proofs:[Proof] = try await CashuSwift.issue(for: quote, on: selectedMint).map { p in
                    let unit = Unit(quote.requestDetail?.unit ?? "other") ?? .other
                    return Proof(p, unit: unit, state: .valid, mint: selectedMint, wallet: activeWallet)
                }
//                activeWallet.proofs.append(contentsOf: proofs)
                proofs.forEach({ modelContext.insert($0) })
                try modelContext.save()
                minting = false
                mintSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if var navigationPath {
                        #warning("pretty sure this does nothing in the UI")
                        if !navigationPath.wrappedValue.isEmpty {
                            navigationPath.wrappedValue.removeLast()
                        }
                    }
                }
                
                #warning("convert pending transaction to completed")
                
            } catch {
                displayAlert(alert: AlertDetail(title: "Error",
                                                description: String(describing: error)))
                minting = false
            }
        }
    }
    
    func displayAlert(alert:AlertDetail) {
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
