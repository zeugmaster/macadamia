
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
                        UserProfileView(profile: vm.userProfile!)
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
                            TableRowView(profile: profile) {
                                
                            } redeemButtonAction: {
                                vm.redeemAllFromProfile(profile: profile)
                            }
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
                            TableRowView(profile: profile) {
                                
                            } redeemButtonAction: {
                                
                            }
                        }
                    } header: {
                        if !vm.randos.isEmpty {
                            Text("Not in your contacts")
                        }
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
            .id(vm.didLoadAdditionalProfileInfo)
            .refreshable {
                vm.loadFollowListWithInfo()
            }
            .navigationTitle("Nostr Contacts")
            .onAppear {
                vm.connectToRelay()
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

struct TableRowView: View {
    
    var profile:Profile
    
    var sendButtonAction:() -> ()
    var redeemButtonAction:() -> ()
    
    var body: some View {
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
            Spacer()
            
            NavigationLink("", destination: NostrProfileMessageView(vm: NostrProfileMessageViewModel(profile: profile)))
        }
        .buttonStyle(.bordered)
    }
}

struct UserProfileView: View {
    var profile:Profile
    
    var body: some View {
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
            Spacer()
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
    @Published var didLoadAdditionalProfileInfo = false
    @Published var textfieldOpacity = 0.0
    
    init() {
        
        nostrService = NostrService.shared
        userProfile = nostrService.userProfile
        
//        userProfile = Demo.user
//        contacts = Demo.contacts
        
        if userProfile != nil {
            textfieldOpacity = 0.01
        } else {
            textfieldOpacity = 1
        }
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
                try await nostrService.loadInfo(for: contacts, of: userProfile)
                didLoadAdditionalProfileInfo = true
                messages = try await nostrService.checkInbox()
                randos = messages.uniqueSenders().filter { !contacts.contains($0)}
            } catch {
                displayAlert(alert: AlertDetail(title: "Refresh failed",
                                                description: String(describing: error)))
            }
        }
    }
    
    func redeemAllFromProfile(profile:Profile) {
        //check messages and redeem
        print("redeeeeem")
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct Demo {
    static let contacts = [Profile(pubkey: "0",
                                npub: "npub1testtesttest0",
                                name: "jack",
                                pictureURL: URL(string: "https://imgproxy.snort.social/0tj5ONtCNGXTrkDxctGz0MsoEqd2ASXBiH7mqtgXRl0//aHR0cHM6Ly9ub3N0ci5idWlsZC9pL3Avbm9zdHIuYnVpbGRfNmI5OTA5YmNjZjBmNGZkYWY3YWFjZDliYzAxZTRjZTcwZGFiODZmN2Q5MDM5NWYyY2U5MjVlNmVhMDZlZDdjZC5qcGVn")),
                        Profile(pubkey: "1",
                                npub: "npub1testtesttest1",
                                name: "Bob"),
                        Profile(pubkey: "2",
                                npub: "npub1testtesttest2",
                                pictureURL: URL(string: "https://upload.wikimedia.org/wikipedia/en/5/52/Hal_Finney_%28computer_scientist%29.jpg"))]


    static let user = Profile(pubkey: "hex92184751239874",
                           npub: "npub1demousertesttesttest",
                           name: "zeugmaster",
                           pictureURL: URL(string: "https://imgproxy.snort.social/rRYAKvx4eBl_dyo2yXkM4mbfGmSLSiLgzUMat0JMEC4//aHR0cHM6Ly9wYnMudHdpbWcuY29tL3Byb2ZpbGVfaW1hZ2VzLzEyODMxMTE3NzU3NjQ5OTIwMDEva3Y5dkMwMlVfNDAweDQwMC5qcGc"))
}
