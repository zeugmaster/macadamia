//
//  AppShortcuts.swift
//  macadamia
//
//  Created by zm on 26.12.24.
//

import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContactlessPaymentIntent(),
            phrases: [
                "Pay with \(.applicationName)",
                "Contactless payment with \(.applicationName)",
                "NFC payment with \(.applicationName)",
                "Tap to pay with \(.applicationName)"
            ],
            shortTitle: "Contactless Pay",
            systemImageName: "wave.3.right"
        )
    }
}


