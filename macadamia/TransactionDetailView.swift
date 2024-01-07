//
//  TransactionDetailView.swift
//  macadamia
//
//  Created by Dario Lass on 07.01.24.
//

import SwiftUI

struct TransactionDetailView: View {
    @State var transaction:Transaction
    
    init(transaction: Transaction) {
        self.transaction = transaction
    }
    
    func copyToClipboard() {
        if transaction.invoice != nil {
            UIPasteboard.general.string = transaction.invoice
        } else if transaction.token != nil {
            UIPasteboard.general.string = transaction.token
        } else {
            UIPasteboard.general.string = "Undefined"
        }
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Amount: ")
                    Spacer()
                    if transaction.amount > 0 {
                        Text("+\(String(transaction.amount))")
                    } else {
                        Text(String(transaction.amount))
                    }
                }
                Text(transaction.timeStamp)
            }
            Section {
                HStack {
                    if transaction.invoice != nil {
                        Text(transaction.invoice!)
                    } else if transaction.token != nil {
                        Text(transaction.token!)
                    } else {
                        Text("Undefined")
                    }
                    Spacer()
                    Button {
                        copyToClipboard()
                    } label: {
                        Image(systemName: "list.clipboard")
                    }
                    .foregroundStyle(.primary)
                }
                if transaction.token != nil {
                    HStack {
                        Text("Token spendable: ")
                        Spacer()
                        if transaction.pending {
                            Text("Yes \(Image(systemName: "hourglass"))")
                        } else {
                            Text("No")
                        }
                    }
                }
            }
            .lineLimit(2)
        }
        .monospaced()
        .foregroundStyle(.secondary)
    }
}

#Preview {
    TransactionDetailView(transaction: Transaction(timeStamp: "2024-01-07T09:30:46+0000", unixTimestamp: 1704619846, amount: -420, type: .cashu, pending: true,token: "lnbc4200n1uhwpfiunvcaiushföjcsnkudsfhgoiwuehrfökjhwqiufhjöiuqwhröofijhnksejzrghfkuahzura"))
}
