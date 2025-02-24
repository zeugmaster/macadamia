import SwiftUI
import SwiftData

struct MintPicker: View {
    @Query(sort: [SortDescriptor(\Mint.userIndex, order: .forward)]) private var mints: [Mint]
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Binding private var selectedMint: Mint?
    @Binding private var hide: Mint?
    private var allowsNoneState: Bool = false
    private var label: String
    
    @State private var mintNamesAndIDs = [(name: String, id: UUID)]()
    @State private var selectedID: UUID? = nil
    
    var activeWallet: Wallet? {
        wallets.first
    }
    
    var sortedMintsOfActiveWallet: [Mint] {
        mints.filter { $0.wallet == activeWallet && !$0.hidden }
             .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
    }
    
    init(label: String, selectedMint: Binding<Mint?>, allowsNoneState: Bool = false, hide: Binding<Mint?>? = nil) {
        self.label = label
        self._selectedMint = selectedMint
        self.allowsNoneState = allowsNoneState
        self._hide = hide ?? .constant(nil)
    }
    
    var body: some View {
        Group {
            if mintNamesAndIDs.isEmpty {
                Text("No mints yet.")
            } else {
                Picker(label, selection: $selectedID) {
                    if allowsNoneState {
                        Text("Select...")
                            .tag(UUID?.none)
                    }
                    ForEach(mintNamesAndIDs, id: \.id) { entry in
                        Text(entry.name).tag(Optional(entry.id))
                    }
                }
            }
        }
        .onAppear {
            populate()
            if let selectedMint = selectedMint {
                selectedID = selectedMint.mintID
            }
        }
        .onChange(of: selectedID) { _, newValue in
            if let id = newValue {
                selectedMint = sortedMintsOfActiveWallet.first { $0.mintID == id }
            } else {
                selectedMint = nil
            }
        }
        .onChange(of: selectedMint) { _, newValue in
            if let mint = newValue {
                selectedID = mint.mintID
            } else {
                selectedID = nil
            }
        }
        .onChange(of: hide) { oldValue, newValue in
            populate()
        }
    }
    
    func populate() {
        mintNamesAndIDs = sortedMintsOfActiveWallet.map { mint in
            (mint.displayName, mint.mintID)
        }
        if let hide {
            mintNamesAndIDs = mintNamesAndIDs.filter { (name: String, id: UUID) in
                id != hide.mintID
            }
        }
        if let first = mintNamesAndIDs.first, !allowsNoneState {
            selectedID = first.id
        }
    }
}
