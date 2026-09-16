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
}
