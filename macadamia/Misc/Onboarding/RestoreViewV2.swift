//
//  RestoreView.swift
//  macadamia
//
//  Created by zm on 03.04.26.
//

import SwiftUI
import CashuSwift

let dummyMintUrls = [
    URL(string: "https://testmint.macadamia.cash")!,
    URL(string: "https://testnut.cashu.space")!,
    URL(string: "https://success.fake.macadamia.cash")!
]

// MARK: - Per-Row Model

@MainActor @Observable
class MintRow: Identifiable {
    let id = UUID()
    let url: URL
    var isSelected: Bool = true
    var status: LoadStatus = .idle

    enum LoadStatus {
        case idle, loading, loaded(CashuSwift.Mint), failed
    }

    var isLoaded: Bool {
        if case .loaded = status { return true }
        return false
    }

    init(url: URL) {
        self.url = url
    }
}

// MARK: - View Model

@MainActor @Observable
class RestoreViewModel {
    var rows = [MintRow]()
    var isDiscovering = true

    var emptySelection: Bool {
        !rows.contains(where: \.isSelected)
    }
    
    func discover(seed: [String]) async {
        // TODO: replace with real mint discovery from seed
        try? await Task.sleep(for: .seconds(2))
        let urls = dummyMintUrls
        let newRows = urls.map { MintRow(url: $0) }
        withAnimation {
            rows.append(contentsOf: newRows)
            isDiscovering = false
        }
        await loadAll(newRows)
    }

    #warning ("needs proper input sanitation and convenience ")
    func addManually(_ urlString: String) {
        guard let url = URL(string: "https://\(urlString)") else { return }
        let row = MintRow(url: url)
        withAnimation { rows.append(row) }
        Task { await load(row) }
    }

    func loadAll(_ rows: [MintRow]) async {
        await withTaskGroup(of: Void.self) { group in
            for row in rows {
                group.addTask { await self.load(row) }
            }
        }
    }

    private func load(_ row: MintRow) async {
        row.status = .loading
        do {
            let url = row.url
            let mint = try await CashuSwift.loadMint(url: url)
            withAnimation { row.status = .loaded(mint) }
        } catch {
            withAnimation { row.status = .failed }
        }
    }
}

// MARK: - Restore View

struct RestoreViewV2: View {
    let seed: [String]
    let onRestore: (Wallet) -> Void
    
    @State private var vm = RestoreViewModel()
    @State private var mintUrlInput = ""
    
    @State private var restoreProgress:Double? = nil

    var body: some View {
        List {
            Section {
                if vm.isDiscovering {
                    HStack {
                        Text("Discovering mints...")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                    .listRowBackground(Color.primary.opacity(0.08))
                }

                ForEach(vm.rows) { row in
                    MintRowView(row: row)
                        .listRowBackground(Color.primary.opacity(0.08))
                }

                HStack {
                    Image(systemName: "plus")
                    TextField("", text: $mintUrlInput, prompt: Text("mint.example.com"))
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            let input = mintUrlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !input.isEmpty else { return }
                            vm.addManually(input)
                            mintUrlInput = ""
                        }
                }
                .listRowBackground(Color.primary.opacity(0.08))
            }
            .lineLimit(1)
            
            Section {
                Text(seed[0] + " " + seed[1] + " ***** **** ******** **** ****** ***** ***** **** **** *******")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospaced()
                    .listRowBackground(Color.primary.opacity(0.08))
            }
            
            // TODO: add wallet reuse warning
            
            Section {
                Button {
                    restore()
                } label: {
                    HStack {
                        Text("Restore Wallet")
                    }
                }
                .listRowBackground(Color.primary.opacity(0.08))
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            await vm.discover(seed: seed)
        }
    }
    
    private func restore() {
        print("start restore process")
    }
}

// MARK: - Mint Row View

struct MintRowView: View {
    @Bindable var row: MintRow

    var body: some View {
        Button {
            withAnimation { row.isSelected.toggle() }
        } label: {
            HStack {
                Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                Text(row.url.host() ?? row.url.absoluteString)
                Spacer()
                statusIndicator
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch row.status {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
        case .loaded:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview {
    ZStack {
        Rectangle().fill(Color.black.gradient)
        RestoreViewV2(seed: dummySeed) { wallet in
            print(String(describing: wallet))
        }
    }
}
