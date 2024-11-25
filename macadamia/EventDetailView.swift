import SwiftUI
import CashuSwift

struct EventDetailView: View {
    let event: Event

    var body: some View {
        switch event.kind {
            
        case .pendingMint:
            if let quote = event.bolt11MintQuote {
                MintView(quote: quote, pendingMintEvent: event)
            } else {
                Text("No quote set.")
            }
            
        case .mint:
            List {
                HStack {
                    Text("Minted at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                HStack {
                    Text("Amount: ")
                    Spacer()
                    Text(String(event.amount ?? 0))
                }
                HStack {
                    Text("Unit: ")
                    Spacer()
                    Text(event.unit.rawValue)
                }
                if let text = event.bolt11MintQuote?.request {
                    TokenText(text: text)
                        .frame(idealHeight: 70)
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = text
                            }) {
                                Text("Copy")
                                Spacer()
                                Image(systemName: "clipboard")
                            }
                        }
                }
            }
            
        case .send:
            SendEventView(event: event)
            
        case .receive:
            List {
                HStack {
                    Text("Received at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                HStack {
                    Text("Amount: ")
                    Spacer()
                    Text(String(event.amount ?? 0))
                }
                HStack {
                    Text("Unit: ")
                    Spacer()
                    Text(event.unit.rawValue)
                }
                if let tokenInfo = event.tokens?.first {
                    TokenText(text: tokenInfo.token)
                        .frame(idealHeight: 70)
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = tokenInfo.token
                            }) {
                                Text("Copy")
                                Spacer()
                                Image(systemName: "clipboard")
                            }
                        }
                }
            }
            
        case .pendingMelt:
            MeltView(quote: event.bolt11MeltQuote, pendingMeltEvent: event)
            
        case .melt:
            List {
                HStack {
                    Text("Melted at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                HStack {
                    Text("Amount: ")
                    Spacer()
                    Text(String(event.amount ?? 0))
                }
                HStack {
                    Text("Unit: ")
                    Spacer()
                    Text(event.unit.rawValue)
                }
                if let text = event.bolt11MeltQuote?.paymentPreimage {
                    TokenText(text: text)
                        .frame(idealHeight: 70)
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = text
                            }) {
                                Text("Copy")
                                Spacer()
                                Image(systemName: "clipboard")
                            }
                        }
                }
            }
            
        case .restore:
            List {
                HStack {
                    Text("Restored at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                Text(event.longDescription ?? "No description.")
            }
            
        case .drain:
            List {
                HStack {
                    Text("Created at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                if let tokens = event.tokens, !tokens.isEmpty {
                    ForEach(tokens, id: \.self) { tokenInfo in
                        Section {
                            TokenText(text: tokenInfo.token)
                                .frame(idealHeight: 70)
                                .contextMenu {
                                    Button(action: {
                                        UIPasteboard.general.string = tokenInfo.token
                                    }) {
                                        Text("Copy")
                                        Spacer()
                                        Image(systemName: "clipboard")
                                    }
                                }
                            Text(tokenInfo.mint)
                        }
                    }
                }
            }
        }
    }
}

struct SendEventView: View {
    var event: Event
    
    @State private var tokenState: TokenState = .unknown
    
    enum TokenState {
        case unknown
        case spent
        case pending
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Created at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                if let memo = event.memo {
                    Text("Memo: \(memo)")
                }
                if let proofs = event.proofs {
                        switch tokenState {
                        case .unknown:
                            Button {
                                checkTokenState(with: proofs)
                            } label: {
                                HStack {
                                    Text("Check token state?")
                                    Spacer()
                                    Image(systemName: "arrow.counterclockwise")
                                }
                            }
                        case .spent:
                            HStack {
                                Text("Token was redeemed.")
                                Spacer()
                                Image(systemName: "checkmark.circle")
                            }
                        case .pending:
                            HStack {
                                Text("Token is pending.")
                                Spacer()
                                Image(systemName: "hourglass")
                            }
                        }
                    }
            }
            
            if let tokenInfo = event.tokens?.first /*, tokenState != .spent */ {
                TokenShareView(tokenString: tokenInfo.token)
            }
        }
    }
    
    private func checkTokenState(with proofs:[Proof]) {
        guard let firstMint = proofs.first?.mint, proofs.allSatisfy({ $0.mint == firstMint }) else {
            logger.error("function to check proofs can not handle proofs from different mints!")
            return
        }
        
        Task {
            let result = try await CashuSwift.check(proofs, mint: firstMint)
            await MainActor.run {
                withAnimation {
                    if result.allSatisfy({ $0 == CashuSwift.Proof.ProofState.unspent }) {
                        tokenState = .pending
                    } else {
                        tokenState = .spent
                    }
                }
            }
        }
    }
}
