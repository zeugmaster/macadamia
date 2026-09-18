#if DEBUG
import SwiftUI
import SwiftData
import CashuSwift

@MainActor
private enum BOLT12MeltPreview {
    static let amountless = "lno1pgryxmmxvejk293pqgg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3z"
    static let fixed = "lno1pqpsrp4qpgryxmmxvejk293pqgg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3z"

    static let container: ModelContainer = {
        do {
            let container = try ModelContainer(for: Wallet.self, Mint.self, Proof.self, Event.self,
                                               NostrKeypair.self, NostrMessage.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let wallet = Wallet(mnemonic: "preview", seed: "preview")
            let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(#"{"id":"009a1f293253e41e","unit":"sat","active":true,"keys":{},"derivationCounter":0}"#.utf8))
            let mint = Mint(url: URL(string: "https://bolt12-preview.invalid")!, keysets: [keyset])
            mint.wallet = wallet
            mint.nickName = "Preview Mint"
            let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: Data(#"{"nuts":{"5":{"methods":[{"method":"bolt12","unit":"sat"}],"disabled":false}}}"#.utf8))
            try mint.setPreviewInfo(info)
            container.mainContext.insert(wallet)
            container.mainContext.insert(mint)
            container.mainContext.insert(Proof(keysetID: keyset.keysetID, C: "preview", secret: "preview",
                                                unit: .sat, inputFeePPK: 0, state: .valid, amount: 2048,
                                                mint: mint, wallet: wallet))
            return container
        } catch { fatalError("Unable to create BOLT12 preview: \(error)") }
    }()

    static func screen(offer: String) -> some View {
        NavigationStack {
            MeltView(offer: offer, bolt12QuoteFetcher: { request, _ in
                let decoded = try BOLT12OfferInput(request.request)
                let amount = try decoded.paymentAmountSat(enteredSats: (request.options?.amountless?.amountMsat ?? 0) / 1000)
                return .init(quote: "preview-quote", request: request.request, amount: amount,
                             unit: "sat", feeReserve: 2, state: .unpaid,
                             expiry: Int(Date().addingTimeInterval(3600).timeIntervalSince1970))
            })
            .navigationTitle("Pay")
        }
        .modelContainer(container)
        .environmentObject(PreviewData.appState)
        .preferredColorScheme(.dark)
    }
}

#Preview("Amountless offer") {
    BOLT12MeltPreview.screen(offer: BOLT12MeltPreview.amountless)
}

#Preview("Fixed amount offer") {
    BOLT12MeltPreview.screen(offer: BOLT12MeltPreview.fixed)
}
#endif
