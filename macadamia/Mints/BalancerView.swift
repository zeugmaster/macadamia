//
//  BalancerView.swift
//  macadamia
//
//  Created by zm on 21.09.25.
//

import SwiftUI
import SwiftData

struct BalancerView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    @State private var buttonState = ActionButtonState.idle("Select")
//    @State private var
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    var body: some View {
        ZStack {
            List {
                ForEach(mints) { mint in
                    VStack(alignment: .leading) {
                        Button {
                            // toggle
                        } label: {
                            Text(mint.displayName)
                        }
                        
                    }
                }
                
                Spacer(minLength: 60)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
            }
        }
    }
    
}

import SwiftUI

struct PercentSlidersSelectable: View {
    @State private var values: [Double] = [25, 25, 25, 25]
    @State private var active: Set<Int> = [0, 1, 2, 3]

    var body: some View {
        NavigationView {
            List {
                ForEach(values.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                toggleSelection(i)
                            }
                        } label: {
                            Image(systemName: active.contains(i) ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large)
                        }
                        Text("Item \(i + 1)")
                            .frame(width: 80, alignment: .leading)
                        SmallKnobSlider(value: binding(for: i), range: 0...100)
                            .disabled(!active.contains(i))
                            .opacity(active.contains(i) ? 1 : 0.35)
                        Text("\(Int(round(values[i])))%")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            toggleSelection(i)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Text("Active total \(Int(round(activeTotal)))%")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Percent Allocations")
            .onAppear {
                equalSplitActive()
            }
        }
    }

    private var activeTotal: Double {
        values.enumerated().filter { active.contains($0.offset) }.map { $0.element }.reduce(0, +)
    }

    private func binding(for i: Int) -> Binding<Double> {
        Binding(
            get: { values[i] },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    if active.contains(i) {
                        redistributeActive(changed: i, to: newValue)
                    }
                }
            }
        )
    }

    private func toggleSelection(_ i: Int) {
        if active.contains(i) {
            guard active.count > 1 else { return }
            active.remove(i)
            values[i] = 0
            equalSplitActive()
        } else {
            active.insert(i)
            equalSplitActive()
        }
    }

    private func equalSplitActive() {
        let count = active.count
        guard count > 0 else { return }
        let share = 100.0 / Double(count)
        for j in values.indices {
            values[j] = active.contains(j) ? share : 0
        }
    }

    private func redistributeActive(changed i: Int, to newValue: Double) {
        let clamped = min(100, max(0, newValue))
        if !active.contains(i) { return }
        let actives = Array(active)
        if actives.count == 1 {
            values[i] = 100
            return
        }
        let oldOthers = actives.filter { $0 != i }.map { values[$0] }.reduce(0, +)
        values[i] = clamped
        let targetOthers = 100 - clamped
        if oldOthers == 0 {
            let share = targetOthers / Double(actives.count - 1)
            for j in actives where j != i { values[j] = share }
        } else {
            let scale = targetOthers / oldOthers
            for j in actives where j != i { values[j] *= scale }
        }
        for j in values.indices where !active.contains(j) { values[j] = 0 }
    }
}

#Preview {
    PercentSlidersSelectable()
}

import SwiftUI

struct SmallKnobSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )

        // smaller circular knob
        let knobSize: CGFloat = 6
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: knobSize, height: knobSize))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: knobSize, height: knobSize)))
        }
        slider.setThumbImage(image, for: .normal)
        slider.setThumbImage(image, for: .highlighted)

        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.value = Float(value)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: SmallKnobSlider
        init(_ parent: SmallKnobSlider) { self.parent = parent }
        @objc func changed(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
    }
}

struct Demo: View {
    @State private var val: Double = 0.5
    var body: some View {
        SmallKnobSlider(value: $val)
            .padding()
    }
}


