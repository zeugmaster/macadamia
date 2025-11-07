import SwiftUI
import SwiftData
import CashuSwift


struct SwapView: View {
    
    enum PaymentState {
        case none, ready, setup, melting, minting, success, fail
    }
    
    @State private var state: PaymentState = .none
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var mints: [Mint]
    @Query private var allProofs: [Proof]
    
    @StateObject private var swapManager = SwapManager()
    
    @State private var buttonState = ActionButtonState.idle("")
    @State private var fromMint: Mint?
    @State private var toMint: Mint?
    @State private var amountString = ""
    @FocusState var amountFieldInFocus: Bool

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var amount: Int? {
        Int(amountString)
    }
    
    var isTransferDisabled: Bool {
        guard let toMint, let amount else { return true }
        guard let fromBalance = fromMint?.balance(for: .sat) else { return true }
        return amount > fromBalance || amount < 0
    }
    
    var isProgressSectionVisible: Bool {
        state == .melting || state == .setup || state == .minting || state == .success
    }
    
    var shouldShowSetupCheckmark: Bool {
        state == .melting || state == .minting || state == .success
    }
    
    var shouldShowMeltingCheckmark: Bool {
        state == .minting || state == .success
    }
    
    private var selectedMintBalance: Int {
        fromMint?.balance(for: .sat) ?? 0
    }
    
    private enum InputRemark: Equatable {
        static func == (lhs: InputRemark, rhs: InputRemark) -> Bool {
            switch (lhs, rhs) {
            case (.warning(let message), .warning(let message2)):
                return message == message2
            case (.error(let message), .error(let message2)):
                return message == message2
            default: return false
            }
        }
        
        case warning(String), error(String)
    }
    
    private var inputRemark: InputRemark? {
        if amount ?? 0 > selectedMintBalance {
            return .error("Insufficient balance.")
        } else if amount ?? 0 > Int(Double(selectedMintBalance) * 0.95) {
            return .warning("Transfer amount approaching the total balance risks payment failure due to fees.")
        } else {
            return nil
        }
    }
    
    var listContent: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    MintPicker(label: "From: ", selectedMint: $fromMint, allowsNoneState: false, hide: $toMint)
                    HStack {
                        Text("Balance:")
                        Spacer()
                        Text(String(fromMint?.balance(for: .sat) ?? 0))
                        Text("sat")
                    }
                    .font(.caption)
                    .foregroundStyle(amount ?? 0 > selectedMintBalance ? .failureRed : .secondary)
                    .animation(.linear(duration: 0.2), value: amount ?? 0 > selectedMintBalance)
                }
                
                MintPicker(label: "To: ", selectedMint: $toMint, allowsNoneState: true, hide: $fromMint)
            }

            Section {
                HStack {
                    TextField("enter amount", text: $amountString)
                        .keyboardType(.numberPad)
                        .monospaced()
                        .focused($amountFieldInFocus)
                        .onAppear {
                            amountFieldInFocus = true
                        }
                    Text("sats")
                        .monospaced()
                }
                Group {
                    if let inputRemark {
                        switch inputRemark {
                        case .warning(let string):
                            Text(string)
                                .foregroundStyle(.orange)
                        case .error(let string):
                            Text(string)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .font(.caption)
                .animation(.default, value: inputRemark)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    progressRow(title: "Getting mint quote...", isActive: state == .setup, showCheckmark: shouldShowSetupCheckmark)
                    progressRow(title: "Melting ecash...", isActive: state == .melting, showCheckmark: shouldShowMeltingCheckmark)
                    progressRow(title: "Minting ecash...", isActive: state == .minting, showCheckmark: state == .success)
                }
                .opacity(isProgressSectionVisible ? 1.0 : 0)
                .animation(.easeInOut(duration: 0.2), value: state)
                .listRowBackground(Color.clear)
            }
        }
    }
    
    var actionButtonOverlay: some View {
        VStack {
            Spacer()
            ActionButton(state: $buttonState)
                .actionDisabled(isTransferDisabled)
        }
    }
    
    @ViewBuilder
    func progressRow(title: String, isActive: Bool, showCheckmark: Bool) -> some View {
        HStack {
            if isActive {
                ProgressView()
                    .scaleEffect(0.8)
            } else if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
            }
            Text(title)
                .opacity(isActive ? 1 : 0.5)
        }
    }
    
    var body: some View {
        ZStack {
            listContent
            actionButtonOverlay
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    let temp = fromMint
                    fromMint = toMint
                    toMint = temp
                }) {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(toMint == nil)
            }
        }
        .onAppear {
            buttonState = .idle("Transfer", action: { swap() })
        }
        .onChange(of: swapManager.singleTransactionState) { _, newState in
            handleStateChange(newState)
        }
        .navigationTitle("Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private func handleStateChange(_ newState: SwapManager.State?) {
        guard let newState else { return }
        
        switch newState {
        case .waiting:
            state = .ready
        case .preparing:
            state = .setup
        case .melting:
            state = .melting
        case .minting:
            state = .minting
        case .success:
            state = .success
            buttonState = .success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        case .fail(let error):
            state = .fail
            buttonState = .fail()
            displayAlert(alert: AlertDetail(with: error))
        }
    }
    
    private func swap() {
        amountFieldInFocus = false
        
        guard let fromMint, let toMint, let amount, let activeWallet else {
            return
        }
        
        state = .ready
        swapManager.swap(fromMint: fromMint,
                         toMint: toMint,
                         amount: amount,
                         seed: activeWallet.seed,
                         modelContext: modelContext)
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
