//
//  SettingView.swift
//  macadamia
//
//  Created by Dario Lass on 13.12.23.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView() {
            NavigationLink(destination: Text("Destination")) { Text("Navigate") }
        }
    }
}

#Preview {
    SettingsView()
}
