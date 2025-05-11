//
//  RedeemContainerView.swift
//  macadamia
//
//  Created by zm on 07.05.25.
//

import SwiftUI
import CashuSwift

struct RedeemContainerView: View {
    
    @State private var inputString: String?
    @State private var token: CashuSwift.Token?
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    init(tokenString: String? = nil) {
        self._inputString = State(initialValue: tokenString)
        self._token = State(initialValue: try? tokenString?.deserializeToken())
    }
    
    var body: some View {
        if let token, let inputString {
            RedeemView(tokenString: inputString, token: token)
        } else {
            List {
                InputView { result in
                    parse(input: result)
                }
            }
        }
    }
    
    @MainActor
    private func parse(input: String) {
        var string = input
        
        guard !string.isEmpty else {
            logger.error("pasted string was empty.")
            displayAlert(alert: AlertDetail(title: "Empty String 🕳️", description: "Looks like you tried to enter an empty string."))
            return
        }
        
        if string.hasPrefix("cashu:") {
            string.removeFirst("cashu:".count)
        }
        
        if string.hasPrefix("CASHU:") {
            string.removeFirst("CASHU:".count)
        }
        
        guard !string.hasPrefix("creq") else {
            displayAlert(alert: AlertDetail(title: "Cashu Payment Request 🫴", description: "macadamia does not yet support payment requests, but will soon™."))
            return
        }
        
        do {
            let t = try string.deserializeToken()
            
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
