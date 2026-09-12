import BIP39
import OSLog
import SwiftData
import SwiftUI

fileprivate let mnemonicLogger = Logger(subsystem: "macadamia", category: "MnemonicView")

struct MnemonicView: View {

    private enum BackupPhase {
        case idle, running, succeeded, failed
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @ObservedObject private var backupStatus = MintListBackupStatus.shared

    @State private var isCopied = false
    @State private var backupPhase: BackupPhase = .idle

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var mnemonic: [String] {
        activeWallet?.mnemonic.components(separatedBy: " ") ?? []
    }

    private var visibleMints: [Mint] {
        (activeWallet?.mints ?? [])
            .filter { $0.hidden == false }
            .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
    }

    /// True while this view's own backup or one triggered elsewhere
    /// (e.g. after adding a mint) is still waiting for a relay.
    private var isBackingUp: Bool {
        if backupPhase == .running { return true }
        guard let activeWallet else { return false }
        return backupStatus.isBackingUp(activeWallet)
    }

    private var lastBackup: Date? {
        activeWallet.flatMap { backupStatus.lastBackup(for: $0) }
    }

    func copyMnemonic() {
        UIPasteboard.general.string = mnemonic.joined(separator: " ")
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(mnemonic.enumerated()), id: \.offset) { (index, word) in
                    HStack {
                        Text("\(index + 1).")
                            .frame(minWidth: 26, alignment: .trailing)
                        Text(word)
                    }
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            } header: {
                Text("12 Word backup seed phrase")
            }
            Section {
                Button {
                    copyToClipboard()
                } label: {
                    HStack {
                        if isCopied {
                            Text("Copied!")
                                .transition(.opacity)
                        } else {
                            Text("Copy to clipboard")
                                .transition(.opacity)
                        }
                        Spacer()
                        Image(systemName: "list.clipboard")
                    }
                }
            }
            Section {
                HStack {
                    switch visibleMints.count {
                    case 0:
                        Text("No mints yet")
                    case 1:
                        Text("1 Mint")
                    case let n:
                        Text("\(n) Mints")
                    }
                }
                .foregroundStyle(.secondary)
                Button {
                    backUpNow()
                } label: {
                    HStack {
                        backupLabel
                        Spacer()
                        backupIndicator
                    }
                    .foregroundStyle(backupPhase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                }
                .disabled(activeWallet == nil || visibleMints.isEmpty)
                .animation(.default, value: isBackingUp)
            } header: {
                Text("Mints")
            } footer: {
                backupFooter
            }
        }
    }

    @ViewBuilder
    private var backupLabel: some View {
        if isBackingUp {
            Text("Backing up…")
                .transition(.opacity)
        } else {
            switch backupPhase {
            case .succeeded:
                Text("Backed up")
                    .transition(.opacity)
            case .failed:
                Text("Backup failed")
                    .transition(.opacity)
            case .idle, .running:
                Text("Back up now")
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var backupIndicator: some View {
        if isBackingUp {
            ProgressView()
                .controlSize(.small)
                .transition(.opacity)
        } else {
            switch backupPhase {
            case .succeeded:
                Image(systemName: "checkmark")
                    .transition(.opacity)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .transition(.opacity)
            case .idle, .running:
                Image(systemName: "arrow.up.circle")
                    .transition(.opacity)
            }
        }
    }

    private var backupFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lastBackup {
                // Ticks aligned to the backup time, so the text flips exactly at 60 s, 120 s, ...
                TimelineView(.periodic(from: lastBackup, by: 60)) { context in
                    if context.date.timeIntervalSince(lastBackup) < 60 {
                        Text("Last backed up to nostr less than a minute ago")
                    } else {
                        Text("Last backed up to nostr \(lastBackup, format: .relative(presentation: .numeric))")
                    }
                }
            } else {
                Text("Not yet backed up to nostr.")
            }
            Text("The list is encrypted with your seed phrase and stored on nostr, so restoring the wallet also restores its mints.")
        }
        .animation(.default, value: lastBackup)
    }

    @MainActor
    private func backUpNow() {
        guard let wallet = activeWallet, backupPhase == .idle, !isBackingUp else { return }
        withAnimation { backupPhase = .running }
        Task {
            do {
                try await MintListBackup.backUp(wallet)
                withAnimation { backupPhase = .succeeded }
            } catch {
                mnemonicLogger.warning("manual mint list backup failed: \(error)")
                withAnimation { backupPhase = .failed }
            }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { backupPhase = .idle }
        }
    }

    func copyToClipboard() {
        // Perform the actual copy operation here
        copyMnemonic()

        // Change button text with animation
        withAnimation {
            isCopied = true
        }

        // Revert button text after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#if DEBUG
#Preview {
    MnemonicView()
        .previewEnvironment()
}
#endif
