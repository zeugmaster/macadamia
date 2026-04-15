//
//  Amount.swift
//  macadamia
//
//  Created by zm on 15.04.26.
//

import SwiftUI

/* TODO:
 - fallbacks to: contenttransitions numerical only, no transition
 -
 */



struct AmountView: View {
    let amount: Double
    let hideAmount: Bool
    
    var body: some View {
        Text(hideAmount ? placeHolder : String(amount))
            .bold(hideAmount)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.5), value: amount)
            .animation(.default, value: hideAmount)
    }
    
    private var placeHolder: String {
        var length = String(amount).count
        length += Int.random(in: -1...1)
        return String(Array(repeating: "*", count: length))
    }
}

struct AmountPreview: View {
    @State private var hide = false
    @State private var amountString = ""
    
    var body: some View {
        VStack {
            Toggle("Toggle", isOn: $hide)
            TextField("input", text: $amountString)
                .textFieldStyle(.roundedBorder)
            AmountView(amount: Double(amountString) ?? 69.0, hideAmount: hide)
        }
        .padding()
        .background(Color.black.gradient)
    }
}

#Preview {
    AmountPreview()
}
