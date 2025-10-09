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
    
    @State private var swapStatus: String?
    @State private var currentSwapManager: SwapManager?
    
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
    
    typealias Transaction = BalanceCalculator<Mint>.Transaction
    
    var body: some View {
        ZStack {
            List {
                Section {
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
                }
                
                if let swapStatus {
                    Section {
                        Text(swapStatus)
                            .foregroundStyle(.secondary)
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
        print("\n=== Balance Distribution ===")
        print("Total balance: \(total) sat")
        for (mint, percentage) in allocations {
            let currentBalance = mint.balance(for: .sat)
            let targetBalance = Int((percentage / 100.0) * Double(total))
            let delta = targetBalance - currentBalance
            deltas[mint] = delta
            print("\(mint.displayName): \(currentBalance) sat → \(targetBalance) sat (delta: \(delta >= 0 ? "+" : "")\(delta))")
        }
        
        // Calculate transactions to balance the mints
        let transactions = BalanceCalculator<Mint>.calculateTransactions(for: deltas)
        
        print("\nGenerated \(transactions.count) transactions:")
        for transaction in transactions {
            print("   Transfer \(transaction.amount) sat from \(transaction.from.displayName) to \(transaction.to.displayName)")
        }
        print("=========================\n")
        

        guard let activeWallet else {
            return
        }
        
        buttonState = .loading()
        
//        performTransaction()
        
        func performTransaction(at index: Int = 0) {
            
            guard transactions.indices.contains(index) else {
                print("swap queue index out of bounds, returning")
                transactionsDidFinish()
                
                return
            }
            
            withAnimation {
                swapStatus = "Transfer \(index + 1) of \(transactions.count)..."
            }
            
            let transaction = transactions[index]
            
            currentSwapManager = SwapManager(modelContext: modelContext) { swapState in
                switch swapState {
                case .ready, .loading, .melting, .minting:
                    print("tx from \(transaction.from.url) to \(transaction.to.url) has changed state to \(swapState)")
                case .success:
                    performTransaction(at: index + 1)
                case .fail(let error):
                    print("swap failed due to error: \(String(describing: error))")
                    performTransaction(at: index + 1)
                }
            }
            
            currentSwapManager?.swap(fromMint: transaction.from,
                                     toMint: transaction.to,
                                     amount: transaction.amount,
                                     seed: activeWallet.seed)
        }
    }
    
    private func transactionsDidFinish() {
        currentSwapManager = nil
        swapStatus = nil
        buttonState = .success()
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
