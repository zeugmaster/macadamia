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
    
    private static let conversionUnitKey = "PreferredCurrencyConversionUnit"
    private static let lastRNackHashKey = "LastReleaseNotesAcknoledgedHash"
    private static let firstLaunchFlag = "HasLaunchedBefore"
    
    struct ExchangeRateResponse: Decodable {
        let bitcoin: ExchangeRate
    }
    
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
    
    struct ExchangeRate: Decodable, Equatable {
        let rates: [String: Double]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rates = try container.decode([String: Double].self)
        }
        
        // Regular initializer for mocking/testing
        init(rates: [String: Double]) {
            self.rates = rates
        }
        
        func rate(for unit: Currency.Unit) -> Double? {
            return rates[unit.currencyCode.lowercased()]
        }
    }
    
    @Published var preferredConversionUnit: Currency.Unit {
        didSet {
            UserDefaults.standard.setValue(preferredConversionUnit.currencyCode, forKey: AppState.conversionUnitKey)
        }
    }

    @Published var concealAmounts: Bool {
        didSet {
            AmountConcealment.userDefaults.set(concealAmounts,
                                               forKey: AmountConcealment.userDefaultsKey)
        }
    }

    init() {
        let candidate: Currency.Unit? = UserDefaults.standard
            .string(forKey: AppState.conversionUnitKey)
            .map { Currency.Unit(code: $0) }
        if let candidate, candidate.kind == .fiat || candidate.kind == .none {
            preferredConversionUnit = candidate
        } else {
            preferredConversionUnit = .usd
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
            self.exchangeRates = ExchangeRate(rates: [
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
    
    @Published var exchangeRates: ExchangeRate?

    func toggleConcealAmounts() {
        concealAmounts.toggle()
    }
    
    func loadExchangeRates() {
        logger.info("loading exchange rates...")
        
        let currencies = Currency.Unit.fiatCases.map { $0.currencyCode.lowercased() }.joined(separator: ",")
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=\(currencies)") else {
            logger.warning("could not fetch exchange rates from API due to an invalid URL.")
            return
        }
        
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                logger.warning("unable to load conversion data.")
                return
            }
            
            guard let prices = try? JSONDecoder().decode(ExchangeRateResponse.self, from: data).bitcoin else {
                logger.warning("unable to decode exchange rate data from request response.")
                return
            }
            
            await MainActor.run {
                self.exchangeRates = prices
            }
        }
    }
}
