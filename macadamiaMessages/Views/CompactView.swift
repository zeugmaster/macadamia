import SwiftUI
import SwiftData
import Messages

struct CompactView: View {
    weak var delegate: MessagesViewController?
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var totalBalance: Int {
        activeWallet?.totalBalance() ?? 0
    }
    
    private var hasAvailableMints: Bool {
        !(activeWallet?.availableMints.isEmpty ?? true)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Main send button
            Button(action: {
                delegate?.requestPresentationStyle(.expanded)
            }) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.title2)
                        .foregroundColor(.macadamiaOrange)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send Ecash")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.macadamiaPrimary)
                        
                        Text("Wallets: \(wallets.count) | Mints: \(activeWallet?.mints.count ?? 0)")
                            .font(.caption)
                            .foregroundColor(.macadamiaSecondary)
                        
                        if !hasAvailableMints {
                            Text("No mints available")
                                .font(.caption)
                                .foregroundColor(.macadamiaRed)
                        } else {
                            Text("\(totalBalance) sats available")
                                .font(.caption)
                                .foregroundColor(.macadamiaSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Arrow indicator
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.macadamiaSecondary)
                }
                .padding(ExtensionTheme.padding)
                .background(
                    RoundedRectangle(cornerRadius: ExtensionTheme.cornerRadius)
                        .fill(Color.macadamiaSecondaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: ExtensionTheme.cornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black
        CompactView(delegate: nil)
            .padding()
    }
    .modelContainer(DatabaseManager.shared.container)
    .preferredColorScheme(.dark)
}
#endif
