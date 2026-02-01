import SwiftUI
import SwiftData
import Flow
import CashuSwift

struct MintListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var mints: [Mint]
    
    var mintOfActiveWallet: [Mint] {
        mints.filter { $0.wallet?.active == true }
             .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) }
    }
    
    var body: some View {
        List {
            ForEach(mintOfActiveWallet) { m in
                NavigationLink(destination: ProofListView(mintID: m.mintID),
                               label: {
                    VStack(alignment: .leading) {
                        Text(m.displayName)
                        Text(m.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                })
            }
        }
    }
}

#Preview {
    MintListView()
}

struct ProofListView: View {
    let id = UUID()
    
    let mintID: UUID
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allProofs: [Proof]
    @Query private var wallets: [Wallet]
    @Query private var mints: [Mint]
    
    @State private var remoteStates: [String : CashuSwift.Proof.ProofState]? = nil
    
    @State private var loadingCounters = false
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    @State private var keysetLabelID = UUID()
        
    private var mint: Mint? {
        mints.first(where: { $0.mintID == mintID })
    }
    
    private var mintProofs: [Proof] {
        mint?.proofs ?? []
    }
    
    private var sortedProofs: [Proof] {
        let outer = [
            mintProofs.filter({ $0.state == .valid }).sorted(by: { $0.amount < $1.amount }),
            mintProofs.filter({ $0.state == .pending }).sorted(by: { $0.amount < $1.amount }),
            mintProofs.filter({ $0.state == .spent }).sorted(by: { $0.amount < $1.amount })
        ]
        return outer.flatMap { $0 }
    }
    
    
    var body: some View {
        if let mint {
            List {
                Section {
                    Button {
                        Task {
                            let result = try await CashuSwift.check(mintProofs.sendable(), url: mint.url)
                            await MainActor.run {
                                var dict = [String : CashuSwift.Proof.ProofState]()
                                for (i, p) in mintProofs.enumerated() {
                                    dict[p.C] = result[i]
//                                    print("e: \(p.dleq?.e ?? "") has state: \(p.state) remote is: \(result[i])")
                                }
                                remoteStates = dict
                            }
                        }
                    } label: {
                        Text("Load States")
                    }
                    Button {
                        guard let remoteStates, remoteStates.values.count == sortedProofs.count else {
                            return
                        }
                        for p in mintProofs {
                            if let state = remoteStates[p.C] { p.state = Proof.State(state: state) }
                        }
                    } label: {
                        Text("Overwrite ⚠")
                    }.disabled(remoteStates == nil)
                }
                
                Section {
                    ForEach(mint.keysets, id: \.keysetID) { keyset in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(keyset.keysetID)
                                Spacer()
                                Text(String(keyset.derivationCounter))
                                    .monospaced()
                            }
                            HStack {
                                Text(keyset.active ? "ACTIVE" : "inactive")
                                Spacer()
                                Text("\(keyset.inputFeePPK) ppk")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .id(keysetLabelID)
                    
                    Button {
                        updateCounters()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Fix derivation counters")
                                Text("WARNING: This reduces your privacy with this mint!")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if loadingCounters {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                    }
                    .disabled(loadingCounters)
                } header: {
                    Text("Keysets and derivation counters")
                }
                
                Section(content: {
                    ForEach(sortedProofs) { proof in
                        NavigationLink {
                            ProofDataView(proof: proof)
                        } label: {
                            HStack {
                                if let remoteStates, let state = remoteStates[proof.C] {
                                    Group {
                                        switch state {
                                        case .unspent:
                                            RoundedRectangle(cornerRadius: 2)
                                                .foregroundStyle(.green)
                                                .frame(width: 6)
                                        case .pending:
                                            RoundedRectangle(cornerRadius: 2)
                                                .foregroundStyle(.yellow)
                                                .frame(width: 6)
                                        case .spent:
                                            RoundedRectangle(cornerRadius: 2)
                                                .foregroundStyle(.red)
                                                .frame(width: 6)
                                        }
                                    }
                                }
                                VStack(alignment:.leading) {
                                    HStack {
                                        switch proof.state {
                                        case .valid:
                                            Circle()
                                                .frame(width: 10)
                                                .foregroundStyle(.green)
                                        case .pending:
                                            Circle()
                                                .frame(width: 10)
                                                .foregroundStyle(.yellow)
                                        case .spent:
                                            Circle()
                                                .frame(width: 10)
                                                .foregroundStyle(.red)
                                        }
                                        Text(proof.C.prefix(10) + "...")
                                        Spacer()
                                        Text(String(proof.amount))
                                    }
                                    .bold()
                                    .font(.title3)
                                    .monospaced()
                                    HFlow() {
                                        TagView(text: proof.keysetID)
                                        TagView(text: proof.unit.rawValue)
                                        TagView(text: String(proof.inputFeePPK))
                                    }
                                }
                            }
                        }
                    }
                }, header: {
                    Text("\(sortedProofs.count) objects")
                })
            }
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        } else {
            Text("Mint could not be found")
        }
    }
    
    private func updateCounters() {
        guard let seed = wallets.first?.seed, let mint else {
            return
        }
        
        loadingCounters = true
        
        let sendableMint = CashuSwift.Mint(mint)
        
        Task {
            do {
                let response = try await CashuSwift.restore(from: sendableMint, with: seed)
                
                await MainActor.run {
                    for result in response.result {
                        print("new derivation counter \(result.derivationCounter) for keyset \(result.keysetID)")
                        mint.setDerivationCounterForKeysetWithID(result.keysetID, to: result.derivationCounter)
                    }
                    loadingCounters = false
                    keysetLabelID = UUID() // force redraw
                }
            } catch {
                await MainActor.run {
                    displayAlert(alert: AlertDetail(with: error))
                    loadingCounters = false
                }
            }
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

extension Proof.State {
    init(state: CashuSwift.Proof.ProofState) {
        switch state {
        case .unspent:
            self = .valid
        case .pending:
            self = .pending
        case .spent:
            self = .spent
        }
    }
}


struct TagView: View {
    var text:String
    var backgroundColor:Color = .secondary.opacity(0.3)
    
    var body: some View {
        Text(LocalizedStringKey(text))
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .background(backgroundColor)
            .cornerRadius(4)
    }
}
