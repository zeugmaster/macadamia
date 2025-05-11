//
//  UntrustedRedeemView.swift
//  macadamia
//
//  Created by zm on 07.05.25.
//

import SwiftUI

struct UntrustedRedeemView: View {
    
    enum Row { case first, second }
    @State private var selectedRow: Row?
    @State private var pickerValue = 0
    let options = ["Scrat from Ice Age", "Two", "Three"]

    var body: some View {
        List {
            HStack {
                Image(systemName: selectedRow == .first ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedRow == .first ? .accentColor : .secondary)
                Text("Add Mint")
                Spacer()
                Text("mint.macadamia.cash")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedRow = .first
            }

            HStack {
                Image(systemName: selectedRow == .second ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedRow == .second ? .accentColor : .secondary)
                Text("Swap to")
                Spacer()
                Picker("", selection: $pickerValue) {
                    ForEach(0..<options.count, id: \.self) {
                        Text(options[$0]).tag($0)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .labelsHidden()
                .tint(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedRow = .second
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

#Preview {
    UntrustedRedeemView()
}
