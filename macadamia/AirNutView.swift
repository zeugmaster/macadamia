//
//  AirNut.swift
//  macadamia
//
//  Created by zm on 20.06.24.
//

import SwiftUI

struct AirNutView: View {
    @ObservedObject var vm:AirNutViewModel
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

class AirNutViewModel: ObservableObject {
    @Published var navPath:NavigationPath?
    
    init(navPath:NavigationPath? = nil) {
        self.navPath = navPath
    }
}

#Preview {
    AirNutView(vm: AirNutViewModel())
}
