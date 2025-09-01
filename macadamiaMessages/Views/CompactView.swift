import SwiftUI
import SwiftData
import Messages

struct CompactView: View {
    weak var delegate: MessagesViewController?
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    var body: some View {
        if let mints = wallets.first?.mints {
            List {
                Section {
                    ForEach(mints) { mint in
                        Text(mint.displayName)
                    }
                } header: {
                    Text("Send from")
                }
            }
        } else {
            Text("no mints or missing wallet.")
        }
    }
}

#if DEBUG
#Preview {
    CompactView(delegate: nil)
        .modelContainer(DatabaseManager.shared.container)
}
#endif
