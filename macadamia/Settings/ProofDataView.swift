//
//  ProofDataView.swift
//  macadamia
//
//  Created by zm on 18.04.25.
//

import SwiftUI

struct ProofDataView: View {
    
    var proof: Proof
    
    var body: some View {
        List {
            Section {
                Text("C: " + proof.C)
                Text("keysetID: " + proof.keysetID)
                Text("amount: " + String(proof.amount))
                Text("Secret: " + proof.secret)
            } header: {
                Text("Mandatory")
            }
            Section {
                Text("DLEQ: " + proof.dleq.debugDescription)
            } header: {
                Text("DLEQ")
            }
            Section {
                Text("inputFeePPK:" + String(proof.inputFeePPK))
            } header: {
                Text("Additional")
            }
        }
    }
}
