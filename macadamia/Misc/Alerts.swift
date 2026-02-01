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
    let primaryButton: AlertButton?
    let secondaryButton: AlertButton?
    let tertiaryButton: AlertButton?
    
    init(title: String,
         description: String? = nil,
         primaryButton: AlertButton? = nil,
         secondaryButton: AlertButton? = nil,
         tertiaryButton: AlertButton? = nil) {
        self.title = title
        self.alertDescription = description
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        self.tertiaryButton = tertiaryButton
    }
    
    init(with error: Swift.Error) {
        switch error {
        case let cashuError as CashuError:
            switch cashuError {
            case .networkError:
                self = AlertDetail(title: String(localized: "Network error 📡"), description: String(localized: "The mint could not be reached due to a network issue. Are you both online?"))
                
            case .quoteNotPaid:
                self = AlertDetail(title: String(localized: "Quote Not Paid 🚫💰"),
                                   description: String(localized: "The quote has not been paid. Try again after paying the displayed quote to the mint."))
                
            case .blindedMessageAlreadySigned:
                self = AlertDetail(title: String(localized: "Blinded Message Already Signed"),
                                   description: String(localized: "This blinded message has already been signed, indicating an issue during deterministic secret generation."))
                
            case .alreadySpent:
                self = AlertDetail(title: String(localized: "Already Spent 💸"), description: String(localized: "The ecash has already been spent with the mint."))
                
            case .transactionUnbalanced:
                self = AlertDetail(title: String(localized: "Transaction Unbalanced"), description: String(localized: "The transaction is unbalanced."))
                
            // Add cases for other errors here...
            case .inputError(let message):
                self = AlertDetail(title: String(localized: "Input Error"), description: message)
                
            case .insufficientInputs(_): // associated typa for detail string TODO: utilize
                self = AlertDetail(title: String(localized: "Insufficient Funds 💰"), description: String(localized: "The wallet was unable to collect enough ecash for this transaction."))
                
            case .unknownError(let message):
                self = AlertDetail(title: String(localized: "Unknown Error"), description: message)
                
            default:
                self = AlertDetail(title: String(localized: "Unhandled Error"), description: String(describing: cashuError))
            }
        case let macadamiaError as macadamiaError:
            switch macadamiaError {
            case .multiMintToken:
                self = AlertDetail(title: String(localized: "Multi Mint Token 📑"), description: String(localized: "macadamia no longer supports tokens that contain ecash from multiple mints. Please use separate tokens and the seed phrase for restoring ecash."))
            case .databaseError(let message):
                self = AlertDetail(title: String(localized: "Database Error 📂"), description: String(localized: "The operation could not be completed due to an unexpected database inconsistency. \(message)"))
            case .lockedToken:
                self = AlertDetail(title: String(localized: "Locked Token 🔒"), description: String(localized: "macadamia can not yet redeem locked tokens. This feature is coming soon™."))
            case .unsupportedUnit:
                self = AlertDetail(title: String(localized: "Unit Error 💵"), description: String(localized: "macadamia can only redeem tokens denominated in Satoshis. Multi unit support is coming soon™."))
            case .unknownMint(_):
                self = AlertDetail(title: String(localized: "Unknown Mint 🥷"), description: String(localized: "You are trying to redeem from a mint that is not known to the wallet. Please add it first."))
            case .unknownKeyset(let string):
                self = AlertDetail(title: String(localized: "Keyset Error"), description: String(localized: "Detail: \(string)"))
            case .mintVerificationError(let detail):
                self = AlertDetail(title: String(localized: "Mint Verification Error"), description: String(localized: "This mint did not pass verification before being added. Detail: \(detail ?? "None")"))
            }
        default:
            self = AlertDetail(title: String(localized: "Unknown Error"), description: error.localizedDescription)
        }
    }
}

struct AlertViewModifier: ViewModifier {
    @Binding var isPresented: Bool
    var currentAlert: AlertDetail? // optional because SwiftUI view modifier requires it

    func body(content: Content) -> some View {
        content
            .alert(currentAlert?.title ?? "Error", isPresented: $isPresented) {
                if let primaryButton = currentAlert?.primaryButton {
                    Button(role: primaryButton.role) {
                        primaryButton.action()
                    } label: {
                        Text(primaryButton.title)
                    }
                } 
                if let secondaryButton = currentAlert?.secondaryButton {
                    Button(role: secondaryButton.role) {
                        secondaryButton.action()
                    } label: {
                        Text(secondaryButton.title)
                    }
                }
                if let tertiaryButton = currentAlert?.tertiaryButton {
                    Button(role: tertiaryButton.role) {
                        tertiaryButton.action()
                    } label: {
                        Text(tertiaryButton.title)
                    }
                }
            } message: {
                Text(currentAlert?.alertDescription ?? "")
            }
    }
}

struct AlertButton {
    var title: String
    var role: ButtonRole?
    var action: (() -> Void)
}

extension View {
    func alertView(isPresented: Binding<Bool>, currentAlert: AlertDetail?) -> some View {
        modifier(AlertViewModifier(isPresented: isPresented, currentAlert: currentAlert))
    }
}
