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
    
    // query events (transactions) if they are visible and in chronological order
    @Query(filter: #Predicate { event in
        event.visible == true
    },
    sort: [SortDescriptor(\Event.date, order: .reverse)]) private var events: [Event]

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
    
    var sortedEventsForActiveWallet: [Event] {
        events.filter({ $0.wallet == activeWallet })
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer().frame(maxHeight: 40)
                BalanceCard(balance: balance ?? 0,
                            unit: .sat)
                .onAppear(perform: {
                    balance = proofs.filter { $0.state == .valid && $0.wallet == activeWallet }.sum

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
                List {
                    if sortedEventsForActiveWallet.isEmpty {
                        Text("No transactions yet.")
                    } else {
                        ForEach(Array(sortedEventsForActiveWallet.prefix(5))) { event in
                            TransactionListRowView(event: event)
                        }
                        if sortedEventsForActiveWallet.count > 5 {
                            NavigationLink(destination: EventList(),
                                           label: {
                                Spacer().frame(width: 27)
                                Text("Show All")
                                    .font(.callout)
                            })
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 30, bottom: 0, trailing: 30))
                .listStyle(.plain)
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
                            Color.clear.overlay(
                                HStack {
                                    Text("Redeem eCash")
                                    Spacer()
                                    Image(systemName: "qrcode")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .mint
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Mint")
                                    Spacer()
                                    Image(systemName: "bolt.fill")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
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
                            Color.clear.overlay(
                                HStack {
                                    Text("Send eCash")
                                    Spacer()
                                    Image(systemName: "banknote")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .melt
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Melt")
                                    Spacer()
                                    Image(systemName: "bolt.fill")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
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

struct TransactionListRowView: View {
    var event: Event

    init(event: Event) {
        self.event = event
    }

    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            HStack {
                Group {
                    switch event.kind {
                    case .pendingMelt, .pendingMint:
                        Image(systemName: "hourglass")
                    case .mint, .receive:
                        Image(systemName: "arrow.down.left")
                    case .melt, .send:
                        Image(systemName: "arrow.up.right")
                    case .restore:
                        Image(systemName: "clock.arrow.circlepath")
                    case .drain:
                        Image(systemName: "arrow.uturn.up")
                    }
                }
                .opacity(0.8)
                .font(.caption)
                .frame(width: 20, alignment: .leading)
                if let memo = event.memo, !memo.isEmpty {
                    Text(memo)
                } else {
                    Text(event.shortDescription)
                }
                Spacer()
                if let amount = event.amount {
                    switch event.kind {
                    case .send, .drain, .melt, .pendingMelt:
                        Text(amountDisplayString(amount, unit: event.unit, negative: true))
                            .foregroundStyle(.secondary)
                    case .receive, .mint, .restore, .pendingMint:
                        Text(amountDisplayString(amount, unit: event.unit, negative: false))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1)
            .font(.callout)
        }
        .listRowBackground(Color.clear)
    }
}

#Preview {
    WalletView(urlState: .constant(nil))
}
