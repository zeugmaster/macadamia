@testable import macadamia
import CashuSwift
import SwiftData
import XCTest

final class OnchainMeltTests: XCTestCase {
    private let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    private let txid = String(repeating: "ab", count: 32)

    // NUT-30 example response, before and after execution.
    private func quote(state: String, selected: String = "null", outpoint: String = "null") throws -> CashuSwift.Onchain.MeltQuote {
        try JSONDecoder().decode(CashuSwift.Onchain.MeltQuote.self, from: Data("""
        {"quote":"019e6d5a-2347-7000-83ad-72a9a83f3105","amount":100000,"unit":"sat","method":"onchain",
         "state":"\(state)","expiry":1701704757,"request":"\(address)",
         "fee_options":[{"fee_index":0,"fee_reserve":5000,"estimated_blocks":1},
                        {"fee_index":1,"fee_reserve":2000,"estimated_blocks":6},
                        {"fee_index":2,"fee_reserve":800,"estimated_blocks":144}],
         "selected_fee_index":\(selected),"outpoint":\(outpoint)}
        """.utf8))
    }

    func testDestinationParsesAddressesAndPaymentLinks() throws {
        let link = try XCTUnwrap(OnchainMeltView.Destination("bitcoin:\(address.uppercased())?amount=0.0001&label=x"))
        XCTAssertEqual(link.address, address.uppercased())
        XCTAssertEqual(link.amount, 10_000)
        let bare = try XCTUnwrap(OnchainMeltView.Destination(" \(address)\n"))
        XCTAssertEqual(bare.address, address)
        XCTAssertNil(bare.amount)
        XCTAssertNil(OnchainMeltView.Destination("bitcoin:\(address)?amount=0.000000001")?.amount, "sub-sat amounts are ignored")
        XCTAssertNil(OnchainMeltView.Destination("bitcoin:\(address)?amount=-1")?.amount)
        XCTAssertNil(OnchainMeltView.Destination("bitcoin:?lightning=lnbc1"), "a link without an address is not a destination")
        XCTAssertNil(OnchainMeltView.Destination("gabagool"))
        XCTAssertNil(OnchainMeltView.Destination("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlH"), "mixed-case bech32 is invalid")
    }

    func testInputValidatorRoutesBitcoinAddressesOnlyWhenSupported() throws {
        func route(_ input: String, _ types: [InputView.InputType]) -> InputView.Result? {
            if case .valid(let result) = InputValidator.validate(input, supportedTypes: types) { result } else { nil }
        }
        XCTAssertEqual(route(address, [.bitcoinAddress]), .init(payload: address, type: .bitcoinAddress))
        XCTAssertEqual(route("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", [.bitcoinAddress])?.type, .bitcoinAddress)
        XCTAssertEqual(route("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx", [.bitcoinAddress])?.type, .bitcoinAddress)
        XCTAssertEqual(route("bcrt1qheasmndw0nlu7v5sah4cf0ujag2gmpf8wm7d5l", [.bitcoinAddress])?.type, .bitcoinAddress, "regtest")
        XCTAssertEqual(OnchainMeltView.Destination("bcrt1qheasmndw0nlu7v5sah4cf0ujag2gmpf8wm7d5l")?.address,
                       "bcrt1qheasmndw0nlu7v5sah4cf0ujag2gmpf8wm7d5l")
        XCTAssertEqual(route("bitcoin:\(address)?amount=0.001", [.bitcoinAddress])?.payload, "bitcoin:\(address)?amount=0.001",
                       "the whole link is passed on for its amount")
        XCTAssertEqual(route("bitcoin:\(address)?lightning=lnbc1", [.bolt11Invoice, .bitcoinAddress])?.type, .bolt11Invoice,
                       "Lightning stays preferred over the address")
        XCTAssertNil(route(address, [.bolt11Invoice, .lightningAddress]))
        XCTAssertNil(route("bitcoin:\(address)", [.bolt11Invoice]))
        XCTAssertNil(route("bitcoin:bc1qinvalid!", [.bitcoinAddress]))
        XCTAssertNil(route("mysatoshi", [.bitcoinAddress]))
    }

    func testPreferredFeeTierIsUsedWhenTheMintOffersIt() throws {
        let options = try quote(state: "UNPAID").feeOptions
        XCTAssertEqual(OnchainMeltView.defaultFeeIndex(in: options, preferred: 2), 2)
        XCTAssertEqual(OnchainMeltView.defaultFeeIndex(in: options, preferred: 9), 0, "falls back to the mint's first tier")
        XCTAssertNil(OnchainMeltView.defaultFeeIndex(in: [], preferred: 0))
    }

    @MainActor
    func testStoredQuoteKeepsItsTypedFieldsForRoutingAndHistory() throws {
        let container = try ModelContainer(for: Wallet.self, Mint.self, Proof.self, Event.self, NostrKeypair.self, NostrMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let wallet = Wallet(mnemonic: "test", seed: "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899")
        let mint = Mint(url: URL(string: "https://mint.example")!, keysets: [])
        mint.wallet = wallet
        container.mainContext.insert(wallet)
        container.mainContext.insert(mint)

        let paid = try quote(state: "PAID", selected: "1", outpoint: "\"\(txid):0\"")
        let event = Event.meltEvent(unit: .sat, shortDescription: "Withdrawal", wallet: wallet, amount: paid.amount,
                                    longDescription: "", mints: [mint], genericQuote: try paid.asGeneric())
        container.mainContext.insert(event)
        try container.mainContext.save()

        XCTAssertEqual(event.genericMeltQuote?.method, .onchain, "routes as an on-chain melt")
        XCTAssertNil(event.bolt11MeltQuote)
        let typed = try XCTUnwrap(event.onchainMeltQuote)
        XCTAssertEqual(typed.state, .paid)
        XCTAssertEqual(typed.request, address)
        XCTAssertEqual(typed.transactionID, txid)
        XCTAssertEqual(typed.selectedFeeIndex, 1)
        XCTAssertEqual(typed.feeOptions.map(\.feeReserve), [5000, 2000, 800])

        let lightning = Event.pendingMeltEvent(unit: .sat, shortDescription: "Pending", wallet: wallet,
                                               quote: .init(quote: "q", request: "lnbc1", amount: 1, unit: "sat", feeReserve: 0,
                                                            state: .unpaid, expiry: nil, paymentPreimage: nil, change: nil),
                                               amount: 1, expiration: nil, mints: [mint])
        XCTAssertNil(lightning.onchainMeltQuote)
        XCTAssertNil(lightning.onchainMeltContext)
    }
}
