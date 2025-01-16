//
//  Operations.swift
//  macadamia
//
//  Created by zm on 11.12.24.
//

import Foundation
import CashuSwift

extension AppSchemaV1.Mint {
    
    func getQuote(for quoteRequest:CashuSwift.QuoteRequest) async throws -> (quote:CashuSwift.Quote,
                                                                             event:Event) {
        
        let event: Event
        
        guard let wallet = self.wallet else {
            throw macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")
        }
        
        let quote = try await CashuSwift.getQuote(mint: self, quoteRequest: quoteRequest)
        
        switch quote {
        case let quote as CashuSwift.Bolt11.MintQuote:
            
            event = Event.pendingMintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                           shortDescription: "Mint Quote",
                                           wallet: wallet,
                                           quote: quote,
                                           amount: quote.requestDetail?.amount ?? 0,
                                           expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry)),
                                           mint: self)
            
        case let quote as CashuSwift.Bolt11.MeltQuote:
            
            event = Event.pendingMeltEvent(unit: .sat,
                                           shortDescription: "Melt Quote",
                                           wallet: wallet,
                                           quote: quote,
                                           amount: (quote.amount),
                                           expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry)),
                                           mints: [self],
                                           proofs: [])
            
        default:
            throw CashuError.typeMismatch("quote is not of any known type.")
        }
        
        logger.info("Successfully requested mint quote from mint.")
        
        return (quote, event)
    }
    
    func getQuote(for quoteRequest: CashuSwift.QuoteRequest,
                  completion: @escaping (Result<(quote: CashuSwift.Quote,
                                                 event: Event), Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = self.sendable
        
        Task {
            do {
                let quote = try await CashuSwift.getQuote(mint: sendableMint, quoteRequest: quoteRequest)
                
                DispatchQueue.main.async {
                    let event: Event
                    switch quote {
                    case let quote as CashuSwift.Bolt11.MintQuote:
                        
                        event = Event.pendingMintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                                       shortDescription: "Mint Quote",
                                                       wallet: wallet,
                                                       quote: quote,
                                                       amount: quote.requestDetail?.amount ?? 0,
                                                       expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry)),
                                                       mint: self)
                        completion(.success((quote, event)))
                        
                    case let quote as CashuSwift.Bolt11.MeltQuote:
                        
                        event = Event.pendingMeltEvent(unit: .sat,
                                                       shortDescription: "Melt Quote",
                                                       wallet: wallet,
                                                       quote: quote,
                                                       amount: (quote.amount),
                                                       expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry)),
                                                       mints: [self],
                                                       proofs: [])
                        completion(.success((quote, event)))
                        
                    default:
                        completion(.failure(CashuError.typeMismatch("quote is not of any known type.")))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
