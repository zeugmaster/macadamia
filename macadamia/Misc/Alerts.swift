//
//  Alerts.swift
//  macadamia
//
//  Created by zm on 12.11.24.
//

import Foundation
import SwiftUI
import CashuSwift

struct AlertDetail {
    let title: String
    let alertDescription: String?
    let primaryButtonText: String?
    let affirmText: String?
    let onAffirm: (() -> Void)?

    init(title: String,
         description: String? = nil,
         primaryButtonText: String? = nil,
         affirmText: String? = nil,
         onAffirm: (() -> Void)? = nil)
    {
        self.title = title
        alertDescription = description
        self.primaryButtonText = primaryButtonText
        self.affirmText = affirmText
        self.onAffirm = onAffirm
    }
    
    // TODO: expand error handling to all cases and communicate common cases more effectively
    
    init(_ error: Swift.Error) {
        switch error {
        case let cashuError as CashuError:
            switch cashuError {
            case .networkError:
                self = AlertDetail(title: "Network error 📡", description: "The mint could not be reached due to a network issue. Are you both online?")
                
            case .quoteNotPaid:
                self = AlertDetail(title: "Quote Not Paid 🚫💰",
                                   description: "The quote has not been paid. Try again after paying the displayed quote to the mint.")
                
            case .blindedMessageAlreadySigned:
                self = AlertDetail(title: "Blinded Message Already Signed",
                                   description: "This blinded message has already been signed, indicating an issue during deterministic secret generation.")
                
            case .alreadySpent:
                self = AlertDetail(title: "Already Spent 💸", description: "The ecash has already been spent with the mint.")
                
            case .transactionUnbalanced:
                self = AlertDetail(title: "Transaction Unbalanced", description: "The transaction is unbalanced.")
                
            // Add cases for other errors here...
            case .inputError(let message):
                self = AlertDetail(title: "Input Error", description: message)
                
            case .insufficientInputs(_): // associated typa for detail string TODO: utilize
                self = AlertDetail(title: "Insufficient Funds", description: "The wallet was unable to collect enough ecash for this transaction.")
                
            case .unknownError(let message):
                self = AlertDetail(title: "Unknown Error", description: message)
                
            default:
                self = AlertDetail(title: "Unhandled Error", description: "An unhandled Cashu error occurred.")
            }
        default:
            self = AlertDetail(title: "General Error", description: error.localizedDescription)
        }
    }
}


struct AlertViewModifier: ViewModifier {
    @Binding var isPresented: Bool
    var currentAlert: AlertDetail?

    func body(content: Content) -> some View {
        content
            .alert(currentAlert?.title ?? "Error", isPresented: $isPresented) {
                Button(role: .cancel) {
                    // This button could potentially reset or handle cancel logic
                } label: {
                    Text(currentAlert?.primaryButtonText ?? "OK")
                }
                if let affirmText = currentAlert?.affirmText, let onAffirm = currentAlert?.onAffirm {
                    Button(role: .destructive) {
                        onAffirm()
                    } label: {
                        Text(affirmText)
                    }
                }
            } message: {
                Text(currentAlert?.alertDescription ?? "")
            }
    }
}

extension View {
    func alertView(isPresented: Binding<Bool>, currentAlert: AlertDetail?) -> some View {
        modifier(AlertViewModifier(isPresented: isPresented, currentAlert: currentAlert))
    }
}
