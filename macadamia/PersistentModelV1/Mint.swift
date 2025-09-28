import Foundation
import CashuSwift
import SwiftData
import OSLog

fileprivate let mintLogger = Logger(subsystem: "macadamia", category: "Mint")

extension AppSchemaV1.Mint {
    
    func select(allProofs:[Proof]? = nil, amount:Int, unit:Unit) -> (selected:[Proof], fee:Int)? {
        
        let proofs = allProofs ?? (self.proofs ?? [])
        
        let validProofsOfUnit = proofs.filter({ $0.unit == unit && $0.state == .valid && $0.mint == self})
        
        guard !validProofsOfUnit.isEmpty else {
            return nil
        }
        
        if validProofsOfUnit.allSatisfy({ $0.inputFeePPK == 0 }) {
            if let selection = Mint.selectWithoutFee(amount: amount, of: validProofsOfUnit) {
                return (selection, 0)
            } else {
                return nil
            }
        } else {
            return Mint.selectIncludingFee(amount: amount, of: validProofsOfUnit)
        }
    }
    
    private static func selectWithoutFee(amount: Int, of proofs:[Proof]) -> [Proof]? {
        
        guard amount >= 0 else {
            mintLogger.error("input selection amount can not be negative")
            return nil
        }
        
        let totalAmount = proofs.reduce(0) { $0 + $1.amount }
        if totalAmount < amount {
            return nil
        }
        
        // dp[s] will store a subset of proofs that sum up to s
        var dp = Array<[Proof]?>(repeating: nil, count: totalAmount + 1)
        dp[0] = []
        
        for proof in proofs {
            let amount = proof.amount
            if amount > totalAmount {
                continue
            }
            for s in stride(from: totalAmount, through: amount, by: -1) {
                if let previousSubset = dp[s - amount], dp[s] == nil {
                    dp[s] = previousSubset + [proof]
                }
            }
        }
        
        // Find the minimal total amount that is at least the target amount
        for s in amount...totalAmount {
            if let subset = dp[s] {
                return subset
            }
        }
        
        return nil
    }
    
    private static func selectIncludingFee(amount: Int, of proofs:[Proof]) -> (selected:[Proof], fee:Int)? {
        
        // TODO: BRUTE FORCE CHECK FOR POSSIBLE
        
        guard amount >= 0 else {
            mintLogger.error("input selection amount can not be negative")
            return nil
        }
        
        func fee(_ proofs:[Proof]) -> Int {
            ((proofs.reduce(0) { $0 + $1.inputFeePPK } + 999) / 1000)
        }
        
        guard var proofsSelected = selectWithoutFee(amount: amount, of: proofs) else {
            return nil
        }
                    
        var proofsRest:[Proof] = proofs.filter({ !proofsSelected.contains($0) })
        
        proofsRest.sort(by: { $0.amount < $1.amount })
        
        while proofsSelected.sum < amount + fee(proofsSelected) {
            if proofsRest.isEmpty {
                // TODO: LOG INSUFFICIENT FUNDS
                return nil
            } else {
                proofsSelected.append(proofsRest.removeFirst())
            }
        }
        
        return (proofsSelected, fee(proofsSelected))
    }
    
    func increaseDerivationCounterForKeysetWithID(_ keysetID:String, by n:Int) {
        if let index = self.keysets.firstIndex(where: { $0.keysetID == keysetID }) {
            var keyset = self.keysets[index]
            keyset.derivationCounter += n
            self.keysets[index] = keyset
        }
    }
    
    func setDerivationCounterForKeysetWithID(_ keysetID:String, to value:Int) {
        if let index = self.keysets.firstIndex(where: { $0.keysetID == keysetID }) {
            var updatedKeysets = self.keysets
            updatedKeysets[index].derivationCounter = value
            self.keysets = updatedKeysets
        }
    }
    
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
    
    @MainActor
    func addProofs(_ proofs: [CashuSwift.Proof],
                   to context: ModelContext,
                   state: Proof.State = .valid,
                   increaseDerivationCounter: Bool = true) throws -> [Proof]  {
        
        // check for duplicates within passed array
        let uniqueCs = Set(proofs.map(\.C))
        guard proofs.count == uniqueCs.count else {
            throw macadamiaError.databaseError("This operation contained duplicate ecash proofs.")
        }
        
        guard let wallet = self.wallet else {
            throw macadamiaError.databaseError("No wallet associated with mint when trying to save \(proofs.count)")
        }
        
        let Cs = self.proofs?.map(\.C) ?? []
        
        let internalRepresentation:[Proof] = try proofs.compactMap { p in
            if Cs.contains(p.C) {
                mintLogger.warning("tried to add proof with duplicate C \(p.C) to the database for mint \(self.url). will be skipped.")
                return nil
            }
            
            guard let keyset = self.keysets.first(where: { $0.keysetID == p.keysetID }) else {
                throw macadamiaError.databaseError("Keyset \(p.keysetID.prefix(16)) of proof could not be found on mint \(self.url.absoluteString).")
            }
            
            return Proof(p,
                         unit: AppSchemaV1.Unit(keyset.unit) ?? .sat,
                         inputFeePPK: keyset.inputFeePPK,
                         state: state,
                         mint: self,
                         wallet: wallet)
        }
        
        if increaseDerivationCounter {
            let ids = Set(proofs.map(\.keysetID))
            for id in ids {
                let count = proofs.filter({ $0.keysetID == id }).count
                self.increaseDerivationCounterForKeysetWithID(id, by: count)
            }
        }
        
        internalRepresentation.forEach({ context.insert($0) })
        print("added \(internalRepresentation.count) proofs to db")
        return internalRepresentation
    }
}
