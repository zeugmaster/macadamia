//
//  Onboarding.swift
//  macadamia
//
//  Created by zm on 23.01.25.
//

import SwiftUI

struct Onboarding: View {
   @State private var seedPhraseWrittenDown = false
   @State private var tosAcknowledged = false
   @State private var currentPage = 0
   
   var body: some View {
       VStack {
           TabView() {
               WelcomePage()
               DisclaimerPage()
               SeedPhrasePage(seedPhraseWrittenDown: $seedPhraseWrittenDown)
               TOSPage(tosAcknoledged: $tosAcknowledged)
           }
           .tabViewStyle(.page)
           .indexViewStyle(.page(backgroundDisplayMode: .always))
           
           Button(action: {
               print("Go to wallet")
           }) {
               Text("Complete")
           }
           .padding()
           .disabled(!seedPhraseWrittenDown || !tosAcknowledged)
           .buttonStyle(.bordered)
       }
       .background(Color.gray.opacity(0.2))
   }
}
struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading) {
            Spacer().frame(maxHeight: 50)
            Text("macadamia Wallet")
                .font(.largeTitle)
                .bold()
            Spacer().frame(maxHeight: 50)
            Text("Welcome")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct DisclaimerPage: View {
    var body: some View {
        VStack(alignment: .leading) {
            Spacer().frame(maxHeight: 50)
            Text("Warning ⚠️")
                .font(.largeTitle)
                .bold()
            Spacer().frame(maxHeight: 50)
            Text("""
                 This wallet and the Cashu protocol are in active development. \
                 Only use it with small amounts you are ready to lose or consider using fake ecash \
                 from a test mint.
                 """)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct SeedPhrasePage: View {
    @Binding var seedPhraseWrittenDown: Bool
    
    var body: some View {
        VStack {
            Text("Seed Phrase")
            Toggle(isOn: $seedPhraseWrittenDown) {
                Text("I have written down the seed phrase")
            }
        }
        .padding(20)
    }
}

struct TOSPage: View {
    @Binding var tosAcknoledged: Bool
    
    var body: some View {
        VStack {
            Text("Terms of Service")
            Toggle(isOn: $tosAcknoledged) {
                Text("I agree to the terms.")
            }
        }
    }
}

#Preview {
    Onboarding()
}
