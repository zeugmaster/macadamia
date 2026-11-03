//
//  OnchainMeltView.swift
//  macadamia
//
//  Created by zm on 03.11.26.
//

import SwiftUI
import SwiftData
import CashuSwift

/// NUT-30 withdrawal to a Bitcoin address: amount and mint, a quote with the mint's fee tiers,
/// the payment, then the transaction view until the mint reports the payout confirmed.
/// One mint, sats only. The transaction view watches the explorer; this view watches the mint.
struct OnchainMeltView: View {

    /// Where the payment goes, from a bare address or a BIP-21 `bitcoin:` link.
    struct Destination: Equatable {
        let address: String
        /// The link's `amount` (BTC) in sat, when it carries a usable one.
        let amount: Int?

        init?(_ input: String) {
            let link = BIP321.parse(input)
            let address = (link?.address ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
            guard InputValidator.isBitcoinAddress(address) else { return nil }
            self.address = address
            let sats = link?.amount.flatMap { Decimal(string: $0) }.map { $0 * 100_000_000 }
            amount = sats.flatMap { Int(exactly: NSDecimalNumber(decimal: $0)) }.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissToRoot) private var dismissToRoot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Wallet> { $0.active }) private var wallets: [Wallet]
    /// The tier the user picked last time, preselected while the mint still offers it.
    @AppStorage("onchainPreferredFeeIndex") private var preferredFeeIndex = 0

    private let destination: Destination?

    @State private var amount: Int
    @State private var amountFromLink: Bool
    @State private var selectedMint: Mint?
    /// Each mint's on-chain sat withdrawal option; mints without one cannot be picked.
    @State private var options: [UUID: PaymentOption] = [:]
    @State private var loadingMints = true
    /// The latest quote the mint reported; it carries the outpoint once the payment is broadcast.
    @State private var quote: CashuSwift.Onchain.MeltQuote?
    @State private var selectedFeeIndex: Int?
    @State private var pendingEvent: Event?
    @State private var isBusy = false
    @State private var isChecking = false
    @State private var buttonState = ActionButtonState.idle("")
    @State private var statusText = String(localized: "Checking with the mint")
    @State private var hourglassStatus = HourglassProgressView.Status.waiting
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    /// A scanned or typed address or `bitcoin:` link.
    init(request: String) {
        destination = Destination(request)
        _amount = State(initialValue: destination?.amount ?? 0)
        _amountFromLink = State(initialValue: destination?.amount != nil)
    }

    /// Reopens a pending withdrawal from the transaction list and keeps asking the mint.
    init(pendingEvent: Event) {
        let context = pendingEvent.onchainMeltContext
        destination = context.flatMap { Destination($0.quote.request) }
        _amount = State(initialValue: context?.quote.amount ?? 0)
        _amountFromLink = State(initialValue: true)
        _selectedMint = State(initialValue: pendingEvent.mints?.first)
        _quote = State(initialValue: context?.quote)
        _pendingEvent = State(initialValue: pendingEvent)
    }

    private var selectedOption: PaymentOption? {
        selectedMint.flatMap { options[$0.mintID] }
    }

    private var selectedFee: CashuSwift.Onchain.FeeOption? {
        quote?.feeOptions.first { $0.feeIndex == selectedFeeIndex }
    }

    private var amountOutsideLimits: Bool {
        amount > 0 && selectedOption?.isAmountWithinLimits(amount) == false
    }

    private var actionDisabled: Bool {
        guard !isBusy, let selectedMint, let selectedOption else { return true }
        if quote != nil { return selectedFee == nil }
        return amount <= 0 || !selectedOption.isAmountWithinLimits(amount) || selectedMint.balance(for: .sat) < amount
    }

    /// The user's standing choice when the mint still offers it, otherwise the mint's first tier.
    static func defaultFeeIndex(in options: [CashuSwift.Onchain.FeeOption], preferred: Int) -> Int? {
        options.first { $0.feeIndex == preferred }?.feeIndex ?? options.first?.feeIndex
    }

    var body: some View {
        ZStack {
            if let destination, let pendingEvent, let mint = pendingEvent.mints?.first {
                OnchainTransaction(address: destination.address, settled: hourglassStatus == .success,
                                   quoteID: quote?.quote, txid: quote?.transactionID,
                                   status: MintStatusRow(mint: mint.displayName, text: statusText, status: hourglassStatus))
            } else if let destination {
                form(for: destination)
                VStack {
                    Spacer()
                    ActionButton(state: $buttonState)
                        .actionDisabled(actionDisabled)
                }
            } else {
                ContentUnavailableView("Invalid address", systemImage: "exclamationmark.triangle",
                                       description: Text("This is not a Bitcoin address the wallet can pay."))
            }
        }
        .animation(reduceMotion ? nil : .default, value: pendingEvent?.eventID)
        .navigationTitle("On-chain Withdrawal")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear(perform: updateButton)
        .onChange(of: isBusy) { _, _ in updateButton() }
        .onChange(of: quote?.quote) { _, _ in updateButton() }
        // The inputs are locked while a quote exists; this only catches programmatic changes, e.g. a mint disappearing.
        .onChange(of: amount) { _, _ in if pendingEvent == nil { quote = nil } }
        .onChange(of: selectedMint?.mintID) { _, _ in if pendingEvent == nil { quote = nil } }
        .task { await loadMints() }
        .task(id: pendingEvent?.eventID) { await pollMint() }
        .sensoryFeedback(trigger: hourglassStatus) { _, status in status == .success ? .success : nil }
        .task(id: hourglassStatus) {
            guard hourglassStatus == .success else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .default) { dismissToRoot() }
        }
    }

    // MARK: - Form

    private func form(for destination: Destination) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.primary.opacity(0.6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.address)
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(OnchainTransaction.network(for: destination.address)?.rawValue ?? String(localized: "Unknown network"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Pay to")
            }

            Section {
                if amountFromLink {
                    HStack {
                        Text("Amount")
                        Spacer()
                        AmountView(amount: amount, unit: .sat)
                            .monospaced()
                    }
                    // Plain style: the app's white accent would hide a default button label on a light row.
                    Button("Change amount") { amountFromLink = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else {
                    NumericalInputView(output: $amount, baseUnit: .sat,
                                       exchangeRates: AppState.shared.exchangeRates, onReturn: requestQuote)
                }
            } footer: {
                HStack {
                    Text("Min: \(selectedOption?.minAmount ?? 0)")
                    Text("Max: \(selectedOption?.maxAmount ?? 0)")
                }
                .opacity(amountOutsideLimits ? 1 : 0)
                .accessibilityHidden(!amountOutsideLimits)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(amountOutsideLimits ? .failureRed : .secondary)
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: amountOutsideLimits)
            }
            // Locked from the moment a quote is requested: the quote is for this amount and mint.
            .disabled(quote != nil || isBusy)

            Section {
                if loadingMints {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading mints...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MintPicker(label: String(localized: "Mint"), selectedMint: $selectedMint,
                               allowedMintIDs: Set(options.keys))
                }
            } footer: {
                if let selectedMint {
                    HStack(spacing: 4) {
                        Text("Balance:")
                        AmountView(amount: selectedMint.balance(for: .sat), unit: .sat)
                    }
                }
            }
            .disabled(quote != nil || isBusy)

            if let quote {
                feeSection(for: quote)
            }

            Spacer(minLength: 80)
                .listRowBackground(Color.clear)
        }
    }

    /// The mint's fee tiers: pick how fast the payment should confirm. The choice becomes the preference.
    private func feeSection(for quote: CashuSwift.Onchain.MeltQuote) -> some View {
        Section {
            ForEach(quote.feeOptions, id: \.feeIndex) { option in
                Button {
                    selectedFeeIndex = option.feeIndex
                    preferredFeeIndex = option.feeIndex
                } label: {
                    HStack {
                        Image(systemName: option.feeIndex == selectedFeeIndex ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("~\(Duration.seconds(option.estimatedBlocks * 600).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 1)))")
                            Text("^[\(option.estimatedBlocks) block](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountView(amount: option.feeReserve, unit: .sat)
                            .monospaced()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if let selectedFee {
                HStack {
                    Text("Total")
                    Spacer()
                    AmountView(amount: quote.amount + selectedFee.feeReserve, unit: .sat)
                        .monospaced()
                }
                .fontWeight(.semibold)
            }
        } header: {
            Text("Network fee")
        } footer: {
            Text("The fee is a reserve. Whatever the transaction does not use comes back as change. Your choice is kept for next time.")
        }
    }

    private func updateButton() {
        if isBusy {
            buttonState = .loading()
        } else if quote != nil {
            buttonState = .idle(String(localized: "Pay"), action: pay)
        } else {
            buttonState = .idle(String(localized: "Get Quote"), action: requestQuote)
        }
    }

    private func show(_ alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }

    // MARK: - Flow

    @MainActor
    private func loadMints() async {
        guard pendingEvent == nil, let wallet = wallets.first else { return }
        var loaded: [UUID: PaymentOption] = [:]
        for mint in wallet.mints where !mint.hidden {
            let available = await mint.supportedPaymentOptions(direction: .withdraw)
            guard !Task.isCancelled else { return }
            loaded[mint.mintID] = available.first { $0.method == .onchain && $0.unit == .sat }
        }
        options = loaded
        loadingMints = false
    }

    private func requestQuote() {
        guard !actionDisabled, let destination, let selectedMint else { return }
        isBusy = true
        let amount = amount
        Task {
            defer { isBusy = false }
            do {
                let info = try await selectedMint.loadInfo()
                let fresh = try await CashuSwift.Onchain.requestMeltQuote(
                    .init(unit: Unit.sat.currencyCode, request: destination.address, amount: amount),
                    from: CashuSwift.Mint(selectedMint), info: info)
                quote = fresh
                selectedFeeIndex = Self.defaultFeeIndex(in: fresh.feeOptions, preferred: preferredFeeIndex)
            } catch {
                show(AlertDetail(with: error))
            }
        }
    }

    private func pay() {
        guard !actionDisabled, let quote, let selectedFee, let selectedMint, let wallet = wallets.first else { return }
        guard let selection = selectedMint.select(amount: quote.amount + selectedFee.feeReserve, unit: .sat) else {
            show(AlertDetail(title: String(localized: "Insufficient Funds 💰"),
                             description: String(localized: "The wallet was unable to collect enough ecash for this transaction.")))
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                guard let info = try await selectedMint.loadInfo() else {
                    throw CashuError.inputError(String(localized: "The mint's settings could not be loaded."))
                }
                let context = try CashuSwift.Onchain.prepareMelt(quote: quote, feeIndex: selectedFee.feeIndex,
                                                                 from: CashuSwift.Mint(selectedMint),
                                                                 proofs: selection.selected.sendable(),
                                                                 seed: wallet.seed, info: info)
                let event = try reserve(context, inputs: selection.selected, mint: selectedMint, wallet: wallet)
                statusText = String(localized: "Sending ecash to the mint")
                pendingEvent = event
                await submit(event)
            } catch {
                show(AlertDetail(with: error))
            }
        }
    }

    /// One durable step before anything is sent: the inputs go pending, the output counter
    /// advances past the blank outputs, and the context stays with the event for recovery.
    private func reserve(_ context: CashuSwift.Onchain.MeltContext, inputs: [Proof], mint: Mint, wallet: Wallet) throws -> Event {
        let event = Event.pendingMeltEvent(unit: .sat, shortDescription: String(localized: "Pending Withdrawal"), wallet: wallet,
                                           genericQuote: try context.quote.asGeneric(), amount: context.quote.amount,
                                           expiration: context.quote.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                           mints: [mint], proofs: inputs)
        event.onchainMeltContext = context
        if let range = context.material.counterRange {
            mint.increaseDerivationCounterForKeysetWithID(range.keysetID, by: range.next - range.start)
        }
        modelContext.insert(event)
        inputs.setState(.pending)
        do {
            try modelContext.save()
        } catch {
            inputs.setState(.valid)
            modelContext.delete(event)
            throw macadamiaError.databaseError(String(localized: "The withdrawal could not be saved. \(error.localizedDescription)"))
        }
        return event
    }

    /// One POST. A transport error leaves the outcome unknown, so the state check decides from here.
    private func submit(_ event: Event) async {
        guard let context = event.onchainMeltContext, let mint = event.mints?.first else { return }
        do {
            let result = try await CashuSwift.Onchain.melt(context: context, from: CashuSwift.Mint(mint))
            apply(result, to: event)
        } catch {
            show(AlertDetail(with: error))
            await checkState()
        }
    }

    /// The mint reports PENDING until the payout has enough confirmations, which can take hours.
    private func pollMint() async {
        while !Task.isCancelled, pendingEvent != nil, hourglassStatus == .waiting {
            if !isBusy { await checkState() }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func checkState() async {
        guard !isChecking, let event = pendingEvent, let context = event.onchainMeltContext, let mint = event.mints?.first else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let result = try await CashuSwift.Onchain.meltState(context: context, from: CashuSwift.Mint(mint))
            guard pendingEvent?.eventID == event.eventID else { return }
            apply(result, to: event)
        } catch {
            statusText = String(localized: "The mint could not be reached. Retrying...")
        }
    }

    private func apply(_ result: CashuSwift.Onchain.MeltResult, to event: Event) {
        quote = result.quote
        switch result.quote.state {
        case .paid:
            finalize(result, event: event)
        case .unpaid, .failed:
            // The mint released the inputs. An unpaid quote can be paid again; a failed one cannot.
            release(event)
            if result.quote.state == .failed { quote = nil }
            show(AlertDetail(title: String(localized: "Withdrawal Not Paid"),
                             description: String(localized: "The mint did not send the payment. Your ecash is back in your balance.")))
        default:
            // The cubes above tell the chain's story; the mint only says "pending" until its threshold is reached.
            statusText = String(localized: "Waiting for the mint to confirm")
        }
    }

    private func release(_ event: Event) {
        event.proofs?.setState(.valid)
        event.visible = false
        try? modelContext.save()
        pendingEvent = nil
    }

    private func finalize(_ result: CashuSwift.Onchain.MeltResult, event: Event) {
        guard let wallet = wallets.first ?? event.wallet, let mint = event.mints?.first,
              let context = event.onchainMeltContext, let settled = try? result.quote.asGeneric() else { return }
        var change: [Proof] = []
        switch result.changeRecovery {
        case .complete(let proofs):
            do {
                // The counter range for these blank outputs was advanced when the context was reserved.
                change = try mint.addProofs(proofs, to: modelContext, increaseDerivationCounter: false)
            } catch {
                // Stay pending: the next poll returns the same change and tries again.
                show(AlertDetail(title: String(localized: "Change Not Saved"), description: error.localizedDescription))
                return
            }
        case .failed(let reason):
            // Settled, but the change did not verify. The hidden pending event keeps the context for recovery.
            logger.error("on-chain withdrawal change could not be recovered: \(reason.rawValue)")
            show(AlertDetail(title: String(localized: "Change Not Verified"),
                             description: String(localized: "The payment went through, but the mint's fee change could not be verified and was not added to your balance.")))
        case .pending:
            break
        }
        let inputs = event.proofs ?? []
        inputs.setState(.spent)
        event.visible = false
        let melt = Event.meltEvent(unit: .sat, shortDescription: String(localized: "Withdrawal"), wallet: wallet,
                                   amount: result.quote.amount, longDescription: "", mints: [mint], change: change,
                                   genericQuote: settled)
        melt.inputFee = context.inputFee
        melt.paymentFee = max(0, inputs.sum - result.quote.amount - context.inputFee - change.sum)
        modelContext.insert(melt)
        do {
            try modelContext.save()
        } catch {
            show(AlertDetail(title: String(localized: "Database Error"), description: error.localizedDescription))
        }
        statusText = String(localized: "Paid!")
        hourglassStatus = .success
    }
}

extension AppSchemaV1.Event {
    /// The stored quote read back with its NUT-30 fields, for routing and history.
    var onchainMeltQuote: CashuSwift.Onchain.MeltQuote? {
        guard let quote = genericMeltQuote, quote.method == .onchain,
              let data = try? JSONEncoder().encode(quote) else { return nil }
        return try? JSONDecoder().decode(CashuSwift.Onchain.MeltQuote.self, from: data)
    }
}

extension CashuSwift.Onchain.MeltQuote {
    /// The event factories take the generic shape; every NUT-30 field survives in its `raw`.
    func asGeneric() throws -> CashuSwift.Generic.MeltQuote {
        try JSONDecoder().decode(CashuSwift.Generic.MeltQuote.self, from: JSONEncoder().encode(self))
    }

    /// `outpoint` is `txid:vout`.
    var transactionID: String? {
        outpoint?.split(separator: ":").first.map(String.init)
    }
}

#if DEBUG
#Preview("Address") {
    NavigationStack {
        OnchainMeltView(request: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.0005")
    }
    .previewEnvironment()
}

#Preview("Invalid") {
    NavigationStack {
        OnchainMeltView(request: "gabagool")
    }
    .previewEnvironment()
}
#endif
