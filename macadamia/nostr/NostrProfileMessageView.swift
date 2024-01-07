//
//  NostrRede.swift
//  macadamia
//
//  Created by Dario Lass on 06.01.24.
//

import SwiftUI


struct NostrProfileMessageView: View {
    
    @ObservedObject var vm:NostrProfileMessageViewModel
    
    init(vm: NostrProfileMessageViewModel) {
        self.vm = vm
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    UserProfileView(profile: vm.profile)
                } header: {
                    Text("Your nostr contact")
                }
                if vm.tokenMessages != nil {
                    if !vm.tokenMessages!.isEmpty {
                        Section {
                            ForEach(vm.tokenMessages!, id: \.self) { token in
                                Button {
                                    vm.redeem(token: token)
                                } label: {
                                    Text(token)
                                        .monospaced()
                                        .lineLimit(1)
                                }
                            }
                        } header: {
                            Text("Pending token messages")
                        } footer: {
                            Text("Tap to redeem.")
                        }
                    }
                }
                Section {
                    NavigationLink("Send eCash",
                                   destination: NostrSendView(nsvm: NostrSendViewModel(recipientProfile: vm.profile)))
                }
            }
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
    NostrProfileMessageView(vm: NostrProfileMessageViewModel(profile: Demo.user, tokenMessages:["cashuAaosdfhpwiuohafjsöfoivüoiüoierfüoiasügoiqhjüweroighjüowif"]))
}

@MainActor
class NostrProfileMessageViewModel: ObservableObject {
    var profile:Profile
    @Published var tokenMessages:[String]?
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    var wallet = Wallet.shared
    
    init(profile: Profile, tokenMessages: [String]? = nil) {
        self.profile = profile
        self.tokenMessages = tokenMessages
    }
    
    func redeem(token:String) {
        Task {
            do {
                try await wallet.receiveToken(tokenString: token)
                tokenMessages?.removeAll(where: {$0 == token})
            } catch {
                displayAlert(alert: AlertDetail(title: "Could not redeem",
                                               description: String(describing: error)))
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
