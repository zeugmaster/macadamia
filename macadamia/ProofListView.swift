import SwiftUI
import SwiftData
import Flow

struct MintListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var mints: [Mint]
    
    var body: some View {
        List {
            ForEach(mints) { m in
                NavigationLink(destination: ProofListView(mint: m),
                               label: {
                    Text(m.url.absoluteString)
                })
            }
        }
    }
}

#Preview {
    MintListView()
}

struct ProofListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allProofs: [Proof]
        
    var mint:Mint
    
    private var sortedProofs: [Proof] {
        let mintProofs = allProofs.filter { p in
            return p.mint?.mintID == mint.mintID
        }
        let outer = [
            mintProofs.filter({ $0.state == .valid }).sorted(by: { $0.amount < $1.amount }),
            mintProofs.filter({ $0.state == .pending }).sorted(by: { $0.amount < $1.amount }),
            mintProofs.filter({ $0.state == .spent }).sorted(by: { $0.amount < $1.amount })
        ]
        return outer.flatMap { $0 }
    }
    
    init(mint: Mint) {
        self.mint = mint
    }
    
    var body: some View {
        List {
            ForEach(sortedProofs) { proof in
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
        .navigationTitle(mint.url.host(percentEncoded:false) ?? "")
    }
}


struct TagView: View {
    var text:String
    var backgroundColor:Color = .secondary.opacity(0.3)
    
    var body: some View {
        Text(text)
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .background(backgroundColor)
            .cornerRadius(4)
    }
}
