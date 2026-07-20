//
//  QuoteOfferTools.swift
//  macadamia
//
//  Shared helpers for the NUT-XX quote-offer flows: NUT-20 quote-locking key
//  derivation, mint resolution against the local database, teller payment
//  codes and the input-routing view that dispatches a scanned `cquote...`
//  string to the mint or melt flow.
//

import Foundation
import CryptoKit
import SwiftUI
import CashuSwift

enum QuoteOfferTools {

    // MARK: - NUT-20 quote-locking key

    /// Derivation counter for the NUT-20 quote-locking key of an offer ticket.
    ///
    /// PROTOTYPE WORKAROUND: the wallet has no persistent NUT-20 counter store,
    /// so instead of a monotonically increasing counter we derive one
    /// deterministically from the ticket: the first 4 bytes of SHA256(ticket)
    /// as a big-endian UInt32, masked with 0x7FFF_FFFF to stay a valid
    /// non-hardened BIP-32 index. Because the claimed quote's `request` field
    /// echoes the ticket, the key is recoverable from seed + stored quote after
    /// an app restart.
    static func nut20Counter(forTicket ticket: String) -> UInt32 {
        let digest = SHA256.hash(data: Data(ticket.utf8))
        let bytes = Array(digest.prefix(4))
        let value = (UInt32(bytes[0]) << 24)
                  | (UInt32(bytes[1]) << 16)
                  | (UInt32(bytes[2]) << 8)
                  |  UInt32(bytes[3])
        return value & 0x7FFF_FFFF
    }

    /// The NUT-20 key pair a quote claimed from an offer with `ticket` is locked to.
    static func quoteLockingKey(seed: String, ticket: String) throws -> (privateKey: Data, publicKey: String) {
        try CashuSwift.QuoteOffers.quoteLockingKey(seed: seed,
                                                   counter: nut20Counter(forTicket: ticket))
    }

    /// Whether a stored mint quote was claimed from an offer and is NUT-20
    /// locked: only claimed quotes carry a `pubkey` in their raw response.
    static func isOfferLockedQuote(_ quote: any CashuSwift.MintQuoteResponse) -> Bool {
        guard let generic = quote as? CashuSwift.Generic.MintQuote,
              case .string = generic.raw["pubkey"] else {
            return false
        }
        return true
    }

    /// Issues ecash against a NUT-20-locked quote claimed from an offer,
    /// re-deriving the quote key from the ticket echoed in `quote.request`.
    static func mint(offerLockedQuote quote: CashuSwift.Generic.MintQuote,
                     from mint: CashuSwift.Mint,
                     seed: String) async throws -> CashuSwift.IssueResult {
        let key = try quoteLockingKey(seed: seed, ticket: quote.request)
        if case let .string(lockedPubkey) = quote.raw["pubkey"] ?? .null,
           lockedPubkey != key.publicKey {
            throw CashuError.unknownError("""
                This quote is locked to key \(lockedPubkey.prefix(12))... which this wallet \
                cannot re-derive from the offer ticket. Issuance is not possible.
                """)
        }
        // cdk <= rev 6132607 verifies the pre-revision NUT-20 message;
        // switch to .current once the mint catches up.
        return try await CashuSwift.QuoteOffers.mint(quote: quote,
                                                     from: mint,
                                                     seed: seed,
                                                     quoteKey: key.privateKey,
                                                     // Mintable remainder from the quote's raw
                                                     // progress fields (state-less cdk quotes).
                                                     amount: QuoteExecutor.mintableAmount(of: quote),
                                                     signatureFormat: .legacyConcat)
    }

    // MARK: - Mint resolution

    /// Finds the wallet's mint matching the offer's mint URL, comparing
    /// normalized (trailing-slash- and case-insensitive) URLs. Hidden mints
    /// count as a match so re-scanning an offer doesn't re-add its mint.
    static func matchMint(url: String, in mints: [Mint]) -> Mint? {
        let target = normalizedMintURL(url)
        return mints.first { normalizedMintURL($0.url.absoluteString) == target }
    }

    static func normalizedMintURL(_ string: String) -> String {
        var normalized = string.lowercased()
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    /// Whether the mint has an active keyset for the offer's unit — without
    /// one the wallet can neither issue nor spend in that unit.
    static func hasKeyset(for unit: String, on mint: Mint) -> Bool {
        mint.keysets.contains { $0.active && $0.unit.lowercased() == unit.lowercased() }
    }

    // MARK: - Teller payment code

    /// Short verification code shown to the teller for a pending offer melt:
    /// the LAST 6 CHARACTERS OF THE QUOTE ID, UPPERCASED. The operator UI
    /// derives the same code from the quote ID it sees on its terminal.
    static func paymentCode(forQuoteID id: String) -> String {
        String(id.suffix(6)).uppercased()
    }

    // MARK: - Errors

    /// Maps claim errors to user-facing alerts, special-casing the NUT-XX
    /// ticket error codes (20010 / 20011).
    static func claimAlertDetail(for error: Error) -> AlertDetail {
        switch error {
        case CashuError.offerTicketAlreadyClaimed:
            return AlertDetail(title: String(localized: "Offer Already Claimed"),
                               description: String(localized: "This offer was already claimed — ask the teller to issue a new one."))
        case CashuError.offerTicketUnknownOrExpired:
            return AlertDetail(title: String(localized: "Offer Not Recognized"),
                               description: String(localized: "The mint does not recognize this offer's ticket, or it has expired. Ask the teller to issue a new one."))
        case CashuError.quoteOfferExpired:
            return AlertDetail(title: String(localized: "Offer Expired"),
                               description: String(localized: "This offer's claim window has passed. Ask the teller to issue a new one."))
        default:
            return AlertDetail(with: error)
        }
    }
}

// MARK: - Input routing

/// Decodes a scanned or pasted `cquote...` string and routes to the melt or
/// mint offer flow. Kept as a view so it can be the direct target of a
/// `navigationDestination`.
struct QuoteOfferRouteView: View {
    private enum Route {
        case melt(CashuSwift.QuoteOffer)
        case mint(CashuSwift.QuoteOffer)
        case invalid(String)
    }

    private let route: Route

    init(encoded: String) {
        do {
            let offer = try CashuSwift.QuoteOffer(encodedOffer: encoded)
            route = offer.operation == .melt ? .melt(offer) : .mint(offer)
        } catch {
            logger.error("could not decode quote offer: \(error)")
            route = .invalid(error.localizedDescription)
        }
    }

    var body: some View {
        switch route {
        case .melt(let offer):
            MeltView(quoteOffer: offer)
        case .mint(let offer):
            QuoteOfferMintView(offer: offer)
        case .invalid(let message):
            List {
                Section {
                    Text(message)
                        .foregroundStyle(.orange)
                } header: {
                    Text("INVALID QUOTE OFFER")
                } footer: {
                    Text("The scanned code could not be decoded as a quote offer. Ask the teller to display it again.")
                }
            }
            .navigationTitle("Quote Offer")
        }
    }
}

// MARK: - Offer details

/// The offer summary both flows show BEFORE claiming, so the user can verify
/// mint, amount and description against what the teller announced.
struct QuoteOfferDetailSection: View {
    let offer: CashuSwift.QuoteOffer
    let resolvedMintName: String?

    private var mintLabel: String {
        resolvedMintName ?? URL(string: offer.mintURL)?.host() ?? offer.mintURL
    }

    var body: some View {
        Section {
            if let description = offer.offerDescription, !description.isEmpty {
                Text(description)
            }
            HStack {
                Text("Mint")
                Spacer()
                Text(mintLabel)
                    .foregroundStyle(.secondary)
            }
            if let amount = offer.amount {
                HStack {
                    Text("Amount")
                    Spacer()
                    AmountView(amount: amount, unit: Unit(code: offer.unit))
                        .monospaced()
                }
            }
            HStack {
                Text("Method")
                Spacer()
                Text(PaymentMethodKind(offer.method).displayName)
                    .foregroundStyle(.secondary)
            }
            if let expiry = offer.expiry {
                let expiryDate = Date(timeIntervalSince1970: TimeInterval(expiry))
                HStack {
                    Text(offer.isExpired() ? "Expired" : "Expires")
                    Spacer()
                    if offer.isExpired() {
                        Text(expiryDate.formatted())
                            .foregroundStyle(.red)
                    } else {
                        Text(expiryDate, style: .relative)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("QUOTE OFFER")
        }
    }
}
