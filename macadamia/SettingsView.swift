//
//  SettingView.swift
//  macadamia
//
//  Created by Dario Lass on 13.12.23.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    
    let sourceRepoURL = URL(string: "https://github.com/zeugmaster/macadamia")!
    
    var appVersion:String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: MintManagerView()) { Text("Mints") }
                    NavigationLink(destination: MnemonicView()) { Text("Show Seed Phrase") }
                    NavigationLink(destination: RestoreView()) { Text("Restore") }
                } header: {
                    Text("cashu")
                }
                Section {
                    NavigationLink(destination: RelayManagerView()) { Text("Relays") }
                    } header: {
                        Text("nostr")
                    }
                Section {
                    HStack {
                        Text("View source on Github")
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        if UIApplication.shared.canOpenURL(sourceRepoURL) {
                            UIApplication.shared.open(sourceRepoURL)
                        }
                    }
                    NavigationLink(destination: Text("Acknowledgments")) { Text("Acknowledgments") }
                } header: {
                    Text("Information")
                } footer: {
                    Text("macadamia, \(appVersion)")
                        .font(.system(size: 16)) // Adjust the size as needed
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
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
