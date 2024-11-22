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

    @State var navigationPath = NavigationPath()
    
    @Binding var urlState: String?

    static let buttonPadding: CGFloat = 1
    
    init(urlState: Binding<String?>) {
        self._urlState = urlState
    }
    
    var activeWallet:Wallet? {
        set {}
        get {
            wallets.first
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                Spacer(minLength: 20)
                VStack(alignment: .center) {
                    Text(balance != nil ? String(balance!) : "...")
                        .monospaced()
                        .bold()
                        .font(.system(size: 70))
                    Text("sats")
                        .monospaced()
                        .bold()
                        .dynamicTypeSize(.xxxLarge)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .foregroundStyle(.secondary)
                }
                .padding(40)
                .onAppear(perform: {
                    // FIXME: NEEDS TO RESPECT WALLET SELECTION
                    balance = proofs.filter { $0.state == .valid }.sum
                    
                    // quick sanity check for uniqueness of C across list of proofs
                    let uniqueCs = Set(proofs.map( { $0.C }))
                    if uniqueCs.count != proofs.count {
                        logger.critical("Wallet seems to contain duplicate proofs.")
                    }
                })
                Spacer()
                List {
                    if events.isEmpty {
                        Text("No transactions yet.")
                    } else {
                        ForEach(events) { event in
                            TransactionListRowView(event: event)
                        }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
                .listStyle(.plain)
                Spacer()
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
                            navigationPath.append("Receive")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Scan or Paste Token")
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
                            navigationPath.append("Mint")
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
                            navigationPath.append("Send")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Create Cashu Token")
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
                            navigationPath.append("Melt")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Pay Lightning Invoice")
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
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 50, trailing: 20))
            }
            .navigationDestination(for: String.self) { tag in
                switch tag {
                case "Send":
                    SendView(navigationPath: $navigationPath)
                case "Receive":
                    ReceiveView(tokenString: urlState, navigationPath: $navigationPath)
                case "Melt":
                    MeltView(navigationPath: $navigationPath)
                case "Mint":
                    MintView(navigationPath: $navigationPath)
                default:
                    EmptyView()
                }
            }
            .onChange(of: urlState, { oldValue, newValue in
                if newValue != nil {
                    navigationPath.append("Receive")
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
                Text(event.shortDescription)
                Spacer()
                if let amount = event.amount {
                    Text(amountDisplayString(amount, unit: event.unit))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .font(.callout)
        }
    }
}

#Preview {
    WalletView(urlState: .constant(nil))
}
