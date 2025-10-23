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
              bolt11MintQuote: quote,
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
              bolt11MintQuote: quote,
              amount: amount,
              mints: [mint]
        )
    }
    
    static func sendEvent(unit: Unit,
                          shortDescription: String,
                          visible: Bool = true,
                          wallet: Wallet,
                          amount: Int,
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
              unit: .other,
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
        Event(date: Date(),
              unit: unit,
              shortDescription: "Pending Transfer",
              visible: true,
              kind: .pendingTransfer,
              wallet: wallet,
              bolt11MintQuote: mintQuote,
              bolt11MeltQuote: meltQuote,
              amount: amount,
              expiration: nil,
              longDescription: nil,
              proofs: proofs,
              memo: nil,
              mints: [from, to],
              preImage: nil,
              redeemed: nil,
              groupingID: groupingID)
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
        Event(date: Date(),
              unit: unit, shortDescription: "Transfer",
              visible: true,
              kind: .transfer,
              wallet: wallet,
              bolt11MintQuote: mintQuote,
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
    }
}
