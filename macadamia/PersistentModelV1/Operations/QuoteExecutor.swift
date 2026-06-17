//
//  QuoteExecutor.swift
//  macadamia
//
//  Method-dispatch layer over CashuSwift's per-namespace (Bolt11 / Bolt12 /
//  Generic) quote operations. The rest of the app drives mint and melt through
//  these existential-typed entry points and never names a concrete payment
//  method; this file is the single place that switches on the concrete quote
//  type and absorbs the per-method execution differences:
//
//   - BOLT12 mint quotes carry no `state` field — "paid" is derived from the
//     paid/issued delta (`mintableAmount`) instead.
//   - BOLT12 and Generic `mint` require the amount to be passed explicitly,
//     whereas BOLT11 derives it from the quote.
//   - Generic state lookups need the `method` threaded through.
//   - `paymentPreimage` lives on the concrete melt quotes, not on the
//     `MeltQuoteResponse` protocol, so it is read here polymorphically.
//

import Foundation
import CashuSwift

enum QuoteExecutor {

    /// Outcome of a melt / melt-state call, with the quote widened to the
    /// payment-method-agnostic protocol type and `change` unwrapped to a
    /// (possibly empty) proof array.
    struct MeltOutcome {
        let quote: any CashuSwift.MeltQuoteResponse
        let change: [CashuSwift.Proof]
    }

    // MARK: - Mint

    /// Requests a mint quote, dispatching on the concrete request type.
    static func requestMintQuote(_ request: any CashuSwift.MintQuoteRequest,
                                 from mint: CashuSwift.Mint) async throws -> any CashuSwift.MintQuoteResponse {
        switch request {
        case let r as CashuSwift.Bolt11.MintQuoteRequest:
            return try await CashuSwift.Bolt11.requestMintQuote(r, from: mint)
        case let r as CashuSwift.Bolt12.MintQuoteRequest:
            return try await CashuSwift.Bolt12.requestMintQuote(r, from: mint)
        case let r as CashuSwift.Generic.MintQuoteRequest:
            return try await CashuSwift.Generic.requestMintQuote(r, from: mint)
        default:
            throw macadamiaError.unsupportedPaymentMethod(request.method.rawValue)
        }
    }

    /// Re-fetches the current state of a mint quote.
    static func refreshMintQuote(_ quote: any CashuSwift.MintQuoteResponse,
                                 from mint: CashuSwift.Mint) async throws -> any CashuSwift.MintQuoteResponse {
        switch quote {
        case is CashuSwift.Bolt11.MintQuote:
            return try await CashuSwift.Bolt11.mintQuoteState(quote.quote, from: mint)
        case is CashuSwift.Bolt12.MintQuote:
            return try await CashuSwift.Bolt12.mintQuoteState(quote.quote, from: mint)
        default:
            return try await CashuSwift.Generic.mintQuoteState(quote.quote, method: quote.method, from: mint)
        }
    }

    /// Method-aware "has the user paid?" predicate. BOLT11 and Generic expose a
    /// `state`; BOLT12 mint quotes never carry one, so we consult the
    /// paid/issued delta instead.
    static func mintQuoteIsPaid(_ quote: any CashuSwift.MintQuoteResponse) -> Bool {
        if let bolt12 = quote as? CashuSwift.Bolt12.MintQuote {
            return bolt12.mintableAmount > 0
        }
        return quote.state == .paid
    }

    /// Issues ecash against a paid mint quote. BOLT11 derives the amount from
    /// the quote; BOLT12 and Generic require it explicitly.
    static func mint(_ quote: any CashuSwift.MintQuoteResponse,
                     amount: Int,
                     from mint: CashuSwift.Mint,
                     seed: String?) async throws -> CashuSwift.IssueResult {
        switch quote {
        case let q as CashuSwift.Bolt11.MintQuote:
            return try await CashuSwift.Bolt11.mint(quote: q, from: mint, seed: seed)
        case let q as CashuSwift.Bolt12.MintQuote:
            return try await CashuSwift.Bolt12.mint(quote: q, from: mint, amount: amount, seed: seed)
        case let q as CashuSwift.Generic.MintQuote:
            return try await CashuSwift.Generic.mint(quote: q, from: mint, amount: amount, seed: seed)
        default:
            throw macadamiaError.unsupportedPaymentMethod(quote.method.rawValue)
        }
    }

    // MARK: - Melt

    /// Melts proofs to fulfill a melt quote.
    static func melt(_ quote: any CashuSwift.MeltQuoteResponse,
                     from mint: CashuSwift.Mint,
                     proofs: [CashuSwift.Proof],
                     blankOutputs: (outputs: [CashuSwift.Output],
                                    blindingFactors: [String],
                                    secrets: [String])?) async throws -> MeltOutcome {
        switch quote {
        case let q as CashuSwift.Bolt11.MeltQuote:
            let r = try await CashuSwift.Bolt11.melt(quote: q, from: mint, proofs: proofs, blankOutputs: blankOutputs)
            return MeltOutcome(quote: r.quote, change: r.change ?? [])
        case let q as CashuSwift.Bolt12.MeltQuote:
            let r = try await CashuSwift.Bolt12.melt(quote: q, from: mint, proofs: proofs, blankOutputs: blankOutputs)
            return MeltOutcome(quote: r.quote, change: r.change ?? [])
        case let q as CashuSwift.Generic.MeltQuote:
            let r = try await CashuSwift.Generic.melt(quote: q, from: mint, proofs: proofs, blankOutputs: blankOutputs)
            return MeltOutcome(quote: r.quote, change: r.change ?? [])
        default:
            throw macadamiaError.unsupportedPaymentMethod(quote.method.rawValue)
        }
    }

    /// Re-checks an existing melt quote's state and unblinds any change.
    static func meltState(_ quote: any CashuSwift.MeltQuoteResponse,
                          from mint: CashuSwift.Mint,
                          blankOutputs: (outputs: [CashuSwift.Output],
                                         blindingFactors: [String],
                                         secrets: [String])?) async throws -> MeltOutcome {
        switch quote {
        case is CashuSwift.Bolt11.MeltQuote:
            let r = try await CashuSwift.Bolt11.meltState(quote.quote, from: mint, blankOutputs: blankOutputs)
            return MeltOutcome(quote: r.quote, change: r.change ?? [])
        case is CashuSwift.Bolt12.MeltQuote:
            let r = try await CashuSwift.Bolt12.meltState(quote.quote, from: mint, blankOutputs: blankOutputs)
            return MeltOutcome(quote: r.quote, change: r.change ?? [])
        default:
            let r = try await CashuSwift.Generic.meltState(quote.quote, method: quote.method, from: mint, blankOutputs: blankOutputs)
            return MeltOutcome(quote: r.quote, change: r.change ?? [])
        }
    }

    /// Lightning payment preimage, which lives on the concrete melt quote types
    /// rather than the `MeltQuoteResponse` protocol.
    static func paymentPreimage(of quote: any CashuSwift.MeltQuoteResponse) -> String? {
        switch quote {
        case let q as CashuSwift.Bolt11.MeltQuote: return q.paymentPreimage
        case let q as CashuSwift.Bolt12.MeltQuote: return q.paymentPreimage
        case let q as CashuSwift.Generic.MeltQuote: return q.paymentPreimage
        default: return nil
        }
    }
}
