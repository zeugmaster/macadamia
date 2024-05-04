//
//  MintManagerView.swift
//  macadamia
//
//  Created by zeugmaster on 01.01.24.
//

import SwiftUI

struct MintManagerView: View {
    @ObservedObject var vm = MintManagerViewModel()
    
    var body: some View {
        List {
            Section {
                ForEach(vm.mintList, id: \.url) { mint in
                    HStack {
                        Circle()
                            .foregroundColor(.green)
                            .frame(width: 10, height: 8)
                        Text(mint.url.absoluteString)
                    }
                }
                .onDelete(perform: { indexSet in
                    vm.removeMint(at:indexSet)
                })
                TextField("enter new Mint URL", text: $vm.newMintURLString)
                    .onSubmit {vm.addMintWithUrlString() }
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("Swipe to delete. Make sure to add correct prefix and port numbers to mint URLs. Pressing RETURN  will add the mint URL")
            }
        }
        .alertView(isPresented: $vm.showAlert, currentAlert: vm.currentAlert)
    }
}

@MainActor
class MintManagerViewModel: ObservableObject {
    @Published var mintList = [Mint]()
    @Published var error:Error?
    @Published var newMintURLString = ""
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    var wallet = Wallet.shared
        
    init() {
        self.mintList = wallet.database.mints
    }
    
    func addMintWithUrlString() {
        // needs to check for uniqueness and URL format
        
        
        
        guard let url = URL(string: newMintURLString),
            newMintURLString.contains("https://") else {
            newMintURLString = ""
            displayAlert(alert: AlertDetail(title: "Invalid URL", 
                                            description: "The URL you entered was not valid. Make sure it uses correct formatting as well as the right prefix."))
            return
        }
        
        guard !mintList.contains(where: { $0.url.absoluteString == newMintURLString }) else {
            displayAlert(alert: AlertDetail(title: "Already added.",
                                           description: "This URL is already in the list of knowm mints, please choose another one."))
            newMintURLString = ""
            return
        }
        
        Task {
            do {
                try await wallet.addMint(with:url)
                mintList = wallet.database.mints
                newMintURLString = ""
            } catch {
                displayAlert(alert: AlertDetail(title: "Could not be added",
                                                description: "The mint with this URL could not be added. \(error)"))
                newMintURLString = ""
            }
        }
        
        
    }
    
    func removeMint(at offsets: IndexSet) {
        //TODO: CHECK FOR BALANCE
        if true {
            displayAlert(alert: AlertDetail(title: "Are you sure?",
                                           description: "Are you sure you want to delete it?",
                                            primaryButtonText: "Cancel",
                                           affirmText: "Yes",
                                            onAffirm: {
                // should actually never be more than one index at a time
                offsets.forEach { index in
                    let url = self.mintList[index].url
                    self.mintList.remove(at: index)
                    self.wallet.removeMint(with: url)
                }
            }))
        } else {
            offsets.forEach { index in
                let url = self.mintList[index].url
                self.mintList.remove(at: index)
                self.wallet.removeMint(with: url)
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    MintManagerView()
}
