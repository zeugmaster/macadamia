//
//  inputSelection.swift
//  macadamia
//
//  Created by zm on 13.12.24.
//

import Foundation

func select_v2(allProofs: [Proof], amount: Int, unit: Unit) -> (selected: [Proof], fee: Int)? {
    let validProofs = allProofs.filter { $0.unit == unit && $0.state == .valid && $0.mint == self }
    guard !validProofs.isEmpty else { return nil }
    func dpSelectWithoutFee(amount: Int, proofs: [Proof]) -> [Proof]? {
        var dp: [Int: [Proof]] = [0: []]
        for proof in proofs {
            let coin = proof.amount
            for (s, subset) in dp.sorted(by: { $0.key > $1.key }) {
                let newSum = s + coin
                if dp[newSum] == nil {
                    dp[newSum] = subset + [proof]
                }
            }
        }
        let candidates = dp.keys.filter { $0 >= amount }
        guard let best = candidates.min() else { return nil }
        return dp[best]
    }
    func fee(for proofs: [Proof]) -> Int {
        ((proofs.reduce(0) { $0 + $1.inputFeePPK } + 999) / 1000)
    }
    if validProofs.allSatisfy({ $0.inputFeePPK == 0 }) {
        if let selection = dpSelectWithoutFee(amount: amount, proofs: validProofs) {
            return (selection, 0)
        }
        return nil
    } else {
        guard var selected = dpSelectWithoutFee(amount: amount, proofs: validProofs) else { return nil }
        var remaining = validProofs.filter { !selected.contains($0) }
        remaining.sort { $0.amount < $1.amount }
        while selected.reduce(0, { $0 + $1.amount }) < amount + fee(for: selected) {
            guard !remaining.isEmpty else { return nil }
            selected.append(remaining.removeFirst())
        }
        return (selected, fee(for: selected))
    }
}
