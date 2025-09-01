import SwiftUI
import SwiftData
import Messages

struct ExpandedView: View {
    weak var delegate: MessagesViewController?
    var mint: Mint?
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    @Query private var allProofs: [Proof]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Send Ecash")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    delegate?.requestPresentationStyle(.compact)
                }
            }
            
            Text("Wallet has \(wallets.first?.totalBalance() ?? 0) sats")
                .foregroundColor(.secondary)
            
            Text("Available mints: \(wallets.first?.availableMints.count ?? 0)")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("You can build your interface here")
                .foregroundColor(.secondary)
                .italic()
            
            Spacer()
        }
    }
}

