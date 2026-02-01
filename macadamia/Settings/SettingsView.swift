import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    let sourceRepoURL = URL(string: "https://github.com/zeugmaster/macadamia")!
    let mailURL = URL(string: "mailto:contact@macadamia.cash")!
    let faqURL = URL(string: "https://macadamia.cash/faq")!
    
    @State private var hiddenMenuShowing: Bool = false
    @State private var showReleaseNotes: Bool = false

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return String(localized: "Version") + " \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: MnemonicView()) { Text("Show Seed Phrase") }
                    NavigationLink(destination: RestoreView()) { Text("Restore") }
                    NavigationLink(destination: PublicKeyView()) { Text("Show Locking Key") }
                } header: {
                    Text("Cashu")
                }
                
                Section {
                    NavigationLink(destination: NostrSettingsView()) {
                        HStack {
                            Text("Wallet Key & Relays")
                        }
                    }
                } header: {
                    Text("Nostr")
                }
                
                if hiddenMenuShowing {
                    Section {
                        NavigationLink(destination: MintListView()) { Text("Proof Database") }
                        NavigationLink(destination: WalletInfoListView()) { Text("Wallet Info") }
                    } header: {
                        Text("Debugging")
                    }
                }
                
                Section {
                    NavigationLink(destination: CurrencySelectionView()) {
                        HStack {
                            Text("Fiat Currency")
                            Spacer()
                            Text(appState.preferredConversionUnit.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Display")
                }
                Section {
                    NavigationLink("About this Release", destination: ReleaseNoteView())
                    Button {
                        if UIApplication.shared.canOpenURL(sourceRepoURL) {
                            UIApplication.shared.open(sourceRepoURL)
                        }
                    } label: {
                        HStack {
                            Text("View source on GitHub")
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        if UIApplication.shared.canOpenURL(faqURL) {
                            UIApplication.shared.open(faqURL)
                        }
                    } label: {
                        HStack {
                            Text("Open FAQ")
                            Spacer()
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        if UIApplication.shared.canOpenURL(mailURL) {
                            UIApplication.shared.open(mailURL)
                        }
                    } label: {
                        HStack {
                            Text("Contact the developer")
                            Spacer()
                            Image(systemName: "envelope")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Information")
                } footer: {
                    VStack {
                        Text("macadamia, \(appVersion)")
                        Text("Privacy is a human right.")
                            .padding(4)
                    }
                    .font(.system(size: 16)) // Adjust the size as needed
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .onTapGesture(count: 3, perform: {
                        withAnimation {
                            hiddenMenuShowing.toggle()
                        }
                    })
                }
                .toolbar(.visible, for: .tabBar)
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState(preview: true, preferredUnit: .usd))
}
