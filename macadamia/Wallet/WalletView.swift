import CashuSwift
import Popovers
import SwiftData
import SwiftUI

@MainActor
struct WalletView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?

    @Binding var urlState: URLState?
    
    enum Destination: Identifiable, Hashable {
        case mint
        case send
        case receive(urlString: String?)
        case melt

        var id: String {
            switch self {
            case .mint:
                return "mint"
            case .send:
                return "send"
            case .receive(let urlString):
                return "receive_\(urlString ?? "nil")"
            case .melt:
                return "melt"
            }
        }
    }
    
    @State private var navigationDestination: Destination?
    
    static let buttonPadding: CGFloat = 1
    
    init(urlState: Binding<URLState?>) {
        self._urlState = urlState
    }
    
    var activeWallet:Wallet? {
        wallets.first
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer().frame(maxHeight: 40)
                BalanceCard(balance: activeWallet?.balance() ?? 0,
                            unit: .sat)
                .onAppear(perform: {
                    // quick sanity check for uniqueness of C across list of proofs
                    guard let activeWallet else {
                        logger.warning("""
                                       wallet view appeared with no activeWallet. \
                                       this will give undefined behaviour.
                                       """)
                        return
                    }
                    let uniqueCs = Set(activeWallet.proofs.map( { $0.C }))
                    if uniqueCs.count != activeWallet.proofs.count {
                        logger.critical("Wallet seems to contain duplicate proofs.")
                    }
                })
                Spacer().frame(maxHeight: 20)
                MinimalEventList()
                Spacer().frame(maxHeight: 20)
                HStack(alignment: .bottom) {
                    // MARK: BUTTON "RECEIVE" -
                    Templates.Menu(
                        configuration: {
                            $0.popoverAnchor = .bottom
                            $0.originAnchor = .top
                            $0.backgroundColor = Color.black.opacity(0.5)
                        }
                    ) {
                        Templates.MenuItem {
                            navigationDestination = .receive(urlString: nil)
                        } label: { fade in
                            menuButtonLabel(title: "Redeem",
                                            subtitle: "Claim Ecash from a Token",
                                            imageSystemName: "qrcode",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .mint
                        } label: { fade in
                            menuButtonLabel(title: "Mint",
                                            subtitle: "Create Lightning Invoice",
                                            imageSystemName: "bolt.fill",
                                            fade: fade)
                        }
                        .background(Color.black)
                    } label: { fade in
                        menuLabel(imageName: "arrow.down", text: "Receive", fade: fade)
                    }
                    
                    // MARK: - SCANNER
                    InputViewModalButton(inputTypes: [.bolt11Invoice, .token]) {
                        Image(systemName: "qrcode")
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .padding(16)
                            .background(Color.secondary.opacity(0.3))
                            .cornerRadius(10)
                    } result: { string in
                        print(string)
                    }


                    // MARK: BUTTON "SEND" -
                    Templates.Menu(
                        configuration: {
                            $0.popoverAnchor = .bottom
                            $0.originAnchor = .top
                            $0.backgroundColor = Color.black.opacity(0.5)
                        }
                    ) {
                        Templates.MenuItem {
                            navigationDestination = .send
                        } label: { fade in
                            menuButtonLabel(title: "Send",
                                            subtitle: "Create Token to Share",
                                            imageSystemName: "banknote",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .melt
                        } label: { fade in
                            menuButtonLabel(title: "Melt",
                                            subtitle: "Pay Lightning Invoice",
                                            imageSystemName: "bolt.fill",
                                            fade: fade)
                        }
                        .background(Color.black)
                    } label: { fade in
                        menuLabel(imageName: "arrow.up", text: "Send", fade: fade)
                    }
                }
                .padding(EdgeInsets(top: 20, leading: 6, bottom: 40, trailing: 6))
            }
            .navigationDestination(item: $navigationDestination) { destination in
                switch destination {
                case .mint:
                    MintView()
                case .send:
                    SendView()
                case .receive (let urlString):
                    RedeemContainerView(tokenString: urlString)
                case .melt:
                    MeltView()
                }
            }
            .onChange(of: urlState, { oldValue, newValue in
                print("url state var did change to \(newValue?.url ?? "nil")")
                if let newValue {
                    navigationDestination = .receive(urlString: newValue.url)
                    urlState = nil
                }
            })
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        }
    }
    
    private func menuLabel(imageName: String,
                           text: String,
                           fade: Bool) -> some View {
        Text("\(Image(systemName: imageName))  \(text)")
            .opacity(fade ? 0.5 : 1)
            .font(.title3)
            .fontWeight(.semibold)
            .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.3))
            .cornerRadius(10)
    }
    
    private func menuButtonLabel(title: String,
                                 subtitle: String,
                                 imageSystemName: String,
                                 fade: Bool) -> some View {
        Color.clear.overlay(
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .foregroundStyle(.white)
                        .font(.title3)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: imageSystemName)
            }
        )
        .opacity(fade ? 0.5 : 1)
        .padding(EdgeInsets(top: 24, leading: 12, bottom: 24, trailing: 12))
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

//#Preview {
//    WalletView(urlState: .constant(nil))
//}
