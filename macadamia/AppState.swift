//
//  Settings.swift
//  macadamia
//
//  Created by zm on 01.12.24.
//

import Foundation

enum DeepLink: Equatable {
    case contactless
}

@MainActor
class AppState: ObservableObject {
    
    static let shared = AppState()
    
    @Published var pendingDeepLink: DeepLink?
    
    private static let lastRNackHashKey = "LastReleaseNotesAcknoledgedHash"
    private static let firstLaunchFlag = "HasLaunchedBefore"
    
    static func showReleaseNotes() -> Bool {
        let releaseNotesSeenHash = UserDefaults.standard.string(forKey: AppState.lastRNackHashKey)
        if releaseNotesSeenHash ?? "not set" != ReleaseNote.hashString() {
            UserDefaults.standard.setValue(ReleaseNote.hashString(),
                                           forKey: AppState.lastRNackHashKey)
            logger.info("Release notes have changed and will be shown.")
            return true
        } else {
            return false
        }
    }
    
    @Published var preferredConversionUnit: Currency.Unit {
        didSet {
            Currency.Unit.savePreferred(preferredConversionUnit)
        }
    }

    @Published var concealAmounts: Bool {
        didSet {
            AmountConcealment.userDefaults.set(concealAmounts,
                                               forKey: AmountConcealment.userDefaultsKey)
        }
    }

    init() {
        Currency.Unit.migratePreferredFromStandardDefaultsIfNeeded()

        let candidate = Currency.Unit.preferred
        if candidate.kind == .fiat || candidate.kind == .none {
            preferredConversionUnit = candidate
        } else {
            preferredConversionUnit = .usd
            Currency.Unit.savePreferred(.usd)
        }

        concealAmounts = AmountConcealment.userDefaults.bool(forKey: AmountConcealment.userDefaultsKey)

        loadExchangeRates()
    }
    
    // Preview/Mock initializer - skips network calls and UserDefaults
    init(preview: Bool, preferredUnit: Currency.Unit = .none, concealAmounts: Bool = false) {
        self.preferredConversionUnit = preferredUnit
        self.concealAmounts = concealAmounts
        
        // Provide mock exchange rates for previews
        if preferredUnit != .none {
            self.exchangeRates = Currency.ExchangeRate(rates: [
                "usd": 95000.0,
                "eur": 87000.0,
                "gbp": 75000.0,
                "jpy": 13500000.0,
                "cny": 680000.0,
                "chf": 85000.0
            ])
        }
        
        // Don't call loadExchangeRates() for previews
    }
    
    @Published var exchangeRates: Currency.ExchangeRate?

    func toggleConcealAmounts() {
        concealAmounts.toggle()
    }
    
    func loadExchangeRates() {
        logger.info("loading exchange rates...")

        Task {
            guard let prices = await Currency.fetchBitcoinExchangeRates() else {
                logger.warning("unable to load conversion data.")
                return
            }

            await MainActor.run {
                self.exchangeRates = prices
            }
        }
    }
}
