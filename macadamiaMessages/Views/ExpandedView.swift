import SwiftUI
import SwiftData
import Messages
import CashuSwift
import OSLog

struct ExpandedView: View {
    weak var delegate: MessagesViewController?
    
    // Access your existing models just like in the main app!
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    @Query private var allProofs: [Proof]
    
    @State private var amount: String = ""
    @State private var memo: String = ""
    @State private var selectedMint: Mint?
    @State private var buttonState: ExtensionButtonState = .idle("Send Ecash", action: {})
    @State private var currentAlert: ExtensionAlert?
    
    @FocusState private var amountFieldInFocus: Bool
    
    private let coreLogger = Logger(subsystem: "macadamia Messages", category: "ExpandedView")
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var availableMints: [Mint] {
        activeWallet?.availableMints ?? []
    }
    
    private var selectedMintBalance: Int {
        selectedMint?.balance() ?? 0
    }
    
    private var amountInt: Int {
        Int(amount) ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.macadamiaBackground.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.title2)
                        .foregroundColor(.macadamiaOrange)
                    Text("Send Ecash")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.macadamiaPrimary)
                    Spacer()
                    
                    // Close button
                    Button("Done") {
                        delegate?.requestPresentationStyle(.compact)
                    }
                    .foregroundColor(.blue)
                }
                .padding(.top)
                
                if availableMints.isEmpty {
                    // No mints available
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.macadamiaOrange)
                        Text("No Mints Available")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Please add a mint in the main Macadamia app before sending ecash.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.macadamiaSecondary)
                    }
                    .foregroundColor(.macadamiaPrimary)
                    .padding()
                } else {
                    // Main content
                    VStack(spacing: 20) {
                        // Amount input section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Enter amount", text: $amount)
                                    .keyboardType(.numberPad)
                                    .focused($amountFieldInFocus)
                                    .monospaced()
                                    .foregroundColor(.macadamiaPrimary)
                                    .extensionInputStyle()
                                Text("sats")
                                    .foregroundColor(.macadamiaSecondary)
                                    .font(.body)
                            }
                            
                            // Mint picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Send from")
                                    .font(.caption)
                                    .foregroundColor(.macadamiaSecondary)
                                
                                Menu {
                                    ForEach(availableMints, id: \.url) { mint in
                                        Button(mint.displayName) {
                                            selectedMint = mint
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedMint?.displayName ?? "Select mint")
                                            .foregroundColor(selectedMint == nil ? .macadamiaSecondary : .macadamiaPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.macadamiaSecondary)
                                    }
                                    .padding()
                                    .background(Color.macadamiaTertiary)
                                    .cornerRadius(ExtensionTheme.smallCornerRadius)
                                }
                            }
                            
                            // Balance display
                            HStack {
                                Text("Balance:")
                                    .font(.caption)
                                Spacer()
                                Text("\(selectedMintBalance) sats")
                                    .font(.caption)
                                    .monospaced()
                            }
                            .foregroundColor(amountInt > selectedMintBalance ? .macadamiaRed : .macadamiaSecondary)
                            .animation(.linear(duration: 0.2), value: amountInt > selectedMintBalance)
                        }
                        
                        // Memo input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memo (optional)")
                                .font(.caption)
                                .foregroundColor(.macadamiaSecondary)
                            
                            TextField("Add a note for the recipient...", text: $memo)
                                .foregroundColor(.macadamiaPrimary)
                                .extensionInputStyle()
                        }
                        
                        Spacer()
                        
                        // Action button
                        ExtensionActionButton(
                            state: $buttonState,
                            isDisabled: amount.isEmpty || amountInt <= 0 || amountInt > selectedMintBalance || selectedMint == nil
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setupView()
        }
        .extensionAlert($currentAlert)
    }
    
    private func setupView() {
        amountFieldInFocus = true
        buttonState = .idle("Send Ecash", action: generateAndSendToken)
        
        // Auto-select first mint if available
        if selectedMint == nil && !availableMints.isEmpty {
            selectedMint = availableMints.first
        }
    }
    
    private func generateAndSendToken() {
        print("📝 Extension: Sending test message")
        coreLogger.info("Sending test message")
        buttonState = .loading("Sending...")
        
        // Just send a simple test message
        print("📱 Extension: Calling createMessage...")
        delegate?.createMessage()
        buttonState = .success("Sent!")
        
        // Reset form after successful send
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            resetForm()
        }
    }
    
    private func tokenGenerationFailed() {
        buttonState = .error("Failed")
        resetButtonAfterDelay()
    }
    
    private func resetButtonAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            buttonState = .idle("Send Ecash", action: generateAndSendToken)
        }
    }
    
    private func resetForm() {
        amount = ""
        memo = ""
        buttonState = .idle("Send Ecash", action: generateAndSendToken)
        amountFieldInFocus = true
    }
}

#if DEBUG
#Preview {
    ExpandedView(delegate: nil)
        .modelContainer(DatabaseManager.shared.container)
}
#endif
