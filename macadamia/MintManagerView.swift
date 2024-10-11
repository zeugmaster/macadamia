//
//  MintManagerView.swift
//  macadamia
//
//  Created by zeugmaster on 01.01.24.
//

import CashuSwift
import SwiftData
import SwiftUI

struct MintManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]

    @State var newMintURLString = ""
    @State var showAlert: Bool = false

    @State var currentAlert: AlertDetail?

    var activeWallet: Wallet? {
        wallets.first
    }

    var body: some View {
        NavigationView {
            if let activeWallet {
                Form {
                    Section {
                        List(activeWallet.mints, id: \.url) { mint in
                            NavigationLink(destination: MintDetailView(mint: mint)) {
                                MintInfoRowView(mint: mint)
                            }
                        }
                    }
                    Section {
                        TextField("Add new Mint URL...", text: $newMintURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onSubmit {
                                addMint()
                            }
                    } footer: {
                        Text("Enter a URL to add a new mint to the wallet, hit Return to save.")
                    }
                }
                .navigationTitle("Mints")
                .alertView(isPresented: $showAlert, currentAlert: currentAlert)
            } else {
                Text("No wallet initialized yet.")
            }
        }
    }

    func addMint() {
        // First, trim any whitespace and newlines
        let trimmedURLString = newMintURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the string starts with a valid scheme
        guard trimmedURLString.starts(with: "http://") || trimmedURLString.starts(with: "https://") else {
            displayAlert(alert: AlertDetail(title: "Invalid URL", description: "URL must start with http:// or https://"))
            return
        }

        // Now try to create the URL
        guard let url = URL(string: trimmedURLString) else {
            displayAlert(alert: AlertDetail(title: "Not a valid URL."))
            return
        }

        // Additional check: ensure the URL has a host
        guard url.host != nil else {
            displayAlert(alert: AlertDetail(title: "Invalid URL", description: "URL must include a valid host"))
            return
        }

        Task {
            do {
                let mint = try await CashuSwift.loadMint(url: url, type: Mint.self)
                mint.wallet = activeWallet
                modelContext.insert(mint)
                try modelContext.save()
                DispatchQueue.main.async {
                    newMintURLString = ""
                }
            } catch {
                DispatchQueue.main.async {
                    displayAlert(alert: AlertDetail(title: "Could not add mint.",
                                                    description: String(describing: error)))
                }
            }
        }
    }

    func removeMint(at _: IndexSet) {
        // TODO: CHECK FOR BALANCE
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

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct MintInfoRowView: View {
    var mint: Mint
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    var body: some View {
        HStack {
            ZStack {
                Group {
                    Color.gray.opacity(0.3)
//                    if let imageURL = mint.info?.imageURL {
//                        AsyncImage(url: imageURL) { phase in
//                            switch phase {
//                            case .success(let image):
//                                image
//                                    .resizable()
//                                    .aspectRatio(contentMode: .fit)
//                            case .failure(_):
//                                Image(systemName: "photo")
//                            case .empty:
//                                ProgressView()
//                            @unknown default:
//                                EmptyView()
//                            }
//                        }
//                    } else {
                    Image(systemName: "building.columns")
                        .foregroundColor(.white)
//                    }
                }
                .frame(width: iconSize, height: iconSize) // Use a relative size or GeometryReader for more flexibility
                .clipShape(Circle())
//                Circle()
//                    .fill(.green)
//                    .frame(width: 12, height: 12)
//                    .offset(x: 15, y: -15)
            }
            VStack(alignment: .leading) {
                Text(mint.url.absoluteString)
                    .bold()
                    .dynamicTypeSize(.xLarge)
                Text("420 sats | 21.69 USD")
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(.small)
            }
        }
    }
}

// #Preview {
//    MintManagerView(vm: MintManagerViewModel(mintList: [mint1, mint2, mint3]))
// }
