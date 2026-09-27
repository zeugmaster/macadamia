@testable import macadamia
import XCTest

final class BOLT11MeltTests: XCTestCase {
    @MainActor
    func testInvoiceRoundingAndPartialPaymentAmounts() throws {
        // Signed synthetic invoices; no mint or payment is involved.
        let cases: [(msat: Int, sats: Int, invoice: String)] = [
            (1, 1, "lnbc10p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqw8x4rkx4vlkeqcxwtnqtjpkzddc52q36zvwqwqm23h64xl9qnsw9nqwqdr2vdezs7qrucn782tkvc04pxh4xn7qte7dkeyy7alkpcmqp0qyp55"),
            (999, 1, "lnbc9990p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqlvu3g53wwx538r3rk6edmpwl3uhz2s7pn87rlly0j003avt2qvqrrl33qy3l6j6dfjadmwfsuv2nrspjmf8sqs4ek9aystmfdr3c9yqqn6wknz"),
            (1000, 1, "lnbc10n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqsh9qzmpyz5gqknj4720j7z9ht7wdr9hg9wmgqs8awrxwpt7mn2lz0s82y3758teqqrddk7z94x8dndzah6ukmgsj9hu6m5vauxvn5lgpdsktr9"),
            (1001, 2, "lnbc10010p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sql285p5c62w9ttljkcxjmut62ftxqgmx52ft5x2crvr9n76e0qky5akk4gznhrf3s4rpewjf3l9rht3ejk65ldamgh7x033rvkzsplpsq2yta0r"),
            (100000000, 100000, "lnbc1m1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqw56xky0zx8slf9xz3wsvd48d23sxqcnn7892kehnrfda8g2g58hskr4s3meczdzkjj8jp933hgd72v0r8hclqy9329u6y45a7r5988gqn5lag6"),
            (100000001, 100001, "lnbc1000000010p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqmevdjywaxl89h8ssjlzqpm7vjky7megzg9wp94d5wexvdd9chwqzk09y6jj3czk2sajud9lrxeg0fypph0pllvhwnwq7fn4pu0cu0gcqnyd5nr"),
        ]
        for (msat, sats, invoice) in cases {
            XCTAssertEqual(try BOLT11MeltQuoteSource.satAmount(from: invoice), sats)
            if msat % 1_000 == 0 {
                XCTAssertEqual(try BOLT11MeltQuoteSource.satAmount(from: invoice, isMPP: true), sats)
            } else {
                XCTAssertThrowsError(try BOLT11MeltQuoteSource.satAmount(from: invoice, isMPP: true))
            }
        }
        XCTAssertThrowsError(try BOLT11MeltQuoteSource.satAmount(from: "invalid"))
    }
}
