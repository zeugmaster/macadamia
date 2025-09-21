//
//  MessageMintList.swift
//  macadamiaMessages
//
//  Created by zm on 01.09.25.
//

import SwiftUI
import SwiftData
import CashuSwift
import UIKit
import Messages

extension Notification.Name {
    static let messageSelected = Notification.Name("messageSelected")
}

struct MessageMintList: View {
    weak var vc: MessagesViewController?
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<AppSchemaV1.Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [AppSchemaV1.Wallet]
    
    @State private var selectedToken: String?
    
    private var activeWallet: AppSchemaV1.Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    var body: some View {
        Group {
            if let token = selectedToken {
                TokenDisplayView(tokenString: token) {
                    selectedToken = nil
                }
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Send from")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            if mints.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "building.columns")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    
                                    Text("No Mints Available")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Add a mint in the main wallet app to start sending ecash tokens.")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                                .padding(.top, 60)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 20) {
                                    ForEach(mints) { mint in
                                        NavigationLink {
                                            MessageSendView(mint: mint, vc: vc)
                                        } label: {
                                            MintGridItem(mint: mint)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messageSelected)) { notification in
            if let tokenString = notification.object as? String {
                selectedToken = tokenString
            }
        }
    }
    
    func showToken(_ tokenString: String) {
        selectedToken = tokenString
    }
}

struct MintGridItem: View {
    let mint: Mint
    
    @State private var mintIcon: UIImage?
    @State private var isLoadingIcon = false
    
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 8) {
            // Mint icon
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: iconSize, height: iconSize)
                
                if let icon = mintIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                        .clipShape(Circle())
                } else if isLoadingIcon {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "building.columns")
                        .foregroundColor(.white)
                        .font(.title2)
                }
            }
            
            // Mint name
            Text(mint.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32) // Fixed height for alignment
            
            // Balance
            Text(amountDisplayString(mint.balance(for: .sat), unit: .sat))
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospaced()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .onAppear {
            loadMintIcon()
        }
    }
    
    private func loadMintIcon() {
        Task {
            await MainActor.run {
                isLoadingIcon = true
            }
            
            do {
                guard let info = try await mint.loadInfo(invalidateCache: false) else {
                    print("No mint info available")
                    await MainActor.run {
                        isLoadingIcon = false
                    }
                    return
                }
                
                if let iconURLString = info.iconUrl,
                   let iconURL = URL(string: iconURLString) {
                    
                    let (data, _) = try await URLSession.shared.data(from: iconURL)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            mintIcon = image
                            isLoadingIcon = false
                        }
                        return
                    }
                }
            } catch {
                print("Failed to load mint icon: \(error)")
            }
            
            await MainActor.run {
                isLoadingIcon = false
            }
        }
    }
}

struct MessageSendView: View {
    let mint: AppSchemaV1.Mint
    weak var vc: MessagesViewController?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var memo: String = ""
    @State private var amountString: String = ""
    @State private var buttonState = ActionButtonState.idle("...")
    @State private var mintIcon: UIImage?
    @State private var selectedBanner: String = ""
    
    @FocusState private var amountFieldInFocus
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 60
    
    private var buttonDisabled: Bool {
        amount <= 0 || amount > mint.balance(for: .sat)
    }
    
    private var amount: Int {
        Int(amountString) ?? 0
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: iconSize, height: iconSize)
                            
                            if let icon = mintIcon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "building.columns")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        Text(mint.displayName)
                            .font(.title3)
                            .lineLimit(1)
                    }
                }
                .task {
                    if let info = try? await mint.loadInfo(),
                       let urlString = info.iconUrl,
                       let url = URL(string: urlString) {
                        if let (data, _) = try? await URLSession.shared.data(from: url),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                withAnimation {
                                    self.mintIcon = image
                                }
                            }
                        }
                    }
                }
                
                Section {
                    HStack {
                        TextField("Enter amount...", text: $amountString)
                            .keyboardType(.numberPad)
                            .focused($amountFieldInFocus)
                        Spacer()
                        Text("sat")
                    }
                    .monospaced()
                    
                    HStack {
                        Text("Balance: ")
                        Spacer()
                        Text(String(mint.balance(for: .sat)))
                            .monospaced()
                        Text("sats")
                    }
                    .foregroundStyle(amount > mint.balance(for: .sat) ? .failureRed : .secondary)
                    .animation(.linear(duration: 0.2), value: amount > mint.balance(for: .sat))
                    
                    TextField("Optional memo...", text: $memo)
                }
                
                Section {
                    NavigationLink {
                        BannerSelectionView(selectedBanner: $selectedBanner)
                    } label: {
                        HStack {
                            Text("Message Banner")
                            Spacer()
                            if selectedBanner.isEmpty {
                                Text("Random")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(selectedBanner)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 24)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState, hideShadow: true)
                    .actionDisabled(buttonDisabled)
            }
        }
        .onAppear {
            buttonState = .idle("Send", action: createToken)
            amountFieldInFocus = true
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func createToken() {
        buttonState = .loading()
        
        guard let proofs = mint.select(amount: amount, unit: .sat) else {
            return
        }
        
        mint.send(proofs: proofs.selected,
                  targetAmount: amount,
                  memo: memo,
                  completion: { result in
            switch result {
            case .success(let success):
                buttonState = .success()
                onSuccess(token: success.token, event: success.event, swapped: success.swapped)
            case .failure(let error):
                buttonState = .fail()
                print("send failed due to error: \(error)")
            }
        })
    }
    
    private func onSuccess(token: CashuSwift.Token, event: Event, swapped: [AppSchemaV1.Proof]) {
        AppSchemaV1.insert(swapped + [event], into: modelContext)
        
        vc?.requestPresentationStyle(.compact)
        
        do {
            let message = try message(for: token)
            
            vc?.activeConversation?.insert(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            buttonState = .fail("Token Error")
            print("error when generating message: \(error)")
        }
    }
    
    private func message(for token: CashuSwift.Token) throws -> MSMessage {
        let tokenString = try token.serialize(to: .V4)
        
        guard let url = URL(string: "data:\(tokenString)") else {
            throw CashuError.unknownError("could not create URL from token")
        }
        
        let message = MSMessage()
        message.url = url
        
        let layout = MSMessageTemplateLayout()
        let bannerName = selectedBanner.isEmpty ? "banner-\(Int.random(in: 1...6))" : selectedBanner
        layout.image = UIImage(named: bannerName)
        layout.caption = amountDisplayString(token.sum(), unit: .sat)
        layout.subcaption = token.memo
        
        message.layout = layout
        return message
    }
}

struct TokenDisplayView: View {
    weak var vc: MessagesViewController?
    
    let tokenString: String
    let onDismiss: () -> Void
    
    @State private var copied = false
    
    private var amount: Int? {
        try? tokenString.deserializeToken().sum()
    }
    
    private var memo: String? {
        try? tokenString.deserializeToken().memo
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Back") {
                    onDismiss()
                }
                Spacer()
                Text("Ecash Token")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("    ") { }
                    .disabled(true)
                    .opacity(0)
            }
            .padding(.horizontal)
            
            RedeemView(tokenString: tokenString) {
                Button {
                    UIPasteboard.general.string = tokenString
                    withAnimation {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        withAnimation {
                            copied = false
                        }
                    }
                } label: {
                    HStack {
                        Text(copied ? "Copied!" : "Copy")
                        Spacer()
                        Image(systemName: "clipboard")
                    }
                }
                Button {
                    guard let url = URL(string: "cashu:\(tokenString)") else {
                        return
                    }
                    vc?.extensionContext?.open(url)
                } label: {
                    HStack {
                        Text("Open in Wallet")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            } onSuccess: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    onDismiss()
                    vc?.requestPresentationStyle(.compact)
                }
            }
        }
    }
}

struct BannerSelectionView: View {
    @Binding var selectedBanner: String
    @Environment(\.dismiss) private var dismiss
    
    private let banners = ["banner-1", "banner-2", "banner-3", "banner-4", "banner-5", "banner-6"]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    // Random option
                    Button {
                        selectedBanner = ""
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.2))
                                    .aspectRatio(16/9, contentMode: .fit)
                                
                                VStack {
                                    Image(systemName: "shuffle")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                    Text("Random")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedBanner.isEmpty ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Banner options
                    ForEach(banners, id: \.self) { banner in
                        Button {
                            selectedBanner = banner
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(banner)
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedBanner == banner ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("Select Banner")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
