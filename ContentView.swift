
import SwiftUI
import NostrSDK
import Combine
import OSLog

struct ContentView: View {
    @ObservedObject var viewmodel = ContentViewModel()
    var body: some View {
        VStack {
            HStack {
                SecureField("enter NSEC or hex private key", text: $viewmodel.providedPubkey)
                    .padding()
                    .textFieldStyle(.roundedBorder)
                Button("Load") {
                    viewmodel.loadSubscriptions()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            VStack {
                List {
                    Section {
                        ForEach(viewmodel.contacts, id: \.pubkey) { profile in
                            TableRowView(profile: profile) {
                                viewmodel.initiateSend(to: profile)
                            } redeemButtonAction: {
                                viewmodel.redeemAllFromProfile(profile: profile)
                            }
                        }
                        .id(viewmodel.didLoadAdditionalProfileInfo)
                    } header: {
                        Text("Contacts")
                    }
                    Section {
                        ForEach(viewmodel.randos, id: \.pubkey) { profile in
                            TableRowView(profile: profile) {
                                
                            } redeemButtonAction: {
                                
                            }
                        }
                    } header: {
                        Text("Randos")
                    }
                }
            }
        }
        .onAppear {
            viewmodel.connectToRelay()
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
            Button(action: {
                sendButtonAction()
            }, label: {
                Image(systemName: "paperplane")
            })
            Spacer().frame(width: 20)
            Button(action: {
                redeemButtonAction()
            }, label: {
                Image(systemName: "square.and.arrow.down")
            })
        }
        .buttonStyle(.bordered)
    }
}


//#Preview {
//    ContentView()
//}

@MainActor
class ContentViewModel: ObservableObject {
    
    @Published var contactService:ContactService?
    @Published var providedPubkey:String = ""
    @Published var contacts = [Profile]()
    @Published var randos = [Profile]()
    
    var messages = [Message]()
    
    @Published var didLoadAdditionalProfileInfo = false
    
    init() {
        do {
            contactService = try ContactService()
        } catch {
            print("unable to initialize ContactService")
        }
    }
    
    func connectToRelay() {
        contactService?.connectAll()
    }
    
    func loadSubscriptions() {
        guard contactService != nil else {
            print("could not load subscriptions because contactService was not initialized yet")
            return
        }
        Task {
            do {
                if !providedPubkey.isEmpty {
                    try contactService?.setPrivateKey(privateKey: providedPubkey)
                }
                contacts = try await contactService!.fetchContactList()
                try await contactService!.loadInfo(for: contacts)
                didLoadAdditionalProfileInfo = true
                
                messages = try await contactService!.checkInbox()
                randos = messages.uniqueSenders().filter { !contacts.contains($0)}
            } catch {
                print("error when loading subscription: \(error)")
            }
        }
    }
    
    func initiateSend(to profile:Profile) {
        // bring up view to send tokens to profile
        print("initiate send")
        do {
//            try contactService?.sendMessage(to: profile)
        } catch {
            print(error)
        }
    }
    
    func redeemAllFromProfile(profile:Profile) {
        //check messages and redeem
        print("redeeeeem")
    }
}
