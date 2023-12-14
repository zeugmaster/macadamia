//
//  MintRequestView.swift
//  macadamia
//
//  Created by Dario Lass on 14.12.23.
//

import SwiftUI

struct MintRequestView: View {
    @StateObject var viewmodel = MintRequestViewModel()
    
    @State var mintSelection = "one"
    let mints = ["one", "two", "three"]
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("enter amount", text: $viewmodel.numberString)
                        .keyboardType(.numberPad)
                        .monospaced()
                        .multilineTextAlignment(.trailing)
                    Text("sats")
                }
                
                Picker("Mint", selection:$mintSelection) {
                    ForEach(mints, id: \.self) {
                        Text($0)
                    }
                }
            }
        }
        .navigationTitle("Mint")
        .navigationBarTitleDisplayMode(.inline)
        Spacer()
        NavigationLink(destination: Text("bing, like a rocketship")) {
            Text("Request \(Image(systemName: "bolt.fill")) Invoice")
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
                
        }
        .buttonStyle(.bordered)
        .padding()
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: {
            withAnimation {
                
            }
        })
    }
    
}

#Preview {
    MintRequestView()
}


class MintRequestViewModel: ObservableObject {
    @Published var numberString: String = ""
    
    var number: Int? {
        return Int(numberString)
    }
    
}
