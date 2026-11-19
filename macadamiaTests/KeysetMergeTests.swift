@testable import macadamia
import CashuSwift
import XCTest

final class KeysetMergeTests: XCTestCase {
    private func keyset(_ id: String, active: Bool, counter: Int) throws -> CashuSwift.Keyset {
        var keyset = try JSONDecoder().decode(CashuSwift.Keyset.self,
                                              from: Data(#"{"id":"\#(id)","unit":"sat","active":\#(active),"keys":{}}"#.utf8))
        keyset.derivationCounter = counter
        return keyset
    }

    @MainActor
    func testMergeNeverMovesCountersBackOrForgetsKeysets() throws {
        let mint = Mint(url: try XCTUnwrap(URL(string: "https://mint.example")),
                        keysets: [try keyset("00aa", active: true, counter: 12), try keyset("00bb", active: true, counter: 3)])
        // A refresh captured 00aa's counter at 5, then the wallet advanced it to 12; the mint rotated 00aa and stopped listing 00bb.
        mint.mergeKeysets([try keyset("00aa", active: false, counter: 5), try keyset("00cc", active: true, counter: 0)])
        XCTAssertEqual(mint.keysets.map(\.keysetID), ["00aa", "00bb", "00cc"])
        XCTAssertEqual(mint.keysets.first { $0.keysetID == "00aa" }?.derivationCounter, 12, "a stale snapshot never rolls a counter back")
        XCTAssertEqual(mint.keysets.first { $0.keysetID == "00aa" }?.active, false, "the mint's flags still win")
        XCTAssertEqual(mint.keysets.first { $0.keysetID == "00bb" }?.derivationCounter, 3, "unlisted keysets keep their counter")
        XCTAssertEqual(mint.keysets.first { $0.keysetID == "00cc" }?.derivationCounter, 0)
    }
}
