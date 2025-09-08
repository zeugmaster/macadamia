import SwiftUI
import SwiftData

struct MintPicker: View {
    @Query(sort: [SortDescriptor(\AppSchemaV1.Mint.userIndex, order: .forward)]) private var mints: [Mint]
    @Query(filter: #Predicate<AppSchemaV1.Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [AppSchemaV1.Wallet]
    
    @Binding private var selectedMint: AppSchemaV1.Mint?
    @Binding private var hide: Mint?
    @Binding private var isMultipleSelected: Bool
    
    private var allowsNoneState: Bool = false
    private var allowsMultipleState: Bool = false
    private var label: String
    
    @State private var mintNamesAndIDs = [(name: String, id: UUID)]()
    @State private var selectedID: UUID? = nil
    
    // Special UUID to represent "Multiple" selection
    private static let multipleSelectionID = UUID()
    
    var activeWallet: AppSchemaV1.Wallet? {
        wallets.first
    }
    
    var sortedMintsOfActiveWallet: [AppSchemaV1.Mint] {
        mints.filter { $0.wallet == activeWallet && !$0.hidden }
             .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
    }
    
    init(
        label: String, 
        selectedMint: Binding<Mint?>, 
        allowsNoneState: Bool = false, 
        allowsMultipleState: Bool = false,
        isMultipleSelected: Binding<Bool> = .constant(false),
        hide: Binding<Mint?>? = nil
    ) {
        self.label = label
        self._selectedMint = selectedMint
        self.allowsNoneState = allowsNoneState
        self.allowsMultipleState = allowsMultipleState
        self._isMultipleSelected = isMultipleSelected
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
                    if allowsMultipleState {
                        Text("Multiple...")
                            .tag(Optional(Self.multipleSelectionID))
                    }
                    ForEach(mintNamesAndIDs, id: \.id) { entry in
                        Text(entry.name).tag(Optional(entry.id))
                    }
                }
            }
        }
        .onAppear {
            populate()
            if isMultipleSelected {
                selectedID = Self.multipleSelectionID
            } else if let selectedMint = selectedMint {
                selectedID = selectedMint.mintID
            }
        }
        .onChange(of: selectedID) { _, newValue in
            if let id = newValue {
                if id == Self.multipleSelectionID {
                    // Multiple selection chosen
                    selectedMint = nil
                    isMultipleSelected = true
                } else {
                    // Regular mint selection
                    selectedMint = sortedMintsOfActiveWallet.first { $0.mintID == id }
                    isMultipleSelected = false
                }
            } else {
                // No selection (allowsNoneState case)
                selectedMint = nil
                isMultipleSelected = false
            }
        }
        .onChange(of: selectedMint) { _, newValue in
            if let mint = newValue {
                selectedID = mint.mintID
                isMultipleSelected = false
            } else if !isMultipleSelected {
                selectedID = nil
            }
        }
        .onChange(of: isMultipleSelected) { _, newValue in
            if newValue {
                selectedID = Self.multipleSelectionID
                selectedMint = nil
            } else if selectedID == Self.multipleSelectionID {
                // When switching away from "Multiple", check if parent has set a specific mint
                if let mint = selectedMint {
                    selectedID = mint.mintID
                } else {
                    selectedID = allowsNoneState ? nil : mintNamesAndIDs.first?.id
                }
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
        
        // Only auto-select if we don't already have a valid selection
        if (selectedID == nil || (!mintNamesAndIDs.contains(where: { $0.id == selectedID }) && selectedID != Self.multipleSelectionID)),
           let first = mintNamesAndIDs.first,
           !allowsNoneState && !isMultipleSelected {
            selectedID = first.id
        }
    }
}
