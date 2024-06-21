//
//  AirNutSettingsView.swift
//  macadamia
//
//  Created by zm on 20.06.24.
//

import SwiftUI

struct AirNutSettingsView: View {
    
    @State var screenName:String = ""
    @FocusState var textfieldInFocus
    
    var body: some View {
        Form {
            TextField("Enter Screen name", text: $screenName)
                .focused($textfieldInFocus)
        }
        .onAppear(perform: {
            textfieldInFocus = true
        })
        .onDisappear(perform: {
            #warning("Needs to save to defaults!")
        })
    }
}

#Preview {
    AirNutSettingsView()
}
