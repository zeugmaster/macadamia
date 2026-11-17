//
//  MintDiscoveryDetail.swift
//  macadamia
//

import SwiftUI
import SwiftData
import CashuSwift

/// Overview of a directory-listed mint. Every section comes from one source and is left out when that source has nothing.
struct MintDiscoveryDetail: View {
    let mint: DiscoveredMint

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Wallet> { $0.active == true }) private var wallets: [Wallet]
    @Query private var walletMints: [Mint]

    @State private var uptime: MintDirectory.Uptime?
    @State private var metrics: MintDirectory.Metrics?
    @State private var reviews = [MintDirectory.Review]()
    @State private var loaded = false
    @State private var buttonState = ActionButtonState.idle("")
    @State private var copied = false
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 80

    private var isAdded: Bool {
        DiscoveredMint.addedIDs(in: walletMints).contains(mint.id)
    }

    // Keeps the button through its success animation although the mint already counts as added.
    private var showsAddButton: Bool {
        !isAdded || buttonState.type != .idle
    }

    var body: some View {
        ZStack {
            List {
                header
                stats
                uptimeSection
                about
                capabilities
                details
                reviewSection
                if showsAddButton {
                    Spacer(minLength: 80)
                        .listRowBackground(Color.clear)
                }
            }
            .listSectionSpacing(16)

            if showsAddButton {
                VStack {
                    Spacer()
                    ActionButton(state: $buttonState, hideShadow: true)
                        .actionDisabled(false)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline) // the header carries the name
        .onAppear {
            if buttonState.type == .idle { resetButton() }
        }
        // Loads once; coming back to the tab doesn't reload, only pulling down does.
        .task {
            guard !loaded else { return }
            await loadDirectoryData()
            loaded = !Task.isCancelled
        }
        .refreshable { await loadDirectoryData() }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }

    // MARK: Sections

    private var header: some View {
        Section {
            VStack(spacing: 8) {
                MintIcon(url: mint.iconURL, size: iconSize)
                    .padding(.bottom, 4)
                Text(mint.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Button(action: copyURL) {
                    HStack(spacing: 4) {
                        Text(mint.displayURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy URL")
                if isAdded {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private struct Stat {
        let symbol: String
        let value: String
        let label: LocalizedStringKey
    }

    private var statItems: [Stat] {
        var items = [Stat]()
        if let average = mint.reviews?.average {
            items.append(Stat(symbol: "star.fill",
                              value: average.formatted(.number.precision(.fractionLength(1))), label: "Rating"))
        }
        if let rate = mint.audit?.successRate {
            items.append(Stat(symbol: "checkmark.seal",
                              value: rate.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down)),
                              label: "Audit success"))
        }
        if let latency = metrics?.avgLatencyMs {
            items.append(Stat(symbol: "stopwatch",
                              value: Duration.milliseconds(latency)
                                .formatted(.units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1))),
                              label: "Avg. swap time"))
        }
        return items
    }

    @ViewBuilder
    private var stats: some View {
        let items = statItems
        if !items.isEmpty {
            Section {
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        if index > 0 {
                            Divider()
                                .frame(height: 32)
                        }
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: items[index].symbol)
                                    .imageScale(.small)
                                    .foregroundStyle(.secondary)
                                Text(items[index].value)
                                    .monospacedDigit()
                            }
                            .font(.title3)
                            .fontWeight(.semibold)
                            Text(items[index].label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 14)
                // Same card as DepositQuoteView: drawn by the row, since listRowBackground clips the hairline on device.
                .background {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.primary.opacity(0.08))
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 0.5)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var uptimeSection: some View {
        if let uptime, !uptime.bars.isEmpty {
            let percent = uptime.uptimePercent.map { ($0 / 100).formatted(.percent.precision(.fractionLength(0...1))) }
            Section {
                HStack(spacing: 3) {
                    ForEach(uptime.bars.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: uptime.bars[index].state))
                    }
                }
                .frame(height: 28)
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(percent.map { String(localized: "Up \($0) of the last 24 hours") }
                                    ?? String(localized: "No uptime data for the last 24 hours"))
            } header: {
                HStack {
                    Text("Uptime")
                    Spacer()
                    if let percent {
                        Text(percent)
                    }
                }
            } footer: {
                Text("Hourly checks over the last 24 hours by \(mint.audit?.host.url.host() ?? "")")
            }
        }
    }

    @ViewBuilder
    private var about: some View {
        let short = DiscoveredMint.clean(mint.info?.description)
        let long = DiscoveredMint.clean(mint.info?.descriptionLong)
        let motd = DiscoveredMint.clean(mint.info?.motd)
        if short != nil || long != nil || motd != nil {
            Section("About") {
                if let short {
                    Text(short)
                }
                if let long, long != short {
                    Text(long)
                        .foregroundStyle(.secondary)
                }
                if let motd {
                    Label(motd, systemImage: "megaphone")
                }
            }
        }
    }

    @ViewBuilder
    private var capabilities: some View {
        if let nuts = mint.info?.nuts {
            Section("Capabilities") {
                if let receive = methodNames(nuts.nut04) {
                    LabeledContent("Deposit", value: receive)
                }
                if let send = methodNames(nuts.nut05) {
                    LabeledContent("Withdraw", value: send)
                }
                MintCapabilityTags(nuts: nuts)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        let version = DiscoveredMint.clean(mint.info?.version)
        let units = unitNames
        let contacts = (mint.info?.contact ?? []).filter { DiscoveredMint.clean($0.info) != nil }
        if version != nil || units != nil || !contacts.isEmpty {
            Section("Details") {
                if let version {
                    LabeledContent("Software", value: version)
                }
                if let units {
                    LabeledContent("Units", value: units)
                }
                ForEach(contacts.indices, id: \.self) { index in
                    LabeledContent(contacts[index].method.capitalized) {
                        Text(contacts[index].info)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if !reviews.isEmpty {
            Section {
                ForEach(reviews.prefix(10)) { review in
                    ReviewRow(review: review)
                }
            } header: {
                HStack {
                    Text("Reviews")
                    Spacer()
                    if let count = mint.reviews?.count {
                        Text(count, format: .number)
                    }
                }
            } footer: {
                Text("Reviews are published on Nostr and collected by \(mint.reviews?.host.host() ?? "")")
            }
        }
    }

    // MARK: Helpers

    private func loadDirectoryData() async {
        async let audit: Void = loadAuditData()
        async let reviews: Void = loadReviews()
        _ = await (audit, reviews)
    }

    // Failed or cancelled fetches keep what is on screen.
    private func loadAuditData() async {
        guard let audit = mint.audit else { return }
        async let uptime = try? MintDirectory.uptime(audit)
        async let metrics = try? MintDirectory.metrics(audit)
        let result = await (uptime, metrics)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .default) {
            self.uptime = result.0 ?? self.uptime
            self.metrics = result.1 ?? self.metrics
        }
    }

    private func loadReviews() async {
        guard let summary = mint.reviews, let result = try? await MintDirectory.reviews(summary),
              !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .default) {
            reviews = result.filter { $0.rating != nil || DiscoveredMint.clean($0.content) != nil }
        }
    }

    private func methodNames(_ nut: CashuSwift.Mint.Info.NutInfo?) -> String? {
        guard nut?.disabled != true else { return nil }
        var seen = Set<String>()
        let names = (nut?.methods ?? []).map(\.displayName).filter { seen.insert($0).inserted }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    private var unitNames: String? {
        var seen = Set<String>()
        let units = (mint.info?.nuts?.nut04?.methods ?? []).map { $0.unit.uppercased() }.filter { seen.insert($0).inserted }
        return units.isEmpty ? nil : units.joined(separator: ", ")
    }

    private func color(for state: String) -> Color {
        switch state {
        case "OK": .successGreen
        case "ERROR": .failureRed
        default: .gray.opacity(0.3)
        }
    }

    private func copyURL() {
        UIPasteboard.general.string = mint.url.absoluteString
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }

    private func resetButton() {
        buttonState = .idle(String(localized: "Add Mint"), action: add)
    }

    private func add() {
        guard let wallet = wallets.first else { return }
        buttonState = .loading()
        Task {
            do {
                try await MintManagerView.addMint(url: mint.url, to: wallet, in: modelContext)
                buttonState = .success(String(localized: "Added"))
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            } catch {
                logger.error("could not add discovered mint \(mint.url.absoluteString): \(error)")
                buttonState = .fail()
                currentAlert = AlertDetail(with: error)
                showAlert = true
                try? await Task.sleep(for: .seconds(2))
                resetButton()
            }
        }
    }
}

private struct ReviewRow: View {
    let review: MintDirectory.Review

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let rating = review.rating {
                    Stars(value: Double(rating))
                        .font(.caption)
                }
                Spacer()
                Text(review.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let text = DiscoveredMint.clean(review.content) {
                Text(text)
            }
            Text(review.npub)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        MintDiscoveryDetail(mint: .preview)
    }
    .previewEnvironment()
}
#endif
