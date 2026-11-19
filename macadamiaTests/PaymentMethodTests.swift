@testable import macadamia
import CashuSwift
import XCTest

final class PaymentMethodTests: XCTestCase {
    func testKnownKindsAndGenericMethodIdentity() {
        XCTAssertEqual(CashuSwift.PaymentMethodID.bolt11.kind, .bolt11)
        XCTAssertEqual(CashuSwift.PaymentMethodID.bolt12.kind, .bolt12)
        XCTAssertEqual(CashuSwift.PaymentMethodID(rawValue: "onchain").kind, .onchain)

        let customMethods: [CashuSwift.PaymentMethodID] = ["branch", "apple-pay", "generic", "future_method"]
        XCTAssertTrue(customMethods.allSatisfy { $0.kind == .generic })
        XCTAssertEqual(Set(customMethods).count, 4)
        XCTAssertEqual(customMethods.first?.rawValue, "branch")
    }

    func testNamesUseMetadataOrReadableIDFallback() {
        let cases: [(CashuSwift.PaymentMethodID, String?, String)] = [
            (.bolt11, nil, "BOLT11"),
            (.bolt12, nil, "BOLT12"),
            ("onchain", nil, String(localized: "On-chain")),
            ("branch", "Branch Pay", "Branch Pay"),
            ("apple-pay", nil, "Apple Pay"),
            ("future_payment-method", nil, "Future Payment Method"),
            ("branch", " \n", "Branch")
        ]
        for (id, name, expected) in cases {
            let setting = CashuSwift.Mint.Info.PaymentMethod(method: id, unit: "sat", methodName: name)
            XCTAssertEqual(setting.displayName, expected)
        }
        let misleadingName = CashuSwift.Mint.Info.PaymentMethod(method: "branch", unit: "sat", methodName: "BOLT11")
        XCTAssertEqual(misleadingName.method.kind, .generic)
    }

    func testPaymentOptionCarriesNameWithoutChangingSelectionIdentity() throws {
        let mintID = UUID()
        let original = PaymentOption(mintID: mintID, direction: .deposit, unit: .sat, method: "branch")
        let setting = CashuSwift.Mint.Info.PaymentMethod(method: "branch", unit: "sat", methodName: "Branch Pay")
        let renamed = PaymentOption(mintID: mintID, direction: .deposit, methodSetting: setting)
        let other = PaymentOption(mintID: mintID, direction: .deposit, unit: .sat, method: "other", methodName: "Branch Pay")

        XCTAssertEqual(renamed.id, original.id)
        XCTAssertNotEqual(renamed.id, other.id)
        XCTAssertEqual(renamed.methodName, "Branch Pay")
        XCTAssertEqual(renamed.methodDisplayName, setting.displayName)
        XCTAssertEqual([other, renamed].preferredOption(preserving: original)?.method, "branch")
        XCTAssertEqual([other, renamed].filter { $0.method == original.method }.count, 1)

        let restored = try JSONDecoder().decode(PaymentOption.self, from: JSONEncoder().encode(renamed))
        XCTAssertEqual(restored, renamed)
    }

    func testAmountLimitsIncludeBoundariesAndAllowMissingBounds() {
        let cases: [(Int?, Int?, [Int], [Int])] = [
            (100, 200, [100, 150, 200], [99, 201]),
            (100, nil, [100, Int.max], [99]),
            (nil, 200, [1, 200], [201]),
            (nil, nil, [1, Int.max], []),
            (100, 100, [100], [99, 101])
        ]
        for direction: PaymentDirection in [.deposit, .withdraw] {
            for (minimum, maximum, valid, invalid) in cases {
                let option = PaymentOption(mintID: UUID(), direction: direction, unit: .sat,
                                           method: "branch", minAmount: minimum, maxAmount: maximum)
                for amount in valid {
                    XCTAssertTrue(option.isAmountWithinLimits(amount), "Rejected \(amount) for \(option)")
                }
                for amount in invalid {
                    XCTAssertFalse(option.isAmountWithinLimits(amount), "Accepted \(amount) for \(option)")
                }
            }
        }
    }
}
