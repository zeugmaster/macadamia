//
//  MintManagerView.swift
//  macadamia
//
//  Created by zeugmaster on 01.01.24.
//

import SwiftUI

struct MintManagerView: View {
    @ObservedObject var vm:MintManagerViewModel
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    List(vm.mintList, id: \.url) { mintInfo in
                        NavigationLink(destination: MintDetailView(mintInfo: mintInfo)) {
                            MintInfoRowView(mintInfo: mintInfo)
                        }
                    }
                }
                Section {
                    TextField("Add new Mint URL...", text: $vm.newMintURLString)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Enter a URL to add a new mint to the wallet, hit Return to save.")
                }
            }
            .navigationTitle("Mints")
            .alertView(isPresented: $vm.showAlert, currentAlert: vm.currentAlert)
        }
    }
}

struct MintInfoRowView: View {
    @State var mintInfo:MintInfo
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44
    
    var body: some View {
        HStack {
            ZStack {
                Group {
                    Color.gray.opacity(0.3)
                    if let imageURL = mintInfo.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            case .failure(_):
                                Image(systemName: "photo")
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "building.columns")
                            .foregroundColor(.white)
                    }
                }
                .frame(width: iconSize, height: iconSize) // Use a relative size or GeometryReader for more flexibility
                .clipShape(Circle())
//                Circle()
//                    .fill(.green)
//                    .frame(width: 12, height: 12)
//                    .offset(x: 15, y: -15)
            }
            VStack(alignment:.leading) {
                Text(mintInfo.name)
                    .bold()
                    .dynamicTypeSize(.xLarge)
                Text("420 sats | 21.69 USD")
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(.small)
            }
        }
    }
}

@MainActor
class MintManagerViewModel: ObservableObject {
    @Published var mintList:[MintInfo]
    @Published var error:Error?
    @Published var newMintURLString = ""
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
//    var wallet = Wallet.shared
        
    init(mintList:[MintInfo]) {
        self.mintList = mintList
    }
    
    func addMintWithUrlString() {
        
        // TODO: CHECK HTTP(S) PREFIX AND APPEND IF NECESSARY
//        guard let url = URL(string: newMintURLString),
//            newMintURLString.contains("https://") else {
//            newMintURLString = ""
//            displayAlert(alert: AlertDetail(title: "Invalid URL", 
//                                            description: "The URL you entered was not valid. Make sure it uses correct formatting as well as the right prefix."))
//            return
//        }
//        
//        guard !mintList.contains(where: { $0.url.absoluteString == newMintURLString }) else {
//            displayAlert(alert: AlertDetail(title: "Already added.",
//                                           description: "This URL is already in the list of knowm mints, please choose another one."))
//            newMintURLString = ""
//            return
//        }
//        
//        Task {
//            do {
//                try await wallet.addMint(with:url)
//                mintList = wallet.database.mints
//                newMintURLString = ""
//            } catch {
//                displayAlert(alert: AlertDetail(title: "Could not be added",
//                                                description: "The mint with this URL could not be added. \(error)"))
//                newMintURLString = ""
//            }
//        }
    }
    
    func removeMint(at offsets: IndexSet) {
        //TODO: CHECK FOR BALANCE
//        if true {
//            displayAlert(alert: AlertDetail(title: "Are you sure?",
//                                           description: "Are you sure you want to delete it?",
//                                            primaryButtonText: "Cancel",
//                                           affirmText: "Yes",
//                                            onAffirm: {
//                // should actually never be more than one index at a time
//                offsets.forEach { index in
//                    let url = self.mintList[index].url
//                    self.mintList.remove(at: index)
//                    self.wallet.removeMint(with: url)
//                }
//            }))
//        } else {
//            offsets.forEach { index in
//                let url = self.mintList[index].url
//                self.mintList.remove(at: index)
//                self.wallet.removeMint(with: url)
//            }
//        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

//#Preview {
//    MintManagerView(vm: MintManagerViewModel(mintList: [mint1, mint2, mint3]))
//}
