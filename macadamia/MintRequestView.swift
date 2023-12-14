//
//  MintRequestView.swift
//  macadamia
//
//  Created by Dario Lass on 14.12.23.
//

import SwiftUI

struct MintRequestView: View {
    
    @StateObject var viewmodel = MintRequestViewModel()
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("enter amount", text: $viewmodel.numberString)
                        .keyboardType(.numberPad)
                        .monospaced()
                    Text("sats")
                }
                Picker("Mint", selection:$viewmodel.selectedMint) {
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
        NavigationLink(destination: MintRequestInvoiceView()) {
            Text("Request \(Image(systemName: "bolt.fill")) Invoice")
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
        }
        .buttonStyle(.bordered)
        .padding()
        .toolbar(.hidden, for: .tabBar)
        .disabled(viewmodel.numberString.isEmpty)
    }
}

#Preview {
    MintRequestView()
}

class MintRequestViewModel: ObservableObject {
    @Published var numberString: String = ""
    @Published var mintList:[String] = [""]
    @Published var selectedMint:String = ""
    
    private var wallet = Wallet.shared
    
    var amount: Int? {
        return Int(numberString)
    }
    
    func fetchMintInfo() {
        print("fetch")
        for mint in wallet.database.mints {
            mintList = []
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
        selectedMint = mintList[0]
    }
}

//MARK: -

struct MintRequestInvoiceView: View {
    //@StateObject var viewmodel = MintRequestViewModel()
    
    @State private var text = "cashuAeialwurt0984u3q0üjpifjpq083u4tüpifjr3"
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                TextField("Enter text", text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .dynamicTypeSize(.xxLarge)
                    .disabled(true)
                    .foregroundColor(.secondary)
                    .monospaced()
                Button(action: copyToClipboard) {
                    Image(systemName: "list.clipboard")
                        .dynamicTypeSize(.xxxLarge)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 40
                               ))
            
            QRCodeView(qrCode: generateQRCode(from: "lnbc210n1pjhkfs0pp5qh2zr8w7vhjfvazgk2f06nv9y8j0fvrye9kz2yf0fpj2muzs35vscqpjsp5te6ukpn9xpcrktv0wvah3pn0lkcv9ks46hl22u9hvkc28wvmfqcs9q7sqqqqqqqqqqqqqqqqqqqsqqqqqysgqdqqmqz9gxqyjw5qrzjqwryaup9lh50kkranzgcdnn2fgvx390wgj5jd07rwr3vxeje0glcllezhk2zechxl5qqqqlgqqqqqeqqjq9yuxv8tagxhtgqkjclc8sc6xxkcxhxdy8m4nn0kjxl04sux2032swckkxc0hj3c5llm5c5pkvqg28mvqy50v5ana6zdkd6zstf46vhsphnxtw3"))
                .padding(40)
                
            Spacer()
            NavigationLink(destination: Text("bing, like a rocketship")) {
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
        
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = text
    }
    
}

#Preview {
    MintRequestInvoiceView()
}
