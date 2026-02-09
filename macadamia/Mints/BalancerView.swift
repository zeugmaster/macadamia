//
//  BalancerView.swift
//  macadamia
//
//  Created by zm on 21.09.25.
//

import SwiftUI
import SwiftData
import CashuSwift

struct BalancerView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    @StateObject private var swapManager: SwapManager = SwapManager()
    
    @State private var collapseSelector = false
    
    @State private var buttonState = ActionButtonState.idle(String(localized: "Select"))
    @State private var allocations: Dictionary<Mint, Double> = [:]
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }
    
    /// Returns true if the proposed redistribution represents less than 1% change
    private var isNegligibleChange: Bool {
        guard !allocations.isEmpty else { return true }
        
        // Calculate total balance across selected mints
        var total = 0
        for mint in allocations.keys {
            total += mint.balance(for: .sat)
        }
        
        guard total > 0 else { return true }
        
        // Calculate sum of absolute deltas
        var totalDelta = 0
        for (mint, percentage) in allocations {
            let currentBalance = mint.balance(for: .sat)
            let targetBalance = Int((percentage / 100.0) * Double(total))
            let delta = abs(targetBalance - currentBalance)
            totalDelta += delta
        }
        
        // Check if total change is less than 1% of total balance
        let changePercentage = Double(totalDelta) / Double(total)
        return changePercentage < 0.01
    }
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    typealias Transaction = BalanceCalculator<Mint>.Transaction
    
    enum BalancerItem: Identifiable, Equatable {
        case mintRow(Mint)
        case sliderRow(Mint)
        
        var id: String {
            switch self {
            case .mintRow(let mint): return "row:\(mint.id)"
            case .sliderRow(let mint): return "slider:\(mint.id)"
            }
        }
        
        static func == (lhs: BalancerItem, rhs: BalancerItem) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    var items: [BalancerItem] {
        mints.flatMap { mint in
            var arr: [BalancerItem] = [.mintRow(mint)]
            if allocations.keys.contains(mint) {
                arr.append(.sliderRow(mint))
            }
            return arr
        }
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    if collapseSelector {
                        VStack(alignment: .leading) {
                            Text(String(localized: "\(allocations.count) Mint\(allocations.count == 1 ? "" : "s") selected"))
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            switch item {
                            case .mintRow(let mint):
                                HStack {
                                    Image(systemName: allocations.keys.contains(mint) ? "checkmark.circle.fill" : "circle")
                                    Button {
                                        withAnimation {
                                            toggleSelection(of: mint)
                                        }
                                    } label: {
                                        HStack { // mint name and balance
                                            Text(mint.displayName)
                                                .lineLimit(1)
                                            Spacer()
                                            Group {
                                                let balance = mint.balance(for: .sat)

                                                Text(balance, format: .number)
                                                    .monospaced()
                                                    .contentTransition(.numericText(value: Double(balance)))
                                                    .animation(.snappy, value: balance)

                                                Text(" sat")
                                            }
                                            .monospaced()
                                        }
                                    }
                                }
                            case .sliderRow(let mint):
                                HStack {
                                    SmallKnobSlider(value: sliderValue(for: mint), range: 0...100)
                                    Text("\(Int(allocations[mint] ?? 0))%")
                                        .foregroundStyle(.secondary)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .transition(.opacity)
                            }
                        }
                    }
                }
                
                if let states = swapManager.multiTransactionState {
                    Section(header: Text("Transfer Progress")) {
                        ForEach(states.indices, id: \.self) { index in
                            HStack {
                                stateIcon(for: states[index].state)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(String(localized: "Transfer \(index + 1)"))
                                        Spacer()
                                        stateText(for: states[index].state)
                                    }
                                    HStack(spacing: 4) {
                                        Text(states[index].from.displayName)
                                            .lineLimit(1)
                                        Image(systemName: "arrow.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(states[index].to.displayName)
                                            .lineLimit(1)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 60)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(isNegligibleChange)
            }
        }
        .onAppear {
            buttonState = .idle(String(localized: "Distribute"), action: {distribute()})
        }
        .onChange(of: swapManager.multiTransactionState) { _, states in
            handleSwapStateChange(states)
        }
        .navigationBarBackButtonHidden(buttonState.type == .loading)
        .navigationTitle("Distribute")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private func sliderValue(for mint: Mint) -> Binding<Double> {
        Binding {
            allocations[mint] ?? 0.0
        } set: { newValue in
            redistribute(changing: mint, to: newValue)
        }
    }
    
    // updates the sliders in real time
    private func redistribute(changing mint: Mint, to newValue: Double) {
        guard allocations.keys.contains(mint) else { return }
        let clamped = min(100, max(0, newValue))

        // If only one active mint, it must take 100%
        if allocations.count == 1 {
            allocations[mint] = 100
            return
        }

        let oldOthers = allocations
            .filter { $0.key != mint }
            .map(\.value)
            .reduce(0, +)

        allocations[mint] = clamped
        let targetOthers = 100 - clamped

        if oldOthers == 0 {
            let share = targetOthers / Double(allocations.count - 1)
            for (key, _) in allocations where key != mint {
                allocations[key] = share
            }
        } else {
            let scale = targetOthers / oldOthers
            for (key, value) in allocations where key != mint {
                allocations[key] = value * scale
            }
        }
    }
    
    private func toggleSelection(of mint: Mint) {
        if allocations.keys.contains(mint) {
            allocations.removeValue(forKey: mint)
            for key in allocations.keys {
                allocations[key] = 100.0 / Double(allocations.count)
            }
        } else {
            let newAllocation = 100.0 / Double(allocations.count + 1)
            allocations[mint] = newAllocation
            for key in allocations.keys {
                allocations[key] = newAllocation
            }
        }
    }
    
    private func handleSwapStateChange(_ states: [SwapManager.TransferState]?) {
        guard let states else { return }
        
        // Check if all swaps are complete (either success or fail)
        let allComplete = states.allSatisfy { transferState in
            if case .success = transferState.state { return true }
            if case .fail = transferState.state { return true }
            return false
        }
        
        if allComplete {
            // Check if all succeeded
            let allSucceeded = states.allSatisfy { transferState in
                if case .success = transferState.state { return true }
                return false
            }
            
            if allSucceeded {
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } else {
                buttonState = .fail()
            }
        }
    }
    
    @ViewBuilder
    private func stateIcon(for state: SwapManager.State) -> some View {
        switch state {
        case .waiting:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .preparing:
            ProgressView()
                .scaleEffect(0.7)
        case .melting, .minting:
            ProgressView()
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private func stateText(for state: SwapManager.State) -> some View {
        switch state {
        case .waiting:
            Text("Waiting...")
                .foregroundColor(.secondary)
        case .preparing:
            Text("Preparing...")
        case .melting:
            Text("Paying...")
        case .minting:
            Text("Issuing...")
        case .success:
            Text("Complete")
                .foregroundColor(.green)
        case .fail(let error):
            VStack(alignment: .leading) {
                Text("Failed")
                    .foregroundColor(.red)
                Text(String(describing: error))
                    .font(.caption2)
            }
        }
    }
    
    private func distribute() {
        var total = 0
        var transferLimits: [Mint: Mint.TransferLimits] = [:]
        
        // Calculate total and limits for each mint
        for mint in allocations.keys {
            let balance = mint.balance(for: .sat)
            total += balance
            transferLimits[mint] = mint.transferLimits(for: .sat)
        }
        
        // Calculate deltas based on allocations, respecting transfer limits
        var deltas: Dictionary<Mint, Int> = [:]
        print("\n=== Balance Distribution ===")
        print("Total balance: \(total) sat")
        
        for (mint, percentage) in allocations {
            let currentBalance = mint.balance(for: .sat)
            let targetBalance = Int((percentage / 100.0) * Double(total))
            var delta = targetBalance - currentBalance
            
            // If this mint needs to send funds (negative delta), check transfer limits
            if delta < 0 {
                let limits = transferLimits[mint]!
                let amountToSend = -delta
                
                if amountToSend > limits.maxTransferable {
                    print("⚠️  \(mint.displayName) would exceed safe transfer limit:")
                    print("    Requested: \(amountToSend) sat")
                    print("    Safe max: \(limits.maxTransferable) sat")
                    print("    Reserved for fees: \(limits.reservedForFees) sat")
                    
                    // Cap the delta to safe maximum
                    delta = -limits.maxTransferable
                }
            }
            
            deltas[mint] = delta
            print("\(mint.displayName): \(currentBalance) sat → \(currentBalance + delta) sat (delta: \(delta >= 0 ? "+" : "")\(delta))")
        }
        
        // Validate transfers before proceeding
        let transactions = BalanceCalculator<Mint>.calculateTransactions(for: deltas)
        
        print("\nGenerated \(transactions.count) transactions:")
        var hasInvalidTransfer = false
        for transaction in transactions {
            let limits = transferLimits[transaction.from]!
            if transaction.amount > limits.maxTransferable {
                print("   ❌ Transfer \(transaction.amount) sat from \(transaction.from.displayName) EXCEEDS LIMIT (\(limits.maxTransferable) sat)")
                hasInvalidTransfer = true
            } else {
                print("   ✓ Transfer \(transaction.amount) sat from \(transaction.from.displayName) to \(transaction.to.displayName)")
            }
        }
        print("=========================\n")
        
        if hasInvalidTransfer {
            displayAlert(alert: AlertDetail(
                title: String(localized: "Transfer Limit Exceeded"),
                description: String(localized: "One or more transfers would exceed safe limits. Please adjust your allocation to leave more balance for fees.")
            ))
            return
        }
        
        guard let activeWallet else {
            return
        }
        
        withAnimation {
            collapseSelector = true
        }
        
        buttonState = .loading()
        
        // Convert transactions to the format SwapManager expects
        let swapTransfers = transactions.map { transaction in
            (from: transaction.from, to: transaction.to, amount: transaction.amount, seed: activeWallet.seed)
        }
        
        // Start the batch swap
        swapManager.swap(transfers: swapTransfers, modelContext: modelContext)
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct SmallKnobSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )

        // Set darker color for filled part of slider
        slider.minimumTrackTintColor = UIColor.lightGray

        // smaller circular knob
        let knobSize: CGFloat = 10
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: knobSize, height: knobSize))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: knobSize, height: knobSize)))
        }
        slider.setThumbImage(image, for: .normal)
        slider.setThumbImage(image, for: .highlighted)

        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.value = Float(value)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: SmallKnobSlider
        init(_ parent: SmallKnobSlider) { self.parent = parent }
        @MainActor @objc func changed(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
    }
}

enum Item: Identifiable, Equatable {
    case row(String)
    case detail(String)
    var id: String {
        switch self {
        case .row(let s): return "row:\(s)"
        case .detail(let s): return "detail:\(s)"
        }
    }
}

struct RowResizeTestView: View {
    let rows = ["One", "Two", "Three", "Four"]
    @State var selection = Set<String>()
    
    var items: [Item] {
        rows.flatMap { s in
            var arr: [Item] = [.row(s)]
            if selection.contains(s) { arr.append(.detail(s)) }
            return arr
        }
    }
    
    var body: some View {
        List {
            ForEach(items) { item in
                switch item {
                case .row(let s):
                    HStack {
                        Image(systemName: selection.contains(s) ? "checkmark.circle.fill" : "circle")
                        Text(s)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.default) {
                            toggle(s)
                        }
                    }
                case .detail(let s):
                    Text("Here goes the slider for \(s)")
                }
            }
        }
    }
    
    func toggle(_ row: String) {
        if selection.contains(row) { selection.remove(row) }
        else { selection.insert(row) }
    }
}

#Preview {
    RowResizeTestView()
}
