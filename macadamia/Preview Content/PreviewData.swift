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
import SwiftData
import SwiftUI

@MainActor
enum PreviewData {

    /// Shared in-memory `ModelContainer` populated with one active wallet,
    /// a non-hidden mint, several valid proofs, a few spent proofs, and a
    /// sample send transaction.
    static let modelContainer: ModelContainer = makeContainer()

    /// Shared `AppState` configured for previews (no network, USD conversion).
    static let appState: AppState = AppState(preview: true, preferredUnit: .usd)

    /// Shared `NostrService`. The init is inert — it only loads relay URLs
    /// from `@AppStorage`; `connect()` is only invoked when an nsec is stored
    /// in the keychain, which previews never have.
    static let nostrService: NostrService = NostrService()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Wallet.self, Mint.self, Proof.self, Event.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("PreviewData failed to build in-memory ModelContainer: \(error)")
        }

        let context = container.mainContext

        let wallet = Wallet(mnemonic: "preview", seed: "preview", active: true)
        wallet.name = "Preview Wallet"
        context.insert(wallet)

        let mint = Mint(url: URL(string: "https://preview.mint")!, keysets: [])
        mint.nickName = "Preview Mint"
        mint.wallet = wallet
        context.insert(mint)

        // Live balance: 256 + 512 + 1024 + 2048 = 3,840 sat
        for amount in [256, 512, 1024, 2048] {
            let proof = Proof(keysetID: "preview-keyset",
                              C: "preview-valid-\(amount)",
                              secret: UUID().uuidString,
                              unit: .sat,
                              inputFeePPK: 0,
                              state: .valid,
                              amount: amount,
                              mint: mint,
                              wallet: wallet)
            context.insert(proof)
        }

        // History of previously sent ecash that the mint marked as spent.
        let spentProofs: [Proof] = [128, 64].map { amount in
            let proof = Proof(keysetID: "preview-keyset",
                              C: "preview-spent-\(amount)",
                              secret: UUID().uuidString,
                              unit: .sat,
                              inputFeePPK: 0,
                              state: .spent,
                              amount: amount,
                              mint: mint,
                              wallet: wallet)
            context.insert(proof)
            return proof
        }

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

        return container
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
