//
//  ContactlessPaymentIntent.swift
//  macadamia
//
//  Created by zm on 26.12.24.
//

import AppIntents

struct ContactlessPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Contactless Payment"
    static var description = IntentDescription("Open the NFC contactless payment screen to pay a terminal")
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.pendingDeepLink = .contactless
        return .result()
    }
}

