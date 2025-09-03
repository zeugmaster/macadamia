//
//  RedeemContainerView.swift
//  macadamia
//
//  Created by zm on 07.05.25.
//

import SwiftUI
import CashuSwift

struct RedeemContainerView: View {
    
    private let allowSwap: Bool
    
    @State private var inputString: String?
    @State private var token: CashuSwift.Token?
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    init(tokenString: String? = nil, allowSwap: Bool = true) {
        self._inputString = State(initialValue: tokenString)
        self._token = State(initialValue: try? tokenString?.deserializeToken())
        self.allowSwap = allowSwap
    }
    
    var body: some View {
        if let token, let inputString {
            RedeemView(tokenString: inputString, token: token)
        } else {
            InputView(supportedTypes: [.token]) { result in
                parse(input: result.payload)
            }
            .padding()
        }
    }
    
    @MainActor
    private func parse(input: String) {
        
        do {
            let t = try input.deserializeToken()
            
            guard t.proofsByMint.count == 1 else {
                displayAlert(alert: AlertDetail(with: macadamiaError.multiMintToken))
                return
            }
            
            self.token = t
            self.inputString = input
            
        } catch {
            logger.error("could not decode token from string \(input) \(error)")
            displayAlert(alert: AlertDetail(with: error))
            inputString = nil
            token = nil
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
