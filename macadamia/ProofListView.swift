import SwiftUI
import SwiftData
import Flow

extension Proof.State {
    var sortOrder:Int {
        switch self {
        case .valid:
            0
        case .pending:
            1
        case .spent:
            2
        }
    }
}

struct MintListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var mints: [Mint]
    
    var body: some View {
        List {
            ForEach(mints) { m in
                NavigationLink(destination: ProofListView(proofs: m.proofs),
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
    
    var proofs:[Proof]
    
    var sortedProofs:[Proof] {
        let outer = [
            proofs.filter({ $0.state == .valid }).sorted(by: { $0.amount < $1.amount }),
            proofs.filter({ $0.state == .pending }).sorted(by: { $0.amount < $1.amount }),
            proofs.filter({ $0.state == .spent }).sorted(by: { $0.amount < $1.amount })
        ]
        return outer.flatMap { $0 }
    }
    
    var body: some View {
        List {
            ForEach(sortedProofs) { proof in
                ProofView(proof: proof)
            }
        }
        .navigationTitle(proofs.first?.mint?.url.host(percentEncoded:false) ?? "")
    }
}

struct ProofView: View {
    var proof: Proof
    
    var body: some View {
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
            }
        }
        
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

let mockProof = Proof(keysetID: "12afs4124as", 
                      C: "asdf8760af7d60a87fd60a976f0a9s7f60a9f7609a7f609a7f6",
                      secret: "1lk243j1öl4kjö1l43kjö1l4kj1öl23k4j1öl24kj1öl23k4j",
                      unit: .sat,
                      inputFeePPK: 100,
                      state: .spent,
                      amount: 16,
                      mint: nil,
                      wallet: nil)

//#Preview {
//    ProofView(proof: mockProof)
//}
//
//#Preview {
//    ProofListView()
//}
