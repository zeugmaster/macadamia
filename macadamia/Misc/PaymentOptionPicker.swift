import SwiftUI

struct PaymentOptionPicker: View {
    let direction: PaymentDirection
    let label: String
    let allowedMethods: Set<PaymentMethodKind>?
    let excludedMethods: Set<PaymentMethodKind>?
    let hidesWhenSingleOption: Bool

    @Binding var selectedMint: Mint?
    @Binding var selectedOption: PaymentOption?

    @State private var options = [PaymentOption]()
    @State private var isLoading = false

    init(direction: PaymentDirection,
         label: String = String(localized: "Payment"),
         selectedMint: Binding<Mint?>,
         selectedOption: Binding<PaymentOption?>,
         allowedMethods: Set<PaymentMethodKind>? = nil,
         excludedMethods: Set<PaymentMethodKind>? = nil,
         hidesWhenSingleOption: Bool = true) {
        self.direction = direction
        self.label = label
        self._selectedMint = selectedMint
        self._selectedOption = selectedOption
        self.allowedMethods = allowedMethods
        self.excludedMethods = excludedMethods
        self.hidesWhenSingleOption = hidesWhenSingleOption
    }

    var body: some View {
        Group {
            if selectedMint == nil {
                EmptyView()
            } else if isLoading {
                HStack {
                    Text(label)
                    Spacer()
                    ProgressView()
                }
            } else if options.isEmpty {
                HStack {
                    Text(label)
                    Spacer()
                    Text("No supported methods")
                        .foregroundStyle(.secondary)
                }
            } else if distinctOptionCount <= 1 {
                if hidesWhenSingleOption {
                    EmptyView()
                } else {
                    HStack {
                        Text(label)
                        Spacer()
                        Text(selectedOption?.displayName ?? options.first?.displayName ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Picker(label, selection: $selectedOption) {
                    ForEach(options) { option in
                        Text(option.displayName).tag(Optional(option))
                    }
                }
            }
        }
        .task(id: refreshID) {
            await refreshOptions()
        }
        .onChange(of: selectedMint?.mintID) { _, _ in
            Task { await refreshOptions() }
        }
    }

    private var refreshID: String {
        let allowed = allowedMethods?.map(\.rawValue).sorted().joined(separator: ",") ?? "all"
        let excluded = excludedMethods?.map(\.rawValue).sorted().joined(separator: ",") ?? "none"
        return "\(selectedMint?.mintID.uuidString ?? "nil")|\(direction.rawValue)|\(allowed)|\(excluded)"
    }

    private var distinctOptionCount: Int {
        Set(options.map { "\($0.unitCode)|\($0.method.rawValue)" }).count
    }

    @MainActor
    private func refreshOptions() async {
        guard let selectedMint else {
            options = []
            selectedOption = nil
            return
        }

        isLoading = true
        let loadedOptions = await selectedMint.supportedPaymentOptions(direction: direction)
        var filteredOptions: [PaymentOption]
        if let allowedMethods {
            filteredOptions = loadedOptions.filter { allowedMethods.contains($0.method) }
        } else {
            filteredOptions = loadedOptions
        }
        if let excludedMethods {
            filteredOptions = filteredOptions.filter { !excludedMethods.contains($0.method) }
        }

        let previous = selectedOption
        options = filteredOptions
        selectedOption = filteredOptions.preferredOption(preserving: previous)
        isLoading = false
    }
}
