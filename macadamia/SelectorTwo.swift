//
//  SelectorTwo.swift
//  macadamia
//
//  Created by zm on 28.03.24.
//

import SwiftUI

struct SelectorTwo: View {
    @ObservedObject var vm = SelectorTwoViewModel()
    
    var body: some View {
        List(vm.mints, id:\.self) { mint in
            Button(action: {
                if !vm.selectedMints.contains(mint) {
                    vm.selectedMints.insert(mint)
                } else {
                    vm.selectedMints.remove(mint)
                }
            }, label: {
                HStack {
                    Text(mint)
                    Spacer()
                    if vm.selectedMints.contains(mint) {
                        Image(systemName: "checkmark")
                    }
                }
            })
        }
        Button(action: {
            print("yank")
        }, label: {
            Text("YANK")
        })
        .disabled(vm.selectedMints.isEmpty)
    }
}

#Preview {
    SelectorTwo()
}

@MainActor
class SelectorTwoViewModel:ObservableObject {
    
    @Published var mints = ["one", "two", "three", "four"]
    
    @Published var selectedMints:Set<String> = []
    
    
}
