//
//  Restore.swift
//  macadamia
//
//  Created by zm on 16.01.25.
//

import Foundation
import CashuSwift
import BIP39
import OSLog

fileprivate let restoreLogger = Logger(subsystem: "macadamia", category: "RestoreOperation")

/// Result of restoring a single mint via `CashuSwift.restore`.
struct MintRestoreResult: Sendable {
    let mintURL: URL
    let keysets: [CashuSwift.Keyset]
    let keysetResults: [CashuSwift.KeysetRestoreResult]
    let dleqPassed: Bool
}

extension macadamiaApp {

    /// Returns an `AsyncStream` that restores proofs from each mint sequentially,
    /// yielding a `MintRestoreResult` after each mint completes.
    ///
    /// Per-mint errors are logged and skipped — the stream continues with the next mint.
    static func restoreSequence(
        mints: [CashuSwift.Mint],
        seed: String
    ) -> AsyncStream<MintRestoreResult> {
        AsyncStream { continuation in
            Task {
                for mint in mints {
                    do {
                        let (proofsByKeyset, dleqPassed) = try await CashuSwift.restore(
                            from: mint,
                            with: seed,
                            batchSize: 50
                        )

                        restoreLogger.info("""
                            DLEQ check on restore proofs from mint \
                            \(mint.url.absoluteString) was\(dleqPassed ? " " : " NOT ")successful.
                            """)

                        continuation.yield(
                            MintRestoreResult(
                                mintURL: mint.url,
                                keysets: mint.keysets,
                                keysetResults: proofsByKeyset,
                                dleqPassed: dleqPassed
                            )
                        )
                    } catch {
                        restoreLogger.warning("""
                            Restore failed for mint \(mint.url.absoluteString): \(error). \
                            Skipping.
                            """)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Assembles a full `Wallet` object graph from restore results.
    ///
    /// Creates the `Wallet`, internal `Mint` and `Proof` objects,
    /// sets up all bidirectional relationships and derivation counters,
    /// and produces a restore `Event`. No `ModelContext` is needed.
    @MainActor
    static func assembleRestoredWallet(
        from results: [MintRestoreResult],
        mnemonic: Mnemonic
    ) -> (wallet: Wallet, mints: [Mint], proofs: [Proof], event: Event) {
        let seed = String(bytes: mnemonic.seed)
        let newWallet = Wallet(mnemonic: mnemonic.phrase.joined(separator: " "),
                               seed: seed)

        var restoredProofs = [Proof]()
        var newMints = [Mint]()

        for result in results {
            let newMint = Mint(url: result.mintURL, keysets: result.keysets)
            newMints.append(newMint)
            newWallet.mints.append(newMint)
            newMint.wallet = newWallet

            guard !result.keysetResults.isEmpty else { continue }

            for keysetResult in result.keysetResults {
                let internalProofs = keysetResult.proofs.map { p in
                    Proof(p,
                          unit: Unit(keysetResult.unitString) ?? .sat,
                          inputFeePPK: keysetResult.inputFeePPK,
                          state: .valid,
                          mint: newMint,
                          wallet: newWallet)
                }

                restoredProofs.append(contentsOf: internalProofs)
                newMint.proofs?.append(contentsOf: internalProofs)
                newWallet.proofs.append(contentsOf: internalProofs)

                newMint.increaseDerivationCounterForKeysetWithID(
                    keysetResult.keysetID,
                    by: keysetResult.derivationCounter
                )
            }

            restoreLogger.info("""
                Restored proofs from mint \(newMint.url.absoluteString). \
                New keyset derivation counters: \
                \(result.keysetResults.map(\.derivationCounter))
                """)
        }

        let event = Event.restoreEvent(
            shortDescription: "Restore",
            wallet: newWallet,
            longDescription: """
                Successfully recovered ecash \
                from \(newWallet.mints.count) mint(s) \
                using a seed phrase!
                """
        )

        return (newWallet, newMints, restoredProofs, event)
    }
}
