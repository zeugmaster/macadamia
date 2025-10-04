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
    
    @State private var buttonState = ActionButtonState.idle("Select")
    @State private var allocations: Dictionary<Mint, Double> = [:]
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    struct Transaction {
        let from:   Mint
        let to:     Mint
        let amount: Int
    }
    
    var body: some View {
        ZStack {
            List {
                ForEach(mints) { mint in
                    VStack(alignment: .leading) {
                        Button {
                            toggleSelection(of: mint)
                        } label: {
                            HStack {
                                Image(systemName: allocations.keys.contains(mint) ? "checkmark.circle.fill" : "circle")
                                Text(mint.displayName)
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
                        HStack {
                            if allocations.keys.contains(mint) {
                                HStack {
                                    SmallKnobSlider(value: sliderValue(for: mint), range: 0...100)
                                    Text("\(Int(allocations[mint] ?? 0))%")
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 60)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(false)
            }
        }
        .onAppear {
            buttonState = .idle("Distribute", action: {distribute()})
        }
    }
    
    private func sliderValue(for mint: Mint) -> Binding<Double> {
        Binding {
            allocations[mint] ?? 0.0
        } set: { newValue in
            redistribute(changing: mint, to: newValue)
        }
    }
    
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
        withAnimation(.easeInOut) {
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
    }
    
    private func distribute() {
        var total = 0
        for mint in allocations.keys {
            total += mint.balance(for: .sat)
        }
        
        // Calculate deltas based on allocations
        var deltas: Dictionary<Mint, Int> = [:]
        for (mint, percentage) in allocations {
            let currentBalance = mint.balance(for: .sat)
            let targetBalance = Int((percentage / 100.0) * Double(total))
            deltas[mint] = targetBalance - currentBalance
        }
        
        // Calculate transactions to balance the mints
        let transactions = calculateTransactions(for: deltas)
        
        // TODO: Execute the transactions
        print("Generated \(transactions.count) transactions")
        for transaction in transactions {
            print("  Transfer \(transaction.amount) from \(transaction.from.displayName) to \(transaction.to.displayName)")
        }
        
        let sendableTransactions = transactions.map { t in
            (CashuSwift.Mint(t.from), CashuSwift.Mint(t.to), t.amount)
        }
        
        Task {
            //
            
            
        }
    }
    
    private func calculateTransactions(for deltas: Dictionary<Mint, Int>) -> [Transaction] {
        var transactions: [Transaction] = []
        
        // Separate mints into sources (positive delta) and targets (negative delta)
        var sources = deltas.compactMap { (mint, delta) -> (mint: Mint, available: Int)? in
            delta > 0 ? (mint: mint, available: delta) : nil
        }
        var targets = deltas.compactMap { (mint, delta) -> (mint: Mint, needed: Int)? in
            delta < 0 ? (mint: mint, needed: -delta) : nil
        }
        
        // Sort sources and targets by amount (descending) for better matching
        sources.sort { $0.available > $1.available }
        targets.sort { $0.needed > $1.needed }
        
        var sourceIndex = 0
        var targetIndex = 0
        
        while sourceIndex < sources.count && targetIndex < targets.count {
            let source = sources[sourceIndex]
            let target = targets[targetIndex]
            
            // Calculate transfer amount
            let amountToTransfer = min(source.available, target.needed)
            
            if amountToTransfer > 0 {
                // Create transaction
                transactions.append(Transaction(
                    from: source.mint,
                    to: target.mint,
                    amount: amountToTransfer
                ))
                
                // Update remaining amounts
                sources[sourceIndex].available -= amountToTransfer
                targets[targetIndex].needed -= amountToTransfer
                
                // Move to next source if current is exhausted
                if sources[sourceIndex].available == 0 {
                    sourceIndex += 1
                }
                
                // Move to next target if current is satisfied
                if targets[targetIndex].needed == 0 {
                    targetIndex += 1
                }
            }
        }
        
        return transactions
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
        @objc func changed(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
    }
}
