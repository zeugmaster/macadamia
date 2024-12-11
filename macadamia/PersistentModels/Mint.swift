import Foundation
import CashuSwift

extension AppSchemaV1.Mint {
    
    func select(allProofs:[Proof], amount:Int, unit:Unit) -> (selected:[Proof], fee:Int)? {
        
        let validProofsOfUnit = allProofs.filter({ $0.unit == unit && $0.state == .valid && $0.mint == self})
        
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
            logger.error("input selection amount can not be negative")
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
            logger.error("input selection amount can not be negative")
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
    
}
