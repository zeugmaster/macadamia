//
//  MintSwap.swift
//  macadamia
//
//  Created by zm on 26.02.25.
//

import Foundation
import CashuSwift

extension Mint {
    func swap(to mint: Mint, proofs: [some Proof], targetAmount: Int, completion: @escaping (PaymentResult) -> Void) {
        // 1.  create mint req of target amount
        // 2.  melt to that invoice
        // 2b. create pending (melt) swap with designated proofs, mintQuote, meltQuote
        // 3.  wait for melt to complete: on error user can retry swap with designated proofs
        // 4.  on success: mint from mint b
        // 5.  save new proofs to db
    }
}
