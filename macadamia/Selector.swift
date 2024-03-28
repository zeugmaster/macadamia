//
//  Selector.swift
//  macadamia
//
//  Created by zm on 28.03.24.
//

import SwiftUI

class Item: Identifiable, ObservableObject, CustomStringConvertible {
    let id: String
    @Published var isSelected: Bool

    init(id: String, isSelected: Bool = false) {
        self.id = id
        self.isSelected = isSelected
    }
    
    var description: String {
        id
    }
}

struct ItemView: View {
    @ObservedObject var item: Item

    var body: some View {
        Button(action: {
            item.isSelected.toggle()
        }, label: {
            HStack {
                Text(item.id)
                Spacer()
                if item.isSelected {
                    Image(systemName: "checkmark")
                }
            }
        })
    }
}

class ViewModel: ObservableObject {
    @Published var items: [Item]
    
    init(items: [Item] = []) {
        self.items = [
            .init(id: "test1", isSelected: true),
            .init(id: "ding"),
            .init(id: "dong", isSelected: true)
        ]
    }
    
    func yank() {
        print(items.filter({$0.isSelected == true}))
    }
    
    var listEmpty:Bool {
        let result = items.filter({$0.isSelected == true}).isEmpty
        print(result)
        return result
    }
}

struct SelContentView: View {
    @ObservedObject var viewModel = ViewModel()

    var body: some View {
        List(viewModel.items) { item in
            ItemView(item: item)
        }
        Button(action: {
            viewModel.yank()
        }, label: {
            Text("YANK")
        })
        .disabled(viewModel.listEmpty)
    }
}


#Preview {
    SelContentView()
}
