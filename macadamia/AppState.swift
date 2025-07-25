//
//  Settings.swift
//  macadamia
//
//  Created by zm on 01.12.24.
//

import Foundation

@MainActor
class AppState: ObservableObject {
    
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
    
    static var showOnboarding: Bool {
        get {
            return !UserDefaults.standard.bool(forKey: firstLaunchFlag)
        } set {
            UserDefaults.standard.set(!newValue, forKey: firstLaunchFlag)
        }
    }
    
    struct ExchangeRate: Decodable, Equatable {
        let usd: Int
        let eur: Int
    }
    
    @Published var preferredConversionUnit: Unit {
        didSet {
            UserDefaults.standard.setValue(preferredConversionUnit.rawValue, forKey: AppState.conversionUnitKey)
        }
    }
    
    init() {
        if let unit = Unit(UserDefaults.standard.string(forKey: AppState.conversionUnitKey)) {
            preferredConversionUnit = unit
        } else {
            preferredConversionUnit = .usd
        }
        
        loadExchangeRates()
    }
    
    @Published var exchangeRates: ExchangeRate?
    
    func loadExchangeRates() {
        logger.info("loading exchange rates...")
        
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd,eur") else {
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
