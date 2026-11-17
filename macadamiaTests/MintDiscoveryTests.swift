@testable import macadamia
import XCTest

final class MintDiscoveryTests: XCTestCase {
    private let reviewHost = URL(string: "https://reviews.example")!
    private let auditor = MintDirectory.AuditorHost(url: URL(string: "https://auditor.example")!, functionSuffix: "1")

    private func reviewed(_ url: String, count: Int, average: Double?) -> DiscoveredMint {
        var mint = DiscoveredMint(url: url, name: nil, info: nil)!
        mint.reviews = .init(host: reviewHost, id: url, count: count, average: average)
        return mint
    }

    private func audited(_ url: String, healthy: Bool = true, successes: Int = 99, errors: Int = 1) -> DiscoveredMint {
        var mint = DiscoveredMint(url: url, name: nil, info: nil)!
        mint.audit = .init(host: auditor, id: 1, healthy: healthy, successes: successes, errors: errors)
        return mint
    }

    func testMergeJoinsListingsCaseInsensitivelyAndKeepsTheBestDuplicate() {
        // imf.gg lists minibits twice; the auditor spells the path with a capital B.
        let reviews = [reviewed("https://mint.minibits.cash/Bitcoin", count: 27, average: 4.8),
                       reviewed("https://mint.minibits.cash/bitcoin/", count: 0, average: nil)]
        for order in [reviews, reviews.reversed()] {
            let merged = DiscoveredMint.merge(reviewed: order, audited: [audited("https://mint.minibits.cash/Bitcoin")])
            XCTAssertEqual(merged.count, 1)
            XCTAssertEqual(merged.first?.url.path(), "/Bitcoin", "the auditor's URL wins")
            XCTAssertEqual(merged.first?.reviews?.count, 27)
            XCTAssertNotNil(merged.first?.audit)
        }

        let reviewOnly = DiscoveredMint.merge(reviewed: reviews.reversed(), audited: [])
        XCTAssertEqual(reviewOnly.map(\.url.absoluteString), ["https://mint.minibits.cash/Bitcoin"])
    }

    func testRankingSinksFailingMintsAndSmoothsSingleReviews() {
        let merged = DiscoveredMint.merge(
            reviewed: [reviewed("https://lucky.example", count: 1, average: 5),
                       reviewed("https://popular.example", count: 27, average: 4.8),
                       reviewed("https://down.example", count: 40, average: 5)],
            audited: [audited("https://popular.example"),
                      audited("https://down.example", healthy: false),
                      audited("https://new.example", successes: 0, errors: 0)])
        XCTAssertEqual(merged.map { $0.url.host() }, ["popular.example", "lucky.example", "new.example", "down.example"])
        XCTAssertNil(merged.first { $0.url.host() == "new.example" }?.audit?.successRate, "no swaps yet means no rate")
    }

    func testDirectoryPayloadsDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reviews = try decoder.decode(MintDirectory.Page<MintDirectory.ReviewedEntry>.self, from: Data(#"""
            {"mints":[{"id":"aHR0cHM6Ly9taW50LmFnb3Jpc3Quc3BhY2U","url":"https://mint.agorist.space",
            "info":"{\"name\":\"\\\"Agorist Cashu Mint\\\"\",\"nuts\":{\"4\":{\"disabled\":false,\"methods\":[{\"method\":\"bolt11\",\"unit\":\"sat\"}]}}}",
            "name":"\"Agorist Cashu Mint\"","updated_at":"2026-11-17T09:46:37Z","review_count":1,"review_avg":4.0}],"total":43}
            """#.utf8))
        let audits = try decoder.decode(MintDirectory.Page<MintDirectory.AuditedEntry>.self, from: Data(#"""
            {"mints":[{"id":1,"url":"https://m7.mountainlake.io","info":null,"name":"Mountainlake M7","balance":28286,
            "state":"OK","n_errors":3,"n_mints":110,"n_melts":86}],"total":25}
            """#.utf8))

        XCTAssertEqual(reviews.total, 43)
        XCTAssertEqual(reviews.mints.first?.reviewCount, 1)
        XCTAssertEqual(audits.mints.first?.nMelts, 86)

        let entry = try XCTUnwrap(reviews.mints.first)
        let mint = try XCTUnwrap(DiscoveredMint(url: entry.url, name: entry.name, info: entry.info))
        XCTAssertEqual(mint.name, "Agorist Cashu Mint", "literal quotes are stripped")
        XCTAssertEqual(mint.info?.nuts?.nut04?.methods?.first?.unit, "sat")
    }

    func testFirstAvailableFallsThroughToTheNextHost() async {
        let answer = await MintDirectory.firstAvailable(["down", "up"]) { host -> String in
            guard host == "up" else { throw URLError(.cannotConnectToHost) }
            return host
        }
        XCTAssertEqual(answer, "up")

        let none = await MintDirectory.firstAvailable(["down"]) { _ -> String in throw URLError(.timedOut) }
        XCTAssertNil(none)
    }
}
