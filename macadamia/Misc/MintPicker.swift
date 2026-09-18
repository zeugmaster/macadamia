import CashuSwift
import SwiftUI
import SwiftData

struct MintPicker: View {
    @Query(sort: [SortDescriptor(\Mint.userIndex, order: .forward)]) private var mints: [Mint]
    @Query(filter: #Predicate<Wallet> { $0.active }) private var wallets: [Wallet]

    @Binding private var selectedMint: Mint?

    private let label: String
    private let allowsNoneState: Bool
    private let allowedMintIDs: Set<UUID>?
    private let paymentMethod: CashuSwift.PaymentMethodID?
    private let hiddenMint: Mint?

    @State private var supportedMintIDs = Set<UUID>()
    @State private var resolvedSupportID: String?

    init(
        label: String,
        selectedMint: Binding<Mint?>,
        allowsNoneState: Bool = false,
        allowedMintIDs: Set<UUID>? = nil,
        paymentMethod: CashuSwift.PaymentMethodID? = nil,
        hide: Mint? = nil
    ) {
        self.label = label
        self._selectedMint = selectedMint
        self.allowsNoneState = allowsNoneState
        self.allowedMintIDs = allowedMintIDs
        self.paymentMethod = paymentMethod
        self.hiddenMint = hide
    }

    private var visibleMints: [Mint] {
        guard let wallet = wallets.first else { return [] }
        return mints.filter {
            $0.wallet == wallet && !$0.hidden && $0.mintID != hiddenMint?.mintID &&
                (allowedMintIDs?.contains($0.mintID) ?? true)
        }
    }

    private var selectableMints: [Mint] {
        visibleMints.filter { isEnabled($0.mintID) }
    }

    private var selectedID: Binding<UUID?> {
        Binding {
            selectableMints.first { $0.mintID == selectedMint?.mintID }?.mintID
        } set: { id in
            if let mint = selectableMints.first(where: { $0.mintID == id }) {
                selectedMint = mint
            } else if id == nil && allowsNoneState {
                selectedMint = nil
            }
        }
    }

    var body: some View {
        Group {
            if visibleMints.isEmpty {
                Text("No mints yet.")
            } else if paymentMethod != nil && resolvedSupportID != supportRefreshID {
                Text("Checking support...")
                    .foregroundStyle(.secondary)
            } else if selectableMints.isEmpty {
                Text("No supported mints")
                    .foregroundStyle(.secondary)
            } else {
                Picker(label, selection: selectedID) {
                    if allowsNoneState || selectedID.wrappedValue == nil {
                        Text("Select...")
                            .tag(UUID?.none)
                            .selectionDisabled(!allowsNoneState)
                    }
                    ForEach(visibleMints, id: \.mintID) { mint in
                        Text(mint.displayName)
                            .tag(Optional(mint.mintID))
                            .selectionDisabled(!isEnabled(mint.mintID))
                    }
                }
                .menuOrder(.fixed)
            }
        }
        .task(id: supportRefreshID) {
            await refreshPaymentSupport()
        }
        .onChange(of: selectedMint?.mintID) { _, _ in
            updateSelection()
        }
    }

    private var supportRefreshID: String {
        let mintIDs = visibleMints.map { $0.mintID.uuidString }.joined(separator: ",")
        return "\(paymentMethod?.rawValue ?? "")|\(mintIDs)"
    }

    private func isEnabled(_ mintID: UUID) -> Bool {
        paymentMethod == nil ||
            (resolvedSupportID == supportRefreshID && supportedMintIDs.contains(mintID))
    }

    @MainActor
    private func refreshPaymentSupport() async {
        let refreshID = supportRefreshID
        let previousMintID = selectedMint?.mintID
        updateSelection()
        guard let paymentMethod else { return }

        var supportedIDs = Set<UUID>()
        for mint in visibleMints {
            // Payment methods are assumed to be available in both directions.
            let options = await mint.supportedPaymentOptions(direction: .deposit)
            guard !Task.isCancelled else { return }
            if options.contains(where: { $0.method == paymentMethod }) {
                supportedIDs.insert(mint.mintID)
            }
        }

        supportedMintIDs = supportedIDs
        resolvedSupportID = refreshID
        if selectedMint == nil {
            selectedMint = selectableMints.first { $0.mintID == previousMintID }
        }
        updateSelection()
    }

    private func updateSelection() {
        if let selectedMint, selectableMints.contains(where: { $0.mintID == selectedMint.mintID }) {
            return
        }
        selectedMint = allowsNoneState ? nil : selectableMints.first
    }
}
