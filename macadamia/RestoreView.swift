//
//  RestoreView.swift
//  macadamia
//
//  Created by Dario Lass on 06.01.24.
//

import SwiftUI

struct RestoreView: View {
    @ObservedObject var vm = RestoreViewModel()
    
    var body: some View {
        List {
            Section {
                TextField("Enter seed phrase", text: $vm.mnemonic, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
            } footer: {
                Text("Enter your 12 word seed phrase, separated by spaces or line breaks. Please also make sure that your mint list contains all the mints you want to try restoring from.")
            }
        }
        Button(action: {
            vm.attemptRestore()
        }, label: {
            HStack(spacing:0) {
                Spacer()
                if vm.loading {
                    ProgressView()
                    Text("Restoring...")
                        .padding()
                } else if vm.success {
                    Text("Done!")
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Restore")
                    .padding()
                }
                Spacer()
            }
        })
        .frame(maxWidth: .infinity)
        .foregroundColor(.white)
        .buttonStyle(.bordered)
        .padding()
        .bold()
        .toolbar(.hidden, for: .tabBar)
        .disabled(vm.mnemonic.isEmpty || vm.loading || vm.success)
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(vm.loading)
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

#Preview {
    RestoreView()
}

@MainActor
class RestoreViewModel:ObservableObject {
    
    @Published var mnemonic = ""
    @Published var loading = false
    @Published var success = false
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    var wallet = Wallet.shared
    
    func attemptRestore() {
        guard wallet.database.mnemonic != mnemonic else {
            displayAlert(alert: AlertDetail(title: "Already in use",
                                           description: "The seed phrase you entered is the same as the one already in use for this wallet."))
            return
        }
        Task {
            do {
                loading = true
                try await wallet.restoreWithMnemonic(mnemonic:mnemonic)
                success = true
                loading = false
            } catch {
                displayAlert(alert: AlertDetail(title: "Error", description: "There was an error when attempting to restore. Detail: \(String(describing: error))"))
                loading = false
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
