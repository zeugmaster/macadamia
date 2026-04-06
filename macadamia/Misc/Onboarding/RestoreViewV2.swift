//
//  RestoreView.swift
//  macadamia
//
//  Created by zm on 03.04.26.
//

import SwiftUI
import CashuSwift
import BIP39
import OSLog

fileprivate let restoreViewLogger = Logger(subsystem: "macadamia", category: "RestoreView")

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
        defer {
            withAnimation { isDiscovering = false }
        }

        do {
            guard let mnemonic = try? Mnemonic(phrase: seed) else {
                restoreViewLogger.warning("Could not derive mnemonic from seed words for mint discovery.")
                return
            }
            let seedHex = String(bytes: mnemonic.seed)
            let urls = try await MintListBackup.retrieve(seedHex: seedHex)

            guard !urls.isEmpty else {
                restoreViewLogger.info("Nostr backup returned empty mint list.")
                return
            }

            let newRows = urls.map { MintRow(url: $0) }
            withAnimation {
                rows.append(contentsOf: newRows)
            }
            await loadAll(newRows)
        } catch {
            restoreViewLogger.info("No mint list backup found on Nostr: \(error). User can add mints manually.")
        }
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

    @State private var restoreProgress: Double = 0.0
    @State private var restoreInProgress = false

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
                    Image(systemName: "pencil")
                        .bold()
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
                if restoreInProgress {
                    GeometryReader { geo in
                        Capsule()
                            .fill(.primary.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.primary)
                                    .frame(width: geo.size.width * restoreProgress)
                            }
                            .clipped()
                    }
                    .frame(height: 4)
                    .animation(.easeInOut, value: restoreProgress)
                    .listRowBackground(Color.primary.opacity(0.08))
                }
            }

            // TODO: add wallet reuse warning

            Section {
                Button {
                    restore()
                } label: {
                    HStack {
                        Spacer()
                        if restoreInProgress {
                            ProgressView()
                        } else {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        Text("Restore")
                        Spacer()
                    }
                    .padding(12)
                    .fontWeight(.medium)
                    .background(RoundedRectangle(cornerRadius: 20)
                        .fill(Color.primary.gradient.opacity(0.8))
                        .stroke(.primary, style: StrokeStyle())
                        .opacity(0.15))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                .disabled(restoreInProgress || vm.emptySelection)
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            await vm.discover(seed: seed)
        }
    }

    private func restore() {
        guard !restoreInProgress else { return }

        // Collect selected, loaded CashuSwift mints
        let selectedMints: [CashuSwift.Mint] = vm.rows.compactMap { row in
            guard row.isSelected, case .loaded(let mint) = row.status else { return nil }
            return mint
        }

        guard !selectedMints.isEmpty else { return }

        guard let mnemonic = try? Mnemonic(phrase: seed) else {
            restoreViewLogger.error("Could not create mnemonic from seed phrase during restore.")
            return
        }

        let seedHex = String(bytes: mnemonic.seed)
        let totalMints = Double(selectedMints.count)

        withAnimation { restoreInProgress = true }

        Task { @MainActor in
            var results = [MintRestoreResult]()

            for await result in macadamiaApp.restoreSequence(mints: selectedMints, seed: seedHex) {
                results.append(result)
                withAnimation {
                    restoreProgress = Double(results.count) / totalMints
                }
            }

            let assembled = macadamiaApp.assembleRestoredWallet(
                from: results,
                mnemonic: mnemonic
            )

            restoreInProgress = false
            onRestore(assembled.wallet)
        }
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
            .ignoresSafeArea()
        RestoreViewV2(seed: dummySeed) { wallet in
            print(String(describing: wallet))
        }
    }
}
