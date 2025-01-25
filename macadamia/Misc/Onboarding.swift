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
       ZStack(alignment: .bottomTrailing) {
           TabView() {
               WelcomePage()
               DisclaimerPage()
               SeedPhrasePage(seedPhraseWrittenDown: $seedPhraseWrittenDown)
               TOSPage(tosAcknoledged: $tosAcknowledged)
           }
           .tabViewStyle(.page)
           .indexViewStyle(.page(backgroundDisplayMode: .always))
           .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
           
           HStack {
               Spacer()
               Button(action: {
                   print("Go to wallet")
               }) {
                   Text("Done")
               }
               .padding()
               .disabled(!seedPhraseWrittenDown || !tosAcknowledged)
               .buttonStyle(.bordered)
           }
       }
       .padding()
       .background(Color.gray.opacity(0.15))
   }
}

struct OnboardingPageLayout<Content: View>: View {
    var title: String
    var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading) {
            Spacer().frame(maxHeight: 30)
            Text(title)
                .bold()
                .font(.largeTitle)
            Spacer().frame(maxHeight: 30)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 70, trailing: 10))
    }
}

struct WelcomePage: View {
    var body: some View {
        OnboardingPageLayout(title: "macadamia Wallet") {
            Text("Welcome")
        }
    }
}

struct DisclaimerPage: View {
    var body: some View {
        OnboardingPageLayout(title: "⚠️ Warning") {
            Text("""
                 This wallet and the Cashu protocol are in active development. \
                 Only use it with small amounts you are ready to lose or consider using fake ecash \
                 from a test mint.
                 """)
        }
    }
}

struct SeedPhrasePage: View {
    @Binding var seedPhraseWrittenDown: Bool
    
    var body: some View {
        OnboardingPageLayout(title: "Seed Phrase") {
            VStack {
                Text("This is your seed phrase backup. Write these twelve words down or save them in a password manager and use them to restore ecash from a mint.")
                Spacer()
                Text("""
                     one    two
                     three  four
                     five   six
                     seven  eight
                     nine   ten
                     eleven twelve
                     """)
                Spacer()
                Toggle(isOn: $seedPhraseWrittenDown) {
                    Text("I have written down the seed phrase")
                }.toggleStyle(CheckboxToggleStyle())
            }
        }
    }
}

struct TOSPage: View {
    @Binding var tosAcknoledged: Bool
    
    var body: some View {
        OnboardingPageLayout(title: "Terms") {
            VStack {
                ScrollView {
                    Text(tos)
                }
                .font(.footnote)
                Spacer(minLength: 20)
                Toggle(isOn: $tosAcknoledged) {
                    Text("I agree to the terms.")
                }.toggleStyle(CheckboxToggleStyle())
            }
        }
    }
}

#Preview(body: {
    TOSPage(tosAcknoledged: .constant(true))
})

#Preview {
    Onboarding()
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {

            RoundedRectangle(cornerRadius: 5.0)
                .stroke(lineWidth: 2)
                .frame(width: 22, height: 22)
                .cornerRadius(5.0)
                .overlay {
                    Image(systemName: configuration.isOn ? "checkmark" : "")
                        .bold()
                }
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label

        }
    }
}
