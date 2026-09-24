//
//  PreviewData.swift
//  macadamia
//
//  Shared sample data and an in-memory SwiftData container for SwiftUI previews.
//  Files in this folder are part of DEVELOPMENT_ASSET_PATHS and excluded from
//  release builds.
//

#if DEBUG

import Foundation
import CashuSwift
import SwiftData
import SwiftUI

@MainActor
enum PreviewData {

    /// Shared in-memory `ModelContainer` populated with one active wallet,
    /// three mints, sat/USD/bux balances, and sample transaction history.
    static let modelContainer: ModelContainer = makeContainer()

    /// Shared `AppState` configured for previews (no network, USD conversion).
    static let appState: AppState = AppState(preview: true, preferredUnit: .usd)

    /// Shared `NostrService`. The init is inert — it only loads relay URLs
    /// from `@AppStorage`; `connect()` is only invoked when the database holds
    /// active nostr receive keys, which previews never have.
    static let nostrService: NostrService = NostrService()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Wallet.self, Mint.self, Proof.self, Event.self,
                             NostrKeypair.self, NostrMessage.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("PreviewData failed to build in-memory ModelContainer: \(error)")
        }

        let context = container.mainContext

        let wallet = Wallet(mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
                            seed: "preview",
                            active: true)
        wallet.name = "Preview Wallet"
        context.insert(wallet)

        // Pretend the mint list was backed up two hours ago so MnemonicView
        // shows its live "last backed up" footer.
        MintListBackupStatus.shared.recordSuccess(for: wallet.walletID,
                                                  at: Date().addingTimeInterval(-2 * 3600))

        let mint = makeMint(name: "Preview Mint", host: "preview.mint",
                            keysetPrefix: "preview", units: [.sat, .usd],
                            method: "bolt11", userIndex: 0, wallet: wallet, context: context)

        // Live sat balance: 256 + 512 + 1024 + 2048 = 3,840 sat
        addProofs(amounts: [256, 512, 1024, 2048], unit: .sat,
                  mint: mint, wallet: wallet, context: context)

        // Live USD balance: amounts are in cents, total = 5,555 ¢ = $55.55
        addProofs(amounts: [1234, 4321], unit: .usd,
                  mint: mint, wallet: wallet, context: context)

        // History of previously sent ecash that the mint marked as spent.
        let spentProofs = addProofs(amounts: [128, 64], unit: .sat, state: .spent,
                                    mint: mint, wallet: wallet, context: context)

        // Sample send transaction tied to the spent proofs above.
        let sendEvent = Event(date: Date().addingTimeInterval(-3600),
                              unit: .sat,
                              shortDescription: "Sent 192 sat",
                              visible: true,
                              kind: .send,
                              wallet: wallet,
                              amount: 192,
                              memo: "preview send",
                              mints: [mint])
        sendEvent.proofs = spentProofs
        context.insert(sendEvent)

        let dualUnitMint = makeMint(name: "Sat & USD Mint", host: "sat-usd.preview.mint",
                                    keysetPrefix: "preview-dual", units: [.sat, .usd],
                                    method: "bolt11", userIndex: 1, wallet: wallet, context: context)

        // Additional balances: 12,288 sat and 2,500 cents ($25.00).
        let satProofs = addProofs(amounts: [4096, 8192], unit: .sat,
                                  mint: dualUnitMint, wallet: wallet, context: context)
        let usdProofs = addProofs(amounts: [4, 64, 128, 256, 2048], unit: .usd,
                                  mint: dualUnitMint, wallet: wallet, context: context)

        for (unit, proofs, hoursAgo) in [(Currency.Unit.sat, satProofs, 24.0),
                                         (Currency.Unit.usd, usdProofs, 12.0)] {
            context.insert(Event(date: Date().addingTimeInterval(-hoursAgo * 3600),
                                 unit: unit,
                                 shortDescription: "Ecash received",
                                 visible: true,
                                 kind: .receive,
                                 wallet: wallet,
                                 amount: proofs.sum,
                                 proofs: proofs,
                                 memo: "Preview \(unit.currencyCode) top-up",
                                 mints: [dualUnitMint],
                                 redeemed: true))
        }

        let bux: Currency.Unit = .other("bux")
        let buxMint = makeMint(name: "Bux Mint", host: "bux.preview.mint",
                               keysetPrefix: "preview-bux", units: [bux],
                               method: "branch", userIndex: 2, wallet: wallet, context: context)

        // 1,024 bux issued, then 256 sent: live balance = 768 bux.
        let buxProofs = addProofs(amounts: [256, 512], unit: bux,
                                  mint: buxMint, wallet: wallet, context: context)
        let spentBuxProofs = addProofs(amounts: [256], unit: bux, state: .spent,
                                       mint: buxMint, wallet: wallet, context: context)
        let buxMintEvent = Event(date: Date().addingTimeInterval(-6 * 3600),
                                 unit: bux,
                                 shortDescription: "Ecash created",
                                 visible: true,
                                 kind: .mint,
                                 wallet: wallet,
                                 amount: 1024,
                                 proofs: buxProofs + spentBuxProofs,
                                 memo: "Preview branch deposit",
                                 mints: [buxMint])
        let quoteID = UUID().uuidString
        buxMintEvent.genericMintQuote = CashuSwift.Generic.MintQuote(
            method: "branch",
            quote: quoteID,
            request: "BRANCH-PREVIEW-1024",
            unit: "bux",
            amount: 1024,
            state: .issued,
            expiry: nil,
            raw: ["method": .string("branch"),
                  "quote": .string(quoteID),
                  "request": .string("BRANCH-PREVIEW-1024"),
                  "unit": .string("bux"),
                  "amount": .integer(1024),
                  "state": .string("ISSUED"),
                  "amount_paid": .integer(1024),
                  "amount_issued": .integer(1024)]
        )
        context.insert(buxMintEvent)
        context.insert(Event(date: Date().addingTimeInterval(-2 * 3600),
                             unit: bux,
                             shortDescription: "Sent 256 bux",
                             visible: true,
                             kind: .send,
                             wallet: wallet,
                             amount: 256,
                             proofs: spentBuxProofs,
                             memo: "Preview bux payment",
                             mints: [buxMint]))

        return container
    }

    private static func makeMint(name: String, host: String, keysetPrefix: String,
                                 units: [Currency.Unit], method: String, userIndex: Int,
                                 wallet: Wallet, context: ModelContext) -> Mint {
        do {
            let unitCodes = units.map { $0.currencyCode.lowercased() }
            let keysetData = try JSONSerialization.data(withJSONObject: unitCodes.map {
                ["id": "\(keysetPrefix)-keyset-\($0)", "unit": $0,
                 "active": true, "keys": [:], "input_fee_ppk": 0] as [String: Any]
            })
            let keysets = try JSONDecoder().decode([CashuSwift.Keyset].self, from: keysetData)
            let mint = Mint(url: URL(string: "https://\(host)")!, keysets: keysets)
            mint.nickName = name
            mint.userIndex = userIndex
            mint.wallet = wallet

            let methods = unitCodes.map { ["method": method, "unit": $0] }
            let nutInfo: [String: Any] = ["methods": methods, "disabled": false]
            let infoData = try JSONSerialization.data(withJSONObject: [
                "name": name,
                "nuts": ["4": nutInfo, "5": nutInfo]
            ])
            let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: infoData)
            try mint.setPreviewInfo(info)
            context.insert(mint)
            return mint
        } catch {
            fatalError("PreviewData failed to seed \(name): \(error)")
        }
    }

    @discardableResult
    private static func addProofs(amounts: [Int], unit: Currency.Unit, state: Proof.State = .valid,
                                  mint: Mint, wallet: Wallet, context: ModelContext) -> [Proof] {
        let keyset = mint.keysets.first { Currency.Unit(code: $0.unit) == unit }!
        return amounts.map { amount in
            let proof = Proof(keysetID: keyset.keysetID,
                              C: "\(keyset.keysetID)-\(state)-\(amount)",
                              secret: UUID().uuidString,
                              unit: unit,
                              inputFeePPK: keyset.inputFeePPK,
                              state: state,
                              amount: amount,
                              mint: mint,
                              wallet: wallet)
            context.insert(proof)
            return proof
        }
    }
}

extension View {
    /// Injects everything previews typically need: the in-memory SwiftData
    /// container, an `AppState`, and a `NostrService`.
    @MainActor
    func previewEnvironment() -> some View {
        self
            .environmentObject(PreviewData.appState)
            .environmentObject(PreviewData.nostrService)
            .modelContainer(PreviewData.modelContainer)
    }
}

#endif
