//
//  MintRequestView.swift
//  macadamia
//
//  Created by zeugmaster on 14.12.23.
//

import SwiftUI

struct MintRequestView: View {
    @ObservedObject var viewmodel: MintRequestViewModel
    @Binding var navigationPath:NavigationPath
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("enter amount", text: $viewmodel.numberString)
                        .keyboardType(.numberPad)
                        .monospaced()
                    Text("sats")
                }
                Picker("Mint", selection:$viewmodel.selectedMintString) {
                    ForEach(viewmodel.mintList, id: \.self) {
                        Text($0)
                    }
                }.onAppear(perform: {
                    viewmodel.fetchMintInfo()
                })
            }
        }
        .navigationTitle("Mint")
        .navigationBarTitleDisplayMode(.inline)
        Spacer()
        Button(action: {
            navigationPath.append("Second")
        }, label: {
            Text("Request \(Image(systemName: "bolt.fill")) Invoice")
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
        })
        .buttonStyle(.bordered)
        .padding()
        .toolbar(.hidden, for: .tabBar)
        .disabled(viewmodel.numberString.isEmpty || viewmodel.amount == 0)
    }
}
//
//#Preview {
//    MintRequestView()
//}


//MARK: -

struct MintRequestInvoiceView: View {
    @ObservedObject var viewmodel:MintRequestViewModel
    @Binding var navigationPath:NavigationPath
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                TextField("", text: $viewmodel.invoiceString)
                    .textFieldStyle(PlainTextFieldStyle())
                    .dynamicTypeSize(.xxLarge)
                    .disabled(true)
                    .foregroundColor(.secondary)
                    .monospaced()
                    .multilineTextAlignment(.center)
                Button {
                    viewmodel.copyToClipboard()
                } label: {
                    Image(systemName: "list.clipboard")
                        .dynamicTypeSize(.xxxLarge)
                }
                .disabled(viewmodel.loadingInvoice)
            }
            .padding(EdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 40
                               ))
            if viewmodel.loadingInvoice {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding(80)
                    .scaleEffect(CGSize(width: 2.0, height: 2.0))
            } else if viewmodel.invoiceString != "loading..." {
                QRCodeView(qrCode: generateQRCode(from: viewmodel.invoiceString))
                    .padding(40)
            }
                
            Spacer()
            Button {
                navigationPath.append("Third")
            } label: {
                Text("I have paid the \(Image(systemName: "bolt.fill")) Invoice")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .bold()
                    .foregroundColor(.white)
            }
            .buttonStyle(.bordered)
            .padding()
            .toolbar(.hidden, for: .tabBar)
        }
        .onAppear(perform: {
            viewmodel.requestQuote()
        })
    }
}

struct MintRequestCompletionView: View {
    @ObservedObject var viewModel: MintRequestViewModel
    @Binding var navigationPath:NavigationPath
    
    var body: some View {
        Text(viewModel.mintRequestState).onAppear(perform: {
            viewModel.requestMinting()
        })
        Spacer()
        Button(action: {
            navigationPath.removeLast(3)
        }, label: {
            Text("Back to Wallet")
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
        })
        .buttonStyle(.bordered)
        .padding()
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(viewModel.success)
    }
}

//#Preview {
//    MintRequestInvoiceView(viewmodel: MintRequestViewModel())
//}


@MainActor
class MintRequestViewModel: ObservableObject {
    @Published var numberString: String = ""
    @Published var mintList:[String] = [""]
    @Published var selectedMintString:String = ""
    @Published var loadingInvoice = true
    @Published var invoiceString = "loading..."
    @Published var errorToDisplay:Error?
    @Published var mintRequestState = "loading..."
    
    @Published var success = false
    
    private var wallet = Wallet.shared
    private var selectedMint:Mint?
    private var quote:QuoteRequestResponse?
    
    var amount: Int {
        return Int(numberString) ?? 0
    }
    
    func fetchMintInfo() {
        mintList = []
        for mint in wallet.database.mints {
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
        selectedMintString = mintList[0]
    }
    
    func requestQuote() {
        loadingInvoice = true
        selectedMint = wallet.database.mints.first(where: {$0.url.absoluteString.contains(selectedMintString)})!
        
        Task {
            do {
                quote = try await wallet.getQuote(from:selectedMint!, for:amount)
                invoiceString = quote!.pr
                loadingInvoice = false
                
            } catch {
                errorToDisplay = error
            }
            
        }
    }
    
    func copyToClipboard() {
        UIPasteboard.general.string = invoiceString
    }
    
    func requestMinting() {
        Task {
            do {
                try await wallet.requestMint(from:selectedMint!,for:quote!,with:amount)
                mintRequestState = "Success"
                success = true
            } catch {
                mintRequestState = String(describing: error)
            }
        }
    }
}
