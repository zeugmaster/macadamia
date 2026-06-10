//
//  EventFactory.swift
//  macadamia
//
//  Created by zm on 11.12.24.
//

import Foundation
import CashuSwift

extension AppSchemaV1.Event {
    static func pendingMintEvent(unit: Unit,
                                 shortDescription: String,
                                 visible: Bool = true,
                                 wallet: Wallet,
                                 quote: CashuSwift.Bolt11.MintQuote,
                                 amount: Int,
                                 expiration: Date,
                                 mint: Mint) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .pendingMint,
              wallet: wallet,
              mintQuote: quote,
              amount: amount,
              expiration: expiration,
              mints: [mint]
        )
    }
    
    static func mintEvent(unit: Unit,
                          shortDescription: String,
                          visible: Bool = true,
                          wallet: Wallet,
                          quote: CashuSwift.Bolt11.MintQuote,
                          mint: Mint,
                          amount: Int) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .mint,
              wallet: wallet,
              mintQuote: quote,
              amount: amount,
              mints: [mint]
        )
    }
    
    static func sendEvent(unit: Unit,
                          shortDescription: String,
                          visible: Bool = true,
                          wallet: Wallet,
                          amount: Int,
                          token: CashuSwift.Token,
                          longDescription: String,
                          proofs: [Proof],
                          memo: String,
                          mint: Mint,
                          redeemed: Bool = false) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .send,
              wallet: wallet,
              amount: amount,
              token: token,
              longDescription: longDescription,
              proofs: proofs,
              memo: memo,
              mints: [mint],
              redeemed: redeemed
        )
    }

    static func pendingReceiveEvent(unit: Unit,
                                    shortDescription: String,
                                    visible: Bool = true,
                                    wallet: Wallet,
                                    amount: Int,
                                    token: CashuSwift.Token,
                                    memo: String?,
                                    mint: Mint) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .pendingReceive,
              wallet: wallet,
              amount: amount,
              token: token,
              memo: memo,
              mints: [mint])
    }
    
    static func receiveEvent(unit: Unit,
                             shortDescription: String,
                             visible: Bool = true,
                             wallet: Wallet,
                             amount: Int,
                             longDescription: String,
                             proofs: [Proof],
                             memo: String?,
                             mint: Mint,
                             redeemed: Bool) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .receive,
              wallet: wallet,
              amount: amount,
              longDescription: longDescription,
              proofs: proofs,
              memo: memo,
              mints: [mint],
              redeemed: redeemed
        )
    }
    
    static func pendingMeltEvent(unit: Unit,
                                 shortDescription: String,
                                 visible: Bool = true,
                                 wallet: Wallet,
                                 quote: CashuSwift.Bolt11.MeltQuote,
                                 amount: Int,
                                 expiration: Date?,
                                 mints: [Mint],
                                 proofs: [Proof]? = nil,
                                 groupingID: UUID? = nil) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .pendingMelt,
              wallet: wallet,
              bolt11MeltQuote: quote,
              amount: amount,
              expiration: expiration,
              proofs: proofs,
              mints: mints,
              groupingID: groupingID
        )
    }
    
    static func meltEvent(unit: Unit,
                          shortDescription: String,
                          visible: Bool = true,
                          wallet: Wallet,
                          amount: Int,
                          longDescription: String,
                          mints:[Mint],
                          change: [Proof]? = nil,
                          preImage: String? = nil, // FIXME: should not be optional
                          groupingID: UUID? = nil,
                          meltQuote: CashuSwift.Bolt11.MeltQuote? = nil /* should not be optional either */) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .melt,
              wallet: wallet,
              bolt11MeltQuote: meltQuote,
              amount: amount,
              longDescription: longDescription,
              proofs: change,
              mints: mints,
              preImage: preImage,
              groupingID: groupingID
        )
    }
    
    static func restoreEvent(shortDescription: String,
                             visible: Bool = true,
                             wallet: Wallet,
                             longDescription: String) -> Event {
        Event(date: Date(),
              unit: .none,
              shortDescription: shortDescription,
              visible: visible,
              kind: .restore,
              wallet: wallet,
              longDescription: longDescription)
    }
    
    static func pendingTransferEvent(wallet: Wallet,
                                     amount: Int,
                                     unit: Unit = .sat,
                                     from: Mint,
                                     to: Mint,
                                     proofs: [Proof],
                                     meltQuote: CashuSwift.Bolt11.MeltQuote,
                                     mintQuote: CashuSwift.Bolt11.MintQuote,
                                     groupingID: UUID?) -> Event {
        let event = Event(date: Date(),
                          unit: unit,
                          shortDescription: "Pending Transfer",
                          visible: true,
                          kind: .pendingTransfer,
                          wallet: wallet,
                          mintQuote: mintQuote,
                          bolt11MeltQuote: meltQuote,
                          amount: amount,
                          // the issuance deadline: mints may refuse to issue ecash on an
                          // expired quote even when it was paid
                          expiration: mintQuote.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                          longDescription: nil,
                          proofs: proofs,
                          memo: nil,
                          mints: [from, to],
                          preImage: nil,
                          redeemed: nil,
                          groupingID: groupingID)
        event.fromMint = from
        event.toMint = to
        return event
    }
    
    static func transferEvent(wallet: Wallet,
                              amount: Int,
                              unit: Unit = .sat,
                              from: Mint,
                              to: Mint,
                              proofs: [Proof],
                              meltQuote: CashuSwift.Bolt11.MeltQuote,
                              mintQuote: CashuSwift.Bolt11.MintQuote,
                              preImage: String?,
                              groupingID: UUID?) -> Event {
        let event = Event(date: Date(),
                          unit: unit, shortDescription: "Transfer",
                          visible: true,
                          kind: .transfer,
                          wallet: wallet,
                          mintQuote: mintQuote,
                          bolt11MeltQuote: meltQuote,
                          amount: amount,
                          token: nil,
                          expiration: nil,
                          longDescription: nil,
                          proofs: proofs,
                          memo: nil,
                          mints: [from, to],
                          preImage: preImage,
                          redeemed: nil,
                          groupingID: groupingID)
        event.fromMint = from
        event.toMint = to
        return event
    }
}

extension AppSchemaV1.Event {
    /// The endpoints of a transfer event.
    ///
    /// New events carry dedicated `fromMint`/`toMint` references. Legacy rows
    /// fall back to the old positional convention (`mints[0]` = from,
    /// `mints[1]` = to) — but SwiftData does NOT reliably preserve the order of
    /// a to-many relationship array, so the proofs relationship disambiguates
    /// where possible: a pending transfer holds the melt inputs (source mint),
    /// a completed transfer holds the newly issued ecash (destination mint).
    var transferMints: (from: Mint, to: Mint)? {
        if let fromMint, let toMint {
            return (fromMint, toMint)
        }

        guard let mints, mints.count >= 2 else { return nil }
        var endpoints = (from: mints[0], to: mints[1])

        if let proofMint = proofs?.first?.mint {
            switch kind {
            case .pendingTransfer where proofMint == endpoints.to,
                 .transfer where proofMint == endpoints.from:
                endpoints = (endpoints.to, endpoints.from)
            default:
                break
            }
        }
        return endpoints
    }

    /// Deadline for issuing ecash at the destination mint. Falls back to the
    /// expiry inside the stored mint quote for events that predate `expiration`
    /// being set on pending transfers.
    var mintQuoteExpiry: Date? {
        expiration ?? mintQuote?.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
