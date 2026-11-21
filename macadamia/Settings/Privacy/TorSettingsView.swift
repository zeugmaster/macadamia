import SwiftUI

struct TorSettingsView: View {
    @ObservedObject private var network = NetworkController.shared

    var body: some View {
        List {
            Section {
                TorOnlyToggle()
            } footer: {
                Text("Use Tor for all connections made by macadamia. When off, onion addresses still use Tor and other addresses connect directly.")
            }
            if network.torOnly || network.torState != .stopped {
                Section { TorStatusView() }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TorOnlyToggle: View {
    @ObservedObject private var network = NetworkController.shared

    var body: some View {
        Toggle("Tor only", isOn: Binding(get: { network.torOnly }, set: { enabled in
            network.setTorOnly(enabled)
            if enabled { TorRuntime.shared.resume() }
        }))
    }
}

struct TorStatusView: View {
    @ObservedObject private var network = NetworkController.shared

    var body: some View {
        HStack(spacing: 8) {
            if network.torState == .connecting || network.torState == .reconnecting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: network.torState == .connected ? "checkmark.shield" : "network")
            }
            Text(network.torState.label)
            if network.torState == .unavailable {
                Spacer()
                Button("Retry") { TorRuntime.shared.resume() }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
