
import SwiftUI
import NostrSDK
import Combine
import OSLog

struct NostrInboxView: View {
    @ObservedObject var vm = ContentViewModel()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if vm.userProfile != nil {
                        HStack {
                            
                            if let url = vm.userProfile!.pictureURL {
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
                            if vm.userProfile!.name != nil {
                                Text(vm.userProfile!.name!)
                                    .lineLimit(1)
                            } else {
                                Text(vm.userProfile!.npub.prefix(14))
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        SecureField("enter NSEC", text: $vm.providedKey)
                            .onSubmit {
                                vm.saveProfileKey()
                            }
                    }
                } header: {
                    Text("My nostr profile")
                } footer: {
                    Text("Your nostr secret key is being encrypted when stored on device.")
                }
                if !vm.contacts.isEmpty {
                    Section {
                        ForEach(vm.contacts, id: \.pubkey) { profile in
                            NavigationLink(destination: NostrProfileMessageView(vm: NostrProfileMessageViewModel(profile: profile))) {
                                HStack {
                                    if let url = profile.pictureURL {
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
                                    if profile.name != nil {
                                        Text(profile.name!)
                                            .lineLimit(1)
                                    } else {
                                        Text(profile.npub.prefix(14))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .badge(profile.tokenMessages?.count ?? 0)
                        }
                    } header: {
                        Text("Contacts")
                    } footer: {
                        Text("Tap an account to send or receive eCash.")
                    }
                }
                if !vm.randos.isEmpty {
                    Section {
                        ForEach(vm.randos, id: \.pubkey) { profile in
                            NavigationLink(destination: NostrProfileMessageView(vm: NostrProfileMessageViewModel(profile: profile))) {
                                HStack {
                                    if let url = profile.pictureURL {
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
                                    if profile.name != nil {
                                        Text(profile.name!)
                                            .lineLimit(1)
                                    } else {
                                        Text(profile.npub.prefix(14))
                                            .lineLimit(1)
                                    }
                                }
                                .badge(profile.tokenMessages?.count ?? 0)
                            }
                        }
                    } header: {
                        Text("Contacts")
                    } footer: {
                        Text("Tap an account to send or receive eCash.")
                    }
                }
                if vm.userProfile != nil {
                    Section {
                        Button(role: .destructive) {
                            vm.reset()
                        } label: {
                            Text("Reset Data")
                        }
                    } footer: {
                        Text("Removes the key from disk.")
                    }
                }
            }
            .id(vm.listRedraw)
            .refreshable {
                vm.loadFollowListWithInfo()
            }
            .navigationTitle("Nostr Contacts")
            .onAppear {
                vm.connectToRelay()
                vm.listRedraw += 1
            }
            .alertView(isPresented: $vm.showAlert, currentAlert: vm.currentAlert)
        }
    }
}

#Preview {
    NostrInboxView()
}

@MainActor
class ContentViewModel: ObservableObject {
    
    @Published var nostrService:NostrService
    @Published var providedKey:String = ""
    @Published var userProfile:Profile?
    @Published var contacts = [Profile]()
    @Published var randos = [Profile]()
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    var messages = [Message]()
    
    //needed to make updates to profile info reflected in UI
    @Published var listRedraw = 0
    
    var wallet = Wallet.shared
    
    init() {
        
        nostrService = NostrService.shared
        userProfile = nostrService.userProfile
    }
    
    func connectToRelay() {
        nostrService.connectAll()
    }
    
    func saveProfileKey() {
        // check key validity
        do {
            try nostrService.setPrivateKey(privateKey: providedKey)
        } catch {
            displayAlert(alert: AlertDetail(title: "Error",
                                           description: "The key you provided could not be saved. Please make sure it is valid."))
            self.providedKey = ""
            return
        }
        
        // init userprofile
        userProfile = nostrService.userProfile
        
        //load userprofile info (with follow list)
        loadFollowListWithInfo()
    }
    
    func reset() {
        displayAlert(alert: AlertDetail(title: "Are you sure?", 
                                        description: "Do you really want to remove your nostr key?",
                                        primaryButtonText: "Cancel",
                                        affirmText: "Yes",
                                        onAffirm: {
            self.contacts = []
            self.randos = []
            self.userProfile = nil
            self.nostrService.dataManager.resetAll()
        }))
    }
    
    func loadFollowListWithInfo() {
        
        Task {
            do {
                contacts = try await nostrService.fetchContactList()
                messages = try await nostrService.checkInbox()
                var allTokenMessages = messages.filter({ $0.decryptedContent.contains("cashuA") })
                randos = allTokenMessages.uniqueSenders().filter { !contacts.contains($0)}
                try await nostrService.loadInfo(for: contacts + randos, of: userProfile)
                                
                // truncate messeges to token
                for message in allTokenMessages {
                    guard let token = findSubstring(in: message.decryptedContent, withPrefix: "cashuA") else {
                        continue
                    }
                    message.decryptedContent = token
                }

                // check against history & mint
                let knownTokens = Set(wallet.database.transactions.compactMap({$0.token}))
                allTokenMessages.removeAll { message in
                    return knownTokens.contains(message.decryptedContent)
                }
                
                var offsets = IndexSet()
                for index in 0..<allTokenMessages.count {
                    let spendable:Bool
                    do {
                        spendable = try await wallet.checkTokenStatePending(token:allTokenMessages[index].decryptedContent)
                    } catch {
                        spendable = false
                    }
                    if !spendable { offsets.insert(index) }
                }
                
                allTokenMessages.remove(atOffsets: offsets)
                
                for p in contacts + randos {
                    p.tokenMessages = allTokenMessages.filter({ $0.senderPubkey == p.pubkey }).map({ $0.decryptedContent })
                }
                
                contacts.sort { (lhs, rhs) -> Bool in
                    switch (lhs.name, rhs.name) {
                    case let (lhsName?, rhsName?):
                        if lhsName == rhsName {
                            return lhs.npub < rhs.npub
                        }
                        return lhsName < rhsName
                    case (nil, _):
                        return false
                    case (_, nil):
                        return true
                    }
                }
                
                allTokenMessages.forEach( { print($0.decryptedContent) } )
                
                listRedraw += 1
            } catch {
                displayAlert(alert: AlertDetail(title: "Refresh failed",
                                                description: String(describing: error)))
            }
        }
    }
    
    func findSubstring(in text: String, withPrefix prefix: String) -> String? {
        let pattern = "\(prefix)\\S*"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        let matches = regex?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        if let matchRange = matches?.first?.range {
            return String(text[Range(matchRange, in: text)!])
        }
        
        return nil
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
