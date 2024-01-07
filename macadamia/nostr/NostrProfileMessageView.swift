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
                    HStack {
                        if let url = vm.profile.pictureURL {
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill") // Fallback system image
                                .frame(width: 40, height: 40)
                        }
                        if vm.profile.name != nil {
                            Text(vm.profile.name!)
                                .lineLimit(1)
                        } else {
                            Text(vm.profile.npub.prefix(14))
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Your nostr contact")
                }
                if !vm.tokens.isEmpty {
                    Section {
                        ForEach(vm.tokens, id: \.self) { token in
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
                    .animation(.default, value: vm.tokens)
                    .id(vm.profile.tokenMessages)
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
            .onAppear(perform: {
                vm.updateTokens()
            })
        }
    }
}

//#Preview {
//    NostrProfileMessageView(vm: NostrProfileMessageViewModel(profile: Demo.user, tokenMessages:["cashuAaosdfhpwiuohafjsöfoivüoiüoierfüoiasügoiqhjüweroighjüowif"]))
//}

@MainActor
class NostrProfileMessageViewModel: ObservableObject {
    @Published var profile:Profile
    @Published var tokens = [String]()
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    var wallet = Wallet.shared
    
    init(profile: Profile, tokenMessages: [String]? = nil) {
        self.profile = profile
    }
    
    // "janky" would be a gross understatement
    func redeem(token:String) {
        Task {
            do {
                try await wallet.receiveToken(tokenString: token)
                for idx in 0..<tokens.count {
                    if tokens[idx] == token {
                        tokens[idx] = "Success!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.tokens.remove(at: idx)
                        }
                    }
                }
                profile.tokenMessages?.removeAll(where: {$0 == token})
            } catch let error as WalletError {
                switch error {
                case .unknownMintError:
                    guard let mintURL = try? wallet.deserializeToken(token: token).token.first?.mint else {
                        return
                    }
                    displayAlert(alert: AlertDetail(title: "Add unknown mint?",
                                                    description: "This token is from a mint you don't have in your list yet. Would you like to add \(mintURL) and then try again to redeem?",
                                                    primaryButtonText: "No",
                                                    affirmText: "Yes",
                                                    onAffirm: {
                        Task {
                            do {
                                try await self.wallet.addMint(with: URL(string: mintURL)!)
                            } catch {
                                self.displayAlert(alert: AlertDetail(title: "Failed"))
                            }
                        }
                    }))
                default:
                    displayAlert(alert: AlertDetail(title: "Could not redeem",
                                                   description: String(describing: error)))
                }
            } catch {
                displayAlert(alert: AlertDetail(title: "Could not redeem",
                                               description: String(describing: error)))
            }
        }
    }
    
    
    func updateTokens() {
        tokens = profile.tokenMessages ?? []
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
