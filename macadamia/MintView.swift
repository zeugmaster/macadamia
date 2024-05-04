import SwiftUI

struct MintView: View {
    @ObservedObject var vm:MintViewModel
    @State private var isCopied = false
    @FocusState var amountFieldInFocus:Bool
    
//    init(vm: MintViewModel) {
//        self.vm = vm
//    }
    init(vm:MintViewModel) {
        self.vm = vm
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("enter amount", text: $vm.amountString)
                        .keyboardType(.numberPad)
                        .monospaced()
                        .focused($amountFieldInFocus)
                        .onSubmit {
                            amountFieldInFocus = false
                        }
                        .onAppear(perform: {
                            amountFieldInFocus = true
                        })
                        .disabled(vm.quote != nil)
                    Text("sats")
                        .monospaced()
                }
                if !vm.mintList.isEmpty && !vm.selectedMintString.isEmpty {
                    Picker("Mint", selection: $vm.selectedMintString) {
                        ForEach(vm.mintList, id: \.self) { mint in
                            Text(mint)
                        }
                    }
                } else {
                    Text("No mints available")
                }
            }
            if vm.quote != nil {
                Section {
                    StaticQR(qrCode: generateQRCode(from: vm.quote!.pr))
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
                        vm.reset()
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
        .alert(vm.currentAlert?.title ?? "Error", isPresented: $vm.showAlert) {
            Button(role: .cancel) {
                
            } label: {
                Text(vm.currentAlert?.primaryButtonText ?? "OK")
            }
            if vm.currentAlert?.onAffirm != nil &&
                vm.currentAlert?.affirmText != nil {
                Button(role: .destructive) {
                    vm.currentAlert!.onAffirm!()
                } label: {
                    Text(vm.currentAlert!.affirmText!)
                }
            }
        } message: {
            Text(vm.currentAlert?.alertDescription ?? "")
        }
        .onAppear(perform: {
            vm.fetchMintList()
        })
        
        if vm.quote == nil {
            Button(action: {
                vm.requestInvoice()
                amountFieldInFocus = false
            }, label: {
                HStack {
                    if !vm.loadingInvoice {
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
            .disabled(vm.amountString.isEmpty || vm.amount == 0 || vm.loadingInvoice)
        } else {
            Button(action: {
                vm.requestMint()
            }, label: {
                HStack {
                    if vm.minting {
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Minting Tokens...")
                    } else if vm.mintSuccess {
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
            .disabled(vm.minting || vm.mintSuccess)
        }
    }
    
    func copyToClipboard() {
        vm.copyInvoice()
        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
//
//#Preview {
//    MintView(vm: MintViewModel())
//}

@MainActor
class MintViewModel:ObservableObject {
    
    @Published var amountString = ""
    @Published var mintList = [""]
    @Published var selectedMintString = ""
    
    @Published var quote:QuoteRequestResponse?
    @Published var loadingInvoice = false
    
    @Published var minting = false
    @Published var mintSuccess = false
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    var wallet = Wallet.shared
    
    private var _navPath: Binding<NavigationPath>  // Changed to non-optional
        
    init(navPath: Binding<NavigationPath>) {
        self._navPath = navPath
    }
    
    var navPath: NavigationPath {
        get { _navPath.wrappedValue }
        set { _navPath.wrappedValue = newValue }
    }
    
    func fetchMintList() {
        mintList = wallet.database.mints.map { mint in
            String(mint.url.absoluteString.dropFirst(8))
        }
        if let initial = mintList.first {
            selectedMintString = initial
        }
    }
    
    var selectedMint:Mint {
        wallet.database.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) })!
    }
    
    var amount: Int {
        return Int(amountString) ?? 0
    }
    
    func copyInvoice() {
        UIPasteboard.general.string = quote?.pr
    }
    
    func requestInvoice() {
        loadingInvoice = true
        Task {
            do {
                quote = try await wallet.getQuote(from: selectedMint, for: amount)
                loadingInvoice = false
            } catch {
                displayAlert(alert: AlertDetail(title: "Error",
                                               description: String(describing: error)))
                loadingInvoice = false
            }
        }
    }
    
    func requestMint() {
        guard let quote = quote else {
            return
        }
        minting = true
        Task {
            do {
                try await wallet.requestMint(from: selectedMint, for: quote, with: amount)
                minting = false
                mintSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !self.navPath.isEmpty { self.navPath.removeLast() }
                }
            } catch {
                displayAlert(alert: AlertDetail(title: "Error",
                                                description: String(describing: error)))
                minting = false
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
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
