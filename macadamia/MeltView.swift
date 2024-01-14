//
//  MeltView.swift
//  macadamia
//
//  Created by zeugmaster on 05.01.24.
//

import SwiftUI
import CodeScanner

struct MeltView: View {
    @ObservedObject var vm = MeltViewModel()
    
    var body: some View {
        VStack {
            CodeScannerView(codeTypes: [.qr], scanMode: .oncePerCode) { result in
                print(result)
                vm.processScanViewResult(result: result)
            }
            .padding()
            List {
                Section {
                    TextField("tap to enter LN invoice", text: $vm.invoice)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .onSubmit() {
                            vm.checkFee()
                        }
                    if !vm.invoice.isEmpty {
                        HStack {
                            Text("Amount: ")
                            Spacer()
                            Text(String(vm.invoiceAmount ?? 0) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        if vm.fee != nil {
                            HStack {
                                Text("Lightning Fee: ")
                                Spacer()
                                Text(String(vm.fee ?? 0) + " sats")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Mint", selection:$vm.selectedMintString) {
                        ForEach(vm.mintList, id: \.self) {
                            Text($0)
                        }
                    }.onAppear(perform: {
                        vm.fetchMintInfo()
                    })
                    .onChange(of: vm.selectedMintString) { oldValue, newValue in
                        vm.updateBalance()
                    }
                    HStack {
                        Text("Balance: ")
                        Spacer()
                        Text(String(vm.selectedMintBalance))
                            .monospaced()
                        Text("sats")
                    }
                    .foregroundStyle(.secondary)
                } footer: {
                    Text("The invoice will be payed by the mint you select.")
                }
            }
            Button(action: {
                vm.melt()
            }, label: {
                if vm.loading {
                    Text("Melting...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if vm.success {
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
            .disabled(vm.invoice.isEmpty || vm.loading || vm.success)
            .navigationTitle("Melt")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }
}

#Preview {
    MeltView()
}


@MainActor
class MeltViewModel: ObservableObject {
    
    @Published var invoice:String = ""
    
    @Published var loading = false
    @Published var success = false
//    @Published var invoiceAmount:Int?
    
    @Published var fee:Int?
    
    @Published var mintList:[String] = [""]
    @Published var selectedMintString:String = ""
    @Published var selectedMintBalance = 0
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    var wallet = Wallet.shared
    
    func processScanViewResult(result:Result<ScanResult,ScanError>) {
        guard let value = try? result.get() else {
            return
        }
        guard value.string.lowercased().hasPrefix("lnbc") else {
            displayAlert(alert: AlertDetail(title: "Invalid QR",
                                           description: "The QR code you scanned does not seem to be of a valid Lighning Network invoice. Please try again."))
            return
        }
        invoice = value.string.lowercased()
        checkFee()
    }
    
    func updateBalance() {
        if let mint = wallet.database.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) }) {
            selectedMintBalance = wallet.balance(mint: mint)
        }
    }
    
    var invoiceAmount:Int? {
        try? QuoteRequestResponse.satAmountFromInvoice(pr: invoice)
    }
    
    func checkFee() {
        Task {
            let selectedMint = wallet.database.mints.first(where: {$0.url.absoluteString.contains(selectedMintString)})!
            fee = try? await Network.checkFee(mint: selectedMint, invoice: invoice)
        }
    }
    
    func fetchMintInfo() {
        mintList = []
        for mint in wallet.database.mints {
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
        selectedMintString = mintList[0]
    }
    
    func melt() {
        let selectedMint = wallet.database.mints.first(where: {$0.url.absoluteString.contains(selectedMintString)})!
        loading = true
        Task {
            do {
                let invoicePaid = try await wallet.melt(mint: selectedMint, invoice: invoice)
                if invoicePaid {
                    loading = false
                    success = true
                } else {
                    loading = false
                    success = false
                    displayAlert(alert: AlertDetail(title: "Unsuccessful",
                                                   description: "The Lighning invoice could not be payed by the mint. Please try again (later)."))
                }
            } catch {
                loading = false
                success = false
                displayAlert(alert: AlertDetail(title: "Error",
                                               description: String(describing: error)))
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
