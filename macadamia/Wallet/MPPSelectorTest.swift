//
//  MPPSelectorTest.swift
//  macadamia
//
//  Created by zm on 28.07.25.
//

import SwiftUI

struct MPPSelectorTest: View {
    struct Item: Identifiable {
        let id = UUID()
        let name: String
        var value: Double
    }

    @State private var items: [Item] = [
        .init(name: "Alice", value: 25),
        .init(name: "Bob",   value: 25),
        .init(name: "Carol", value: 25),
    ]

    private func redistribute(changedAt index: Int, to newValue: Double) {
        let clamped = min(max(newValue, 0), 100)
        let oldValue = items[index].value
        let otherIndices = items.indices.filter { $0 != index }
        let othersSum = otherIndices.map { items[$0].value }.reduce(0, +)
        if othersSum > 0 {
            let remaining = max(100 - clamped, 0)
            let factor = remaining / othersSum
            for i in otherIndices {
                items[i].value *= factor
            }
        } else {
            for i in otherIndices {
                items[i].value = 0
            }
        }
        items[index].value = clamped
        let total = items.map(\.value).reduce(0, +)
        if abs(total - 100) > 0.001 {
            items[index].value += 100 - total
        }
    }

    var body: some View {
        List(items.indices, id: \.self) { i in
            HStack {
                Text(items[i].name)
                Slider(
                    value: Binding(
                        get: { items[i].value },
                        set: { redistribute(changedAt: i, to: $0) }
                    ),
                    in: 0...100
                )
                Text("\(Int(round(items[i].value)))%")
            }
            .padding(.vertical, 4)
        }
    }
}

struct PickerTest: View {
    @State var selectedNumber: Int = 0

    var body: some View {
        Menu {
            Picker(selection: $selectedNumber, label: EmptyView()) {
                ForEach(0..<10) {
                    Text("\($0)")
                }
            }
        } label: {
            customLabel
        }
    }

    var customLabel: some View {
        HStack {
            Image(systemName: "paperplane")
            Text(String(selectedNumber))
            Spacer()
            Text("⌵")
                .offset(y: -4)
        }
        .foregroundColor(.white)
        .font(.title)
        .padding()
        .frame(height: 32)
        .background(Color.blue)
        .cornerRadius(16)
    }
}

#Preview {
    PickerTest()
}


#Preview {
    MPPSelectorTest()
}
