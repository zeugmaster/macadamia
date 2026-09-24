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

    // Published BOLT test vectors for realistic QR payloads, not live payment requests.
    // https://github.com/lightning/bolts/blob/master/11-payment-encoding.md#examples
    private static let bolt11Invoice = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"

    // Amountless offer with a blinded path from bolt12/offers-test.json.
    // https://github.com/lightning/bolts/blob/master/bolt12/offers-test.json
    private static let bolt12Offer = "lno1pgx9getnwss8vetrw3hhyucs5ypjgef743p5fzqq9nqxh0ah7y87rzv3ud0eleps9kl2d5348hq2k8qzqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgqpqqqqqqqqqqqqqqqqqqqqqqqqqqqzqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqqzq3zyg3zyg3zyg3vggzamrjghtt05kvkvpcp0a79gmy3nt6jsn98ad2xs8de6sl9qmgvcvs"

    static let bolt11 = DepositQuote(
        response: CashuSwift.Bolt11.MintQuote(
            quote: UUID().uuidString, request: bolt11Invoice, amount: 250_000,
            unit: "sat", state: .unpaid, expiry: Int(Date().addingTimeInterval(3600).timeIntervalSince1970)),
        mint: mint,
        option: .init(mintID: mint.mintID, direction: .deposit, unit: .sat, method: .bolt11),
        requestedAmount: 250_000, lockingKeyCounter: nil)

    static let bolt12 = lockedQuote(method: .bolt12, request: bolt12Offer, amount: nil)
    static let onchain = lockedQuote(method: "onchain",
                                    request: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", amount: nil,
                                    paid: 25_000, issued: 10_000,
                                    options: ["confirmations": .integer(3)])
    static let generic = lockedQuote(method: "branch", request: "BRANCH-PREVIEW-1000", amount: 1_000,
                                    methodName: "Branch", unit: .other("bux"))

    private static func lockedQuote(method: CashuSwift.PaymentMethodID, request: String, amount: Int?,
                                    paid: Int = 0, issued: Int = 0, methodName: String? = nil,
                                    unit: Unit = .sat, options: CashuSwift.JSONObject? = nil) -> DepositQuote {
        let quoteID = UUID().uuidString
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
