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
              minta: [mint]
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
              minta: [mint]
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
                          token: CashuSwift.Token,
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
              token: token,
              minta: [mint],
              redeemed: redeemed
        )
    }
    
    static func receiveEvent(unit: Unit,
                             shortDescription: String,
                             visible: Bool = true,
                             wallet: Wallet,
                             amount: Int,
                             longDescription: String,
                             proofs: [Proof],
                             memo: String,
                             mint: Mint,
                             token: CashuSwift.Token,
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
              token: token,
              minta: [mint],
              redeemed: redeemed
        )
    }
    
    static func pendingMeltEvent(unit: Unit,
                                 shortDescription: String,
                                 visible: Bool = true,
                                 wallet: Wallet,
                                 quote: CashuSwift.Bolt11.MeltQuote,
                                 amount: Int,
                                 expiration: Date,
                                 mints: [Mint]) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .pendingMelt,
              wallet: wallet,
              bolt11MeltQuote: quote,
              amount: amount,
              expiration: expiration,
              minta: mints
        )
    }
    
    static func meltEvent(unit: Unit,
                          shortDescription: String,
                          visible: Bool = true,
                          wallet: Wallet,
                          amount: Int,
                          longDescription: String,
                          mints:[Mint]) -> Event {
        Event(date: Date(),
              unit: unit,
              shortDescription: shortDescription,
              visible: visible,
              kind: .melt,
              wallet: wallet,
              amount: amount,
              longDescription: longDescription,
              minta: mints
        )
    }
    
    // TODO: REMOVE DRAIN FEATURE AND ASSOCIATED FUNCTIONS
    static func drainEvent(shortDescription: String,
                           visible:Bool = true,
                           wallet: Wallet,
                           tokens: [TokenInfo]) -> Event {
        Event(date: Date(),
              unit: .other,
              shortDescription: shortDescription,
              visible: visible,
              kind: .drain,
              wallet: wallet,
              tokens: tokens)
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
}
