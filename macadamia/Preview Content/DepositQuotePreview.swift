#if DEBUG
import CashuSwift
import Foundation

@MainActor
enum DepositQuotePreview {
    private static let mint: Mint = {
        let mint = Mint(url: URL(string: "https://deposit.preview.mint")!, keysets: [])
        mint.nickName = "Preview Mint"
        mint.userIndex = 0
        return mint
    }()

    static let bolt11 = DepositQuote(
        response: CashuSwift.Bolt11.MintQuote(
            quote: "preview-bolt11", request: "lnbc10u1preview", amount: 1_000,
            unit: "sat", state: .unpaid, expiry: Int(Date().addingTimeInterval(3600).timeIntervalSince1970)),
        mint: mint,
        option: .init(mintID: mint.mintID, direction: .deposit, unit: .sat, method: .bolt11),
        requestedAmount: 1_000, lockingKeyCounter: nil)

    static let bolt12 = lockedQuote(method: .bolt12, request: "lno1previewoffer", amount: nil)
    static let onchain = lockedQuote(method: "onchain",
                                    request: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", amount: nil,
                                    paid: 25_000, issued: 10_000,
                                    options: ["confirmations": .integer(3)])
    static let generic = lockedQuote(method: "branch", request: "BRANCH-PREVIEW-1000", amount: 1_000,
                                    methodName: "Branch", unit: .other("bux"))

    private static func lockedQuote(method: CashuSwift.PaymentMethodID, request: String, amount: Int?,
                                    paid: Int = 0, issued: Int = 0, methodName: String? = nil,
                                    unit: Unit = .sat, options: CashuSwift.JSONObject? = nil) -> DepositQuote {
        let quoteID = "preview-\(method.rawValue)"
        var raw: CashuSwift.JSONObject = [
            "method": .string(method.rawValue), "quote": .string(quoteID),
            "request": .string(request), "unit": .string(unit.currencyCode),
            "pubkey": .string("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
            "amount_paid": .integer(Int64(paid)), "amount_issued": .integer(Int64(issued)),
            "updated_at": .integer(1_800_000_000)
        ]
        if let amount { raw["amount"] = .integer(Int64(amount)) }
        return DepositQuote(
            response: CashuSwift.Generic.MintQuote(method: method, quote: quoteID, request: request,
                                                  unit: unit.currencyCode, amount: amount,
                                                  state: nil, expiry: nil, raw: raw),
            mint: mint,
            option: .init(mintID: mint.mintID, direction: .deposit, unit: unit, method: method,
                          methodName: methodName, minAmount: 100, options: options),
            requestedAmount: amount, lockingKeyCounter: 0)
    }
}
#endif
