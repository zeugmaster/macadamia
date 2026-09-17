//
//  DepositQuoteRequestView.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import SwiftData
import CashuSwift

// TODO: add "no mints yet" and "no mints support this payment method

struct DepositQuoteRequestView: View {
    let paymentMethod: CashuSwift.Mint.Info.PaymentMethod

    @Environment(\.modelContext) private var modelContext
    @State private var numericalInput: Int = 0
    @State private var selectedMint: Mint?
    @State private var selectedUnit: Unit?
    @State private var availableOptions = [PaymentOption]()
    @State private var quote: DepositQuote?
    @State private var requestTask: Task<Void, Never>?
    @State private var actionButtonState: ActionButtonState = .idle("")
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    private var paymentMethodKind: PaymentMethodKind { paymentMethod.method.kind }

    private var selectedOption: PaymentOption? {
        availableOptions.first {
            $0.mintID == selectedMint?.mintID && $0.method == paymentMethod.method && $0.unit == selectedUnit
        }
    }

    private var availableUnits: [Unit] {
        var seen = Set<Unit>()
        return availableOptions.map(\.unit).filter { seen.insert($0).inserted }
    }

    private var requestedAmount: Int? {
        paymentMethodKind == .onchain || numericalInput == 0 ? nil : numericalInput
    }

    private var actionTitle: String {
        switch paymentMethodKind {
        case .bolt11: String(localized: "Get Invoice")
        case .bolt12: String(localized: "Get Offer")
        case .onchain: String(localized: "Get Address")
        case .generic: String(localized: "Request Quote")
        }
    }

    private var canRequestQuote: Bool {
        guard requestTask == nil, let selectedOption else { return false }
        return (try? Self.validateAmount(requestedAmount, for: selectedOption)) != nil
    }

    var body: some View {
        ZStack {
            List {
                if paymentMethodKind != .onchain {
                    Section {
                        NumericalInputView(output: $numericalInput,
                                           baseUnit: selectedUnit ?? Unit(code: paymentMethod.unit),
                                           exchangeRates: AppState.shared.exchangeRates,
                                           onReturn: requestQuote)
                    } footer: {
                        if paymentMethodKind == .bolt12 {
                            Text("Leave the amount empty to create an offer for any amount.")
                        }
                    }
                }
                Section {
                    MintPicker(label: "Mint",
                               selectedMint: $selectedMint,
                               paymentMethod: paymentMethod.method)
                    if availableUnits.count > 1 {
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(availableUnits, id: \.self) { unit in
                                Text(unit.displayName).tag(Optional(unit))
                            }
                        }
                    }
                }
                Spacer(minLength: 80)
                    .listRowBackground(Color.clear)
            }
            .disabled(requestTask != nil)

            VStack {
                Spacer()
                ActionButton(state: $actionButtonState, hideShadow: true)
                    .actionDisabled(!canRequestQuote)
            }
        }
        .navigationTitle("\(paymentMethod.displayName) Deposit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $quote) { quote in
            DepositQuoteView(quote: quote)
        }
        .onAppear { resetActionButton() }
        .onDisappear { requestTask?.cancel() }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .task(id: "\(selectedMint?.mintID.uuidString ?? "")|\(paymentMethod.method.rawValue)") {
            await refreshOptions()
        }
    }

    @MainActor
    private func refreshOptions() async {
        availableOptions = []
        guard let selectedMint else {
            selectedUnit = nil
            return
        }

        let options = await selectedMint.supportedPaymentOptions(direction: .deposit)
        guard !Task.isCancelled, self.selectedMint?.mintID == selectedMint.mintID else { return }

        availableOptions = options.filter { $0.method == paymentMethod.method }
        let preferredUnit = selectedUnit ?? Unit(code: paymentMethod.unit.lowercased())
        selectedUnit = availableUnits.first(where: { $0 == preferredUnit }) ?? availableUnits.first
    }

    private func resetActionButton() {
        actionButtonState = .idle(actionTitle, action: requestQuote)
    }

    @MainActor
    private func requestQuote() {
        guard canRequestQuote, let selectedMint, let selectedOption else { return }
        let amount = requestedAmount
        actionButtonState = .loading()

        requestTask = Task { @MainActor in
            defer {
                requestTask = nil
                resetActionButton()
            }
            do {
                let result = try await Self.loadQuote(from: selectedMint, option: selectedOption,
                                                      amount: amount, in: modelContext)
                try Task.checkCancellation()
                quote = result
            } catch {
                guard !Task.isCancelled else { return }
                currentAlert = AlertDetail(with: error)
                showAlert = true
            }
        }
    }

    // Save the quote before navigation so it remains resumable if the view closes.
    @MainActor
    static func loadQuote(from mint: Mint, option: PaymentOption, amount: Int?,
                          in context: ModelContext) async throws -> DepositQuote {
        try validateAmount(amount, for: option)
        guard option.mintID == mint.mintID, option.direction == .deposit,
              mint.supportedUnits.contains(option.unit), let wallet = mint.wallet else {
            throw CashuError.inputError("The selected mint cannot request this quote.")
        }
        try Task.checkCancellation()
        let sendableMint = CashuSwift.Mint(mint)
        let response: any CashuSwift.MintQuoteResponse
        var counter: UInt32?

        if option.method.kind == .bolt11 {
            guard let amount else { throw CashuError.invalidAmount }
            response = try await CashuSwift.Bolt11.requestMintQuote(
                .init(unit: option.unitCode, amount: amount), from: sendableMint)
        } else {
            let reservedCounter = try reserveQuoteCounter(for: wallet, in: context)
            counter = reservedCounter
            let key = try CashuSwift.Generic.quoteLockingKey(seed: wallet.seed, counter: reservedCounter)
            let quote = try await CashuSwift.Generic.requestMintQuote(
                .init(method: option.method, unit: option.unitCode, amount: amount,
                      extra: ["pubkey": .string(key.publicKey)]), from: sendableMint)
            guard case .string(let pubkey) = quote.raw["pubkey"],
                  pubkey.lowercased() == key.publicKey.lowercased() else {
                throw CashuError.invalidKey("The mint did not lock the quote to the requested key.")
            }
            response = quote.addingNut20Counter(reservedCounter)
        }

        guard response.unit == option.unitCode,
              !response.quote.isEmpty, !response.request.isEmpty else {
            throw CashuError.inputError("The mint returned an invalid quote.")
        }
        if let responseAmount = response.amount, responseAmount != amount {
            throw CashuError.inputError("The quote amount does not match the requested amount.")
        }
        if option.method.kind == .bolt11, response.amount == nil {
            throw CashuError.inputError("The invoice quote is missing its amount.")
        }
        let expiration = response.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let event: Event
        switch response {
        case let bolt11 as CashuSwift.Bolt11.MintQuote:
            guard let amount = bolt11.amount else { throw CashuError.invalidAmount }
            event = Event.pendingMintEvent(unit: option.unit, shortDescription: "Pending Ecash",
                                           wallet: wallet, quote: bolt11, amount: amount,
                                           expiration: expiration, mint: mint)
        case let generic as CashuSwift.Generic.MintQuote:
            event = Event.pendingMintEvent(unit: option.unit, shortDescription: "Pending Ecash",
                                           wallet: wallet, genericQuote: generic, amount: amount,
                                           expiration: expiration, mint: mint)
        default:
            throw CashuError.unsupportedPaymentMethod("This deposit's quote format cannot be saved.")
        }

        // A returned quote must be saved even if the requesting task was cancelled.
        context.insert(event)
        do {
            try context.save()
        } catch {
            context.delete(event)
            throw macadamiaError.databaseError("The deposit quote could not be saved. \(error.localizedDescription)")
        }
        return DepositQuote(response: response, mint: mint, option: option,
                            requestedAmount: amount, lockingKeyCounter: counter, pendingEvent: event)
    }

    static func validateAmount(_ amount: Int?, for option: PaymentOption) throws {
        switch option.method.kind {
        case .bolt11, .generic:
            guard amount != nil else { throw CashuError.invalidAmount }
        case .bolt12:
            break
        case .onchain:
            guard amount == nil else { throw CashuError.invalidAmount }
        }
        if let amount {
            guard amount > 0 else { throw CashuError.invalidAmount }
            if let minimum = option.minAmount, amount < minimum { throw CashuError.amountOutsideOfLimitRange }
            if let maximum = option.maxAmount, amount > maximum { throw CashuError.amountOutsideOfLimitRange }
        }
    }

    @MainActor
    static func reserveQuoteCounter(for wallet: Wallet, in context: ModelContext) throws -> UInt32 {
        let previous = wallet.mintQuoteCounter
        let counter = previous ?? 0
        // NUT-20 uses a non-hardened child index. Never wrap or reuse a reserved index.
        guard (0..<0x80000000).contains(counter) else {
            throw CashuError.inputError("The wallet has exhausted its quote-locking key indices.")
        }
        wallet.mintQuoteCounter = counter + 1
        do {
            try context.save()
        } catch {
            wallet.mintQuoteCounter = previous
            throw error
        }
        return UInt32(counter)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DepositQuoteRequestView(paymentMethod: .init(method: "branch", unit: "bux"))
    }
    .previewEnvironment()
}
#endif
