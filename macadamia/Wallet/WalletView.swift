import CashuSwift
import Popovers
import SwiftData
import SwiftUI

let betaDisclaimerURL = URL(string: "https://macadamia.cash/beta.html")!

@MainActor
struct WalletView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var proofs: [Proof]
    
    @State var balance: Int?

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
                BalanceCard(balance: balance ?? 0,
                            unit: .sat)
                .onAppear(perform: {
                    balance = proofs.filter { $0.state == .valid && $0.wallet == activeWallet && $0.mint?.hidden ?? true == false}.sum
                    
                    // quick sanity check for uniqueness of C across list of proofs
                    guard let activeWallet else {
                        logger.warning("wallet view appeared with no activeWallet. this will give undefined behaviour.")
                        return
                    }
                    let uniqueCs = Set(activeWallet.proofs.map( { $0.C }))
                    if uniqueCs.count != activeWallet.proofs.count {
                        logger.critical("Wallet seems to contain duplicate proofs.")
                    }
                })
                Spacer().frame(maxHeight: 30)
                MinimalEventList()
                Spacer().frame(maxHeight: 30)
                HStack {
                    // MARK: - BUTTON "RECEIVE"

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
                            MenuButtonLabel(title: "Redeem",
                                            subtitle: "Claim Ecash from a Token",
                                            imageSystemName: "qrcode",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .mint
                        } label: { fade in
                            MenuButtonLabel(title: "Mint",
                                            subtitle: "Create Lightning Invoice",
                                            imageSystemName: "bolt.fill",
                                            fade: fade)
                        }
                        .background(Color.black)
                    } label: { fade in
                        Text("\(Image(systemName: "arrow.down"))  Receive")
                            .opacity(fade ? 0.5 : 1) // Apply fading effect based on a condition
                            .dynamicTypeSize(.xLarge) // Apply dynamic type size for accessibility
                            .fontWeight(.semibold) // Apply bold font weight
                            .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)) // Add padding around the text
                            .frame(maxWidth: .infinity) // Ensure it takes up the maximum width
                            .background(Color.secondary.opacity(0.3)) // Apply a semi-transparent background
                            .cornerRadius(10) // Apply rounded corners to the background
                    }

                    // MARK: - BUTTON "SEND"

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
                            MenuButtonLabel(title: "Send",
                                            subtitle: "Create Token to Share",
                                            imageSystemName: "banknote",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .melt
                        } label: { fade in
                            MenuButtonLabel(title: "Melt",
                                            subtitle: "Pay Lightning Invoice",
                                            imageSystemName: "bolt.fill",
                                            fade: fade)
                        }
                        .background(Color.black)
                    } label: { fade in
                        Text("\(Image(systemName: "arrow.up"))  Send")
                            .opacity(fade ? 0.5 : 1) // Apply fading effect based on a condition
                            .dynamicTypeSize(.xLarge) // Apply dynamic type size for accessibility
                            .fontWeight(.semibold) // Apply bold font weight
                            .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
                            .frame(maxWidth: .infinity) // Ensure it takes up the maximum width
                            .background(Color.secondary.opacity(0.3)) // Apply a semi-transparent background
                            .cornerRadius(10) // Apply rounded corners to the background
                    }
                }
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 40, trailing: 20))
            }
            .navigationDestination(item: $navigationDestination) { destination in
                switch destination {
                case .mint:
                    MintView()
                case .send:
                    SendView()
                case .receive (let urlString):
                    ReceiveView(tokenString: urlString)
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
    
    

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct MenuButtonLabel: View {
    let title: String
    let subtitle: String
    let imageSystemName: String
    var fade: Bool
    
    var body: some View {
        Color.clear.overlay(
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .foregroundStyle(.white)
                        .dynamicTypeSize(.large)
                    Text(subtitle)
                        .dynamicTypeSize(.xSmall)
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: imageSystemName)
            }
        )
        .opacity(fade ? 0.5 : 1)
        .padding(24)
    }
}

#Preview {
    WalletView(urlState: .constant(nil))
}
