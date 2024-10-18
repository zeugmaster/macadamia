import SwiftUI
import UIKit

struct SettingsView: View {
    let sourceRepoURL = URL(string: "https://github.com/zeugmaster/macadamia")!
    let mailURL = URL(string: "mailto:contact@macadamia.cash")!
    
    @State var hiddenMenuShowing:Bool = false

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: MnemonicView()) { Text("Show Seed Phrase") }
                    NavigationLink(destination: EmptyView()) { Text("Restore") }.disabled(true)
                    NavigationLink(destination: DrainView()) { Text("Drain Wallet") }
                    if hiddenMenuShowing {
                        NavigationLink(destination: MintListView()) { Text("Proof Database") }
                    }
                } header: {
                    Text("cashu")
                }
                Section {
                    NavigationLink(destination: RelayManagerView()) { Text("Relays") }
                } header: {
                    Text("nostr")
                }
                Section {
                    NavigationLink("About this Release", destination: ReleaseNoteView())
                    
                    Button {
                        if UIApplication.shared.canOpenURL(sourceRepoURL) {
                            UIApplication.shared.open(sourceRepoURL)
                        }
                    } label: {
                        HStack {
                            Text("View source on Github")
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
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
}
