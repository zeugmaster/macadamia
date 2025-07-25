import SwiftUI
import SwiftData
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
            }
            
        case .pendingReceive:
            RedeemLaterView(event: event)
        case .pendingMelt:
            MeltView(pendingMeltEvent: event)
            
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
    
    var token: CashuSwift.Token? {
                
        if let proofs = event.proofs,
           !proofs.isEmpty,
           let mints = event.mints,
           mints.count == 1 {
            
            return CashuSwift.Token(proofs: [mints.first!.url.absoluteString: proofs],
                                    unit: Unit.sat.rawValue,
                                    memo: event.memo)
        }
        return nil
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Created at: ")
                    Spacer()
                    Text(event.date.formatted())
                }
                if let mint = event.mints?.first {
                    HStack {
                        Text("Mint: ")
                        Spacer()
                        Text(mint.displayName)
                    }
                }
                if let memo = event.memo, !memo.isEmpty {
                    HStack {
                        Text("Memo: ")
                        Spacer()
                        Text(memo)
                    }
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
            
            if let token {
                TokenShareView(token: token)
            }
        }
        .onAppear {
            print(String(describing: token))
        }
    }
    
    private func checkTokenState(with proofs:[Proof]) {
        guard let firstMint = proofs.first?.mint,
              proofs.allSatisfy({ $0.mint == firstMint }) else {
            logger.error("function to check proofs can not handle proofs from different mints!")
            return
        }
        
        Task {
            let result = try await CashuSwift.check(proofs.sendable(), mint: CashuSwift.Mint(firstMint))
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
