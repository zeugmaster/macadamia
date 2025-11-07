//
//  Onboarding.swift
//  macadamia
//
//  Created by zm on 23.01.25.
//

import SwiftUI
import MarkdownUI

// placeholder for previews
let dummySeed = "coil indicate path field habit ladder concert disease gate robot industry prison".components(separatedBy: " ")

struct Onboarding: View {
    @State private var seedPhraseWrittenDown = false
    @State private var tosAcknowledged = false
    
    @State private var currentPage: Int = 0
    
    var seedPhrase: [String]
    var onClose: () -> Void
    
    private var doneButtonDisabled: Bool {
        if currentPage == 3 && tosAcknowledged {
            return false
        } else if tosAcknowledged && seedPhraseWrittenDown {
            return false
        } else {
            return true
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            
            Group {
                RadialGradient(
                    gradient: Gradient(colors: [Color(white: 0.1), .black]),
                    center: .leading,
                    startRadius: 100,
                    endRadius: 1000
                )
                RadialGradient(
                    gradient: Gradient(colors: [Color(white: 0.08), .clear]),
                    center: .bottomTrailing,
                    startRadius: 100,
                    endRadius: 400
                )
            }
            
            Group {
                TabView(selection: $currentPage) {
                    WelcomePage().tag(0)
                    DisclaimerPage().tag(1)
                    SeedPhrasePage(seedPhraseWrittenDown: $seedPhraseWrittenDown, phrase: seedPhrase).tag(2)
                    TOSPage(tosAcknoledged: $tosAcknowledged).tag(3)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
        
                HStack {
                    Spacer()
                    Button(action: {
                        if !seedPhraseWrittenDown {
                            withAnimation {
                                currentPage = 2
                            }
                        } else {
                            onClose()
                        }
                    }) {
                        Text("Done")
                    }
                    .padding()
                    .disabled(doneButtonDisabled)
                    .buttonStyle(.bordered)
                }
            }
        }
        .background(Color.gray.opacity(0.15))
        .ignoresSafeArea()
    }
}

struct OnboardingPageLayout<Content: View>: View {
    @ScaledMetric(relativeTo: .body) private var scaleMetric: CGFloat = 20
    
    private var sidePadding: CGFloat {
        max(0, 50-scaleMetric)
    }
    
    var title: String
    var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading) {
            Spacer().frame(maxHeight: 50)
            Text(title)
                .fontWeight(.semibold)
                .font(.largeTitle)
            Spacer().frame(maxHeight: 30)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 0, leading: sidePadding, bottom: 70, trailing: sidePadding))
    }
}

struct WelcomePage: View {
    var body: some View {
        OnboardingPageLayout(title: "Hi there!") {
            Markdown("""
                     You are using **macadamia**, the first fully native \
                     ecash wallet for the Cashu protocol on iOS. \n
                     Digital payments should be as natural as handing over cash in person. \
                     Cashu brings simplicity back to online and real-life payments. \
                     Tap [here](https://cashu.space) to learn more. \n
                     The code for this project is **open-source** allowing anyone to view it or contribute. \
                     You can find it on [Github](https://github.com/zeugmaster/macadamia). \n
                     This app does not collect any usage data or analytics. \n
                     Thank you for trying the future of payments! \n\n\n
                     # 🥜🌰
                     """)
            .markdownTextStyle(\.link, textStyle: {
                    UnderlineStyle(.single)
            })
        }
    }
}

struct DisclaimerPage: View {
    var body: some View {
        OnboardingPageLayout(title: "⚠️ Warning") {
            Markdown("""
                     This wallet and the Cashu protocol are in active development. \
                     Be cautious when using this software and follow best practices:
                     
                     - Mint only as much as you are ready to lose
                     
                     - Only use mints you trust
                     
                     - Back up your wallet
                     
                     If you experience any issues, don't hesitate to send a request for \
                     support or feedback to [support@macadamia.cash](mailto:support@macadamia.cash) \
                     or open an Issue on [Github](https://github.com/zeugmaster/macadamia/issues).
                     """)
            .markdownTextStyle(\.link, textStyle: {
                UnderlineStyle(.single)
            })
        }
    }
}

struct SeedPhrasePage: View {
    @State private var copied = false
    @Binding var seedPhraseWrittenDown: Bool
    let phrase: [String]
    
    var body: some View {
        OnboardingPageLayout(title: "Wallet Backup") {
            VStack {
                Markdown("""
                         This is your newly generated **seed phrase** backup. \
                         Write these twelve words down or save them in a password \ 
                         manager and use them to restore ecash from the mints known to this wallet (write those down, too). \n 
                         """)
                Spacer()
                if phrase.count == 12 {
                    HStack {
                        VStack(alignment: .leading) {
                            ForEach(phrase.indices.dropLast(6), id: \.self) { index in
                                HStack {
                                    Text(String(index + 1) + ".")
                                        .frame(minWidth: 30)
                                    Text(phrase[index]).bold()
                                }
                            }
                        }
                        .padding()
                        VStack(alignment: .leading) {
                            ForEach(phrase.indices.dropFirst(6), id: \.self) { index in
                                HStack {
                                    Text(String(index + 1) + ".").frame(minWidth: 30)
                                    Text(phrase[index]).bold()
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Text("Not a valid mnemonic.")
                }
                Button {
                    withAnimation {
                        copied = true
                    }
                    UIPasteboard.general.string = phrase.joined(separator: " ")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            copied = false
                        }
                    }
                } label: {
                    if copied {
                        Text("Copied \(Image(systemName: "list.clipboard"))")
                    } else {
                        Text("Copy \(Image(systemName: "clipboard"))")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                    Text(tos_rev1)
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

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 5.0)
                .stroke(lineWidth: 2)
                .frame(width: 22, height: 22)
                .cornerRadius(5.0)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .bold()
                    }
                }
            configuration.label
        }
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}


#Preview {
    Onboarding(seedPhrase: dummySeed) {
        print("onClose closure executed")
    }
}
//#Preview {
//    DisclaimerPage()
//}
//#Preview {
//    SeedPhrasePage(seedPhraseWrittenDown: .constant(true), phrase: dummySeed)
//}
//#Preview {
//    TOSPage(tosAcknoledged: .constant(true))
//}
