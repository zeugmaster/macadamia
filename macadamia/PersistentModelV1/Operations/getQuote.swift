//
//  Operations.swift
//  macadamia
//
//  Created by zm on 11.12.24.
//

import Foundation
import CashuSwift
import OSLog

fileprivate let quoteLogger = Logger(subsystem: "macadamia", category: "GetQuoteOperation")


extension AppSchemaV1.Mint {
    
    func getQuote(for quoteRequest: CashuSwift.Bolt11.MintQuoteRequest) async throws -> (quote: CashuSwift.Bolt11.MintQuote,
                                                                                         event: Event) {
        
        guard let wallet = self.wallet else {
            throw macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")
        }
        
        let quote = try await CashuSwift.Bolt11.requestMintQuote(quoteRequest, from: CashuSwift.Mint(self))
        let event = Event.pendingMintEvent(unit: Unit(code: quote.unit),
                                           shortDescription: "Pending Ecash",
                                           wallet: wallet,
                                           quote: quote,
                                           amount: quote.amount ?? 0,
                                           expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry ?? 0)),
                                           mint: self)
        
        quoteLogger.info("Successfully requested mint quote from mint.")
        
        return (quote, event)
    }
    
    @MainActor
    func getQuote(for quoteRequest: CashuSwift.Bolt11.MintQuoteRequest,
                  completion: @escaping (Result<(quote: CashuSwift.Bolt11.MintQuote,
                                                 event: Event), Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = CashuSwift.Mint(self)
        
        Task {
            do {
                let quote = try await CashuSwift.Bolt11.requestMintQuote(quoteRequest, from: sendableMint)
                
                await MainActor.run {
                    let event = Event.pendingMintEvent(unit: Unit(code: quote.unit),
                                                       shortDescription: "Mint Quote",
                                                       wallet: wallet,
                                                       quote: quote,
                                                       amount: quote.amount ?? 0,
                                                       expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry ?? 0)),
                                                       mint: self)
                    completion(.success((quote, event)))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Requests a mint quote for a non-BOLT11 payment method via the generic
    /// endpoint. Every quote is locked to a fresh NUT-20 key derived from the
    /// wallet seed: harmless at mints that ignore the field, required by mints
    /// that enforce locking. The key's derivation counter is grafted into the
    /// quote before it is handed out so issuance can re-derive the key, also
    /// after an app restart.
    @MainActor
    func getGenericMintQuote(method: PaymentMethodKind,
                             unit unitCode: String,
                             amount: Int,
                             completion: @escaping (Result<(quote: CashuSwift.Generic.MintQuote,
                                                            event: Event), Error>) -> Void) {

        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }

        let sendableMint = CashuSwift.Mint(self)
        let seed = wallet.seed

        Task {
            do {
                let counter = UInt32.random(in: 0..<UInt32.max)
                let key = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: counter)

                let quoteRequest = CashuSwift.Generic.MintQuoteRequest(method: method.id,
                                                                       unit: unitCode,
                                                                       amount: amount,
                                                                       extra: ["pubkey": .string(key.publicKey)])

                let quote = try await CashuSwift.Generic.requestMintQuote(quoteRequest, from: sendableMint)
                    .addingNut20Counter(counter)

                await MainActor.run {
                    let event = Event.pendingMintEvent(unit: Unit(code: quote.unit),
                                                       shortDescription: "Mint Quote",
                                                       wallet: wallet,
                                                       genericQuote: quote,
                                                       amount: quote.amount ?? amount,
                                                       expiration: quote.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                                       mint: self)
                    completion(.success((quote, event)))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
}
