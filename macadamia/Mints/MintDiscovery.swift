//
//  MintDiscovery.swift
//  macadamia
//
//  Created by zm on 17.11.26.
//

import SwiftUI
import SwiftData
import CashuSwift

// MARK: - Model

/// A mint listed by the review directory, the auditor, or both. A missing source leaves its summary nil.
struct DiscoveredMint: Identifiable, Hashable, Sendable {
    let id: String
    var url: URL
    var name: String
    var info: CashuSwift.Mint.Info?
    var reviews: Reviews?
    var audit: Audit?

    struct Reviews: Sendable {
        let host: URL
        let id: String
        let count: Int
        let average: Double?
    }

    struct Audit: Sendable {
        let host: MintDirectory.AuditorHost
        let id: Int
        let healthy: Bool
        let successes: Int
        let errors: Int

        /// Counts mint-caused failures only; the auditor's own errors (like an empty test wallet) are excluded.
        var successRate: Double? {
            successes + errors > 0 ? Double(successes) / Double(successes + errors) : nil
        }
    }

    init?(url string: String, name: String?, info: String?) {
        guard let url = URL(string: string), url.host() != nil else { return nil }
        self.id = Self.key(for: url)
        self.url = url
        self.info = info.flatMap { try? JSONDecoder().decode(CashuSwift.Mint.Info.self, from: Data($0.utf8)) }
        self.name = Self.clean(self.info?.name) ?? Self.clean(name) ?? url.host() ?? string
    }

    // Navigation identity only: a reloaded listing of the same mint is the same destination.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var iconURL: URL? { info?.iconUrl.flatMap(URL.init(string:)) }

    var displayURL: String {
        (url.host() ?? url.absoluteString) + (url.path().count > 1 ? url.path() : "")
    }

    /// Smoothed rating (two phantom 3★ reviews, so a single 5★ can't top the list) scaled by audit success.
    var score: Double {
        var rating = 3.0
        if let reviews, let average = reviews.average {
            rating = (average * Double(reviews.count) + 6) / Double(reviews.count + 2)
        }
        return rating / 5 * (audit?.successRate ?? 0.9)
    }

    /// Case-insensitive so `/Bitcoin` and `/bitcoin` from different directories meet.
    static func key(for url: URL) -> String {
        var key = url.absoluteString.lowercased()
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }

    static func addedIDs(in mints: [Mint]) -> Set<String> {
        Set(mints.filter { !$0.hidden && $0.wallet?.active == true }.map { key(for: $0.url) })
    }

    /// Some mints publish their name and description wrapped in literal quotes.
    static func clean(_ text: String?) -> String? {
        let cleaned = text?.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    /// Auditor entries keep their URL and info, since the auditor has swapped against that exact URL.
    /// Of duplicate review listings the one with the most reviews wins. Failing mints sink to the bottom,
    /// the rest are ranked by score.
    static func merge(reviewed: [DiscoveredMint], audited: [DiscoveredMint]) -> [DiscoveredMint] {
        var mints = Dictionary(audited.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for mint in reviewed where (mints[mint.id]?.reviews?.count ?? -1) < (mint.reviews?.count ?? 0) {
            var merged = mint
            if let audited = mints[mint.id], audited.audit != nil {
                merged = audited
                merged.reviews = mint.reviews
            }
            mints[mint.id] = merged
        }
        return mints.values.sorted { a, b in
            let aDown = a.audit?.healthy == false, bDown = b.audit?.healthy == false
            if aDown != bDown { return bDown }
            if a.score != b.score { return a.score > b.score }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - Directories

/// Public mint directories. Each source lists its hosts in order of preference and falls through to the
/// next when one is unreachable; a source without any reachable host contributes nothing.
enum MintDirectory {
    static let reviewHosts = [URL(string: "https://imf.gg")!]

    static let auditorHosts = [
        AuditorHost(url: URL(string: "https://auditor.regtest.macadamia.cash")!, functionSuffix: "5929181479826419594"),
    ]

    /// The auditor is a Leptos app: its API is server functions whose path ends in a per-deployment hash.
    /// shortcut: the hash is pinned per host, update it if the deployment changes or give the endpoints fixed names.
    struct AuditorHost: Sendable {
        let url: URL
        let functionSuffix: String
    }

    struct Page<Entry: Decodable & Sendable>: Decodable, Sendable {
        let mints: [Entry]
        let total: Int
    }

    struct ReviewedEntry: Decodable, Sendable {
        let id: String
        let url: String
        let name: String?
        let info: String?
        let reviewCount: Int
        let reviewAvg: Double?
    }

    struct AuditedEntry: Decodable, Sendable {
        let id: Int
        let url: String
        let name: String?
        let info: String?
        let state: String
        let nErrors: Int
        let nMints: Int
        let nMelts: Int
    }

    struct Uptime: Decodable, Sendable {
        let uptimePercent: Double?
        let bars: [Bar]

        struct Bar: Decodable, Sendable {
            let state: String
        }
    }

    struct Metrics: Decodable, Sendable {
        let avgLatencyMs: Double?
    }

    struct Review: Decodable, Identifiable, Sendable {
        let eventId: String
        let npub: String
        let rating: Int?
        let content: String
        let createdAt: Date

        var id: String { eventId }
    }

    /// Empty only when no directory could be reached.
    static func load() async -> [DiscoveredMint] {
        async let reviewed = firstAvailable(reviewHosts, reviewedMints)
        async let audited = firstAvailable(auditorHosts, auditedMints)
        let (reviews, audits) = await (reviewed, audited)
        return DiscoveredMint.merge(reviewed: reviews ?? [], audited: audits ?? [])
    }

    static func reviewedMints(at host: URL) async throws -> [DiscoveredMint] {
        let entries = try await allPages { page -> Page<ReviewedEntry> in
            try await get(host.appending(path: "api/mints").appending(queryItems: [URLQueryItem(name: "page", value: String(page))]))
        }
        return entries.compactMap { entry in
            var mint = DiscoveredMint(url: entry.url, name: entry.name, info: entry.info)
            mint?.reviews = .init(host: host, id: entry.id, count: entry.reviewCount, average: entry.reviewAvg)
            return mint
        }
    }

    static func auditedMints(at host: AuditorHost) async throws -> [DiscoveredMint] {
        let entries = try await allPages { page -> Page<AuditedEntry> in
            try await call(host, "search_mints", "search=&page=\(page)")
        }
        return entries.compactMap { entry in
            var mint = DiscoveredMint(url: entry.url, name: entry.name, info: entry.info)
            mint?.audit = .init(host: host, id: entry.id, healthy: entry.state != "ERROR",
                                successes: entry.nMints + entry.nMelts, errors: entry.nErrors)
            return mint
        }
    }

    static func uptime(_ audit: DiscoveredMint.Audit) async throws -> Uptime {
        try await call(audit.host, "get_mint_uptime", "id=\(audit.id)")
    }

    static func metrics(_ audit: DiscoveredMint.Audit) async throws -> Metrics {
        try await call(audit.host, "get_mint_metrics", "id=\(audit.id)")
    }

    static func reviews(_ summary: DiscoveredMint.Reviews) async throws -> [Review] {
        struct Response: Decodable { let reviews: [Review] }
        let response: Response = try await get(summary.host.appending(path: "api/mints/\(summary.id)/reviews"))
        return response.reviews.sorted { $0.createdAt > $1.createdAt }
    }

    /// Tries each host in order and returns the first answer, or nil when none respond.
    static func firstAvailable<Host, Result>(_ hosts: [Host],
                                             _ fetch: (Host) async throws -> Result) async -> Result? {
        for host in hosts {
            do {
                return try await fetch(host)
            } catch {
                logger.warning("mint directory \(String(describing: host)) unavailable: \(error)")
            }
        }
        return nil
    }

    private static func allPages<Entry>(_ fetch: (Int) async throws -> Page<Entry>) async throws -> [Entry] {
        var entries = [Entry]()
        for page in 0..<50 { // cap so a misbehaving host can't page forever
            let result = try await fetch(page)
            entries += result.mints
            if result.mints.isEmpty || entries.count >= result.total { break }
        }
        return entries
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        try await send(URLRequest(url: url))
    }

    /// Leptos server functions take form-encoded arguments by POST.
    private static func call<T: Decodable>(_ host: AuditorHost, _ function: String, _ arguments: String) async throws -> T {
        var request = URLRequest(url: host.url.appending(path: "api/\(function)\(host.functionSuffix)"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(arguments.utf8)
        return try await send(request)
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await NetworkController.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - List

struct MintDiscovery: View {
    struct Route: Hashable {}

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { $0.active == true }) private var wallets: [Wallet]
    @Query private var walletMints: [Mint]

    @State private var mints: [DiscoveredMint]?
    @State private var adding = Set<String>()
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    var body: some View {
        let addedIDs = DiscoveredMint.addedIDs(in: walletMints)
        List {
            Section {
                ForEach(mints ?? []) { mint in
                    let added = addedIDs.contains(mint.id)
                    NavigationLink(value: mint) {
                        MintDiscoveryRow(mint: mint, added: added, adding: adding.contains(mint.id))
                    }
                    .swipeActions(edge: .trailing) {
                        if !added {
                            Button { add(mint) } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .tint(.gray)
                        }
                    }
                }
            } footer: {
                if let mints, !mints.isEmpty {
                    sourcesFooter(mints)
                }
            }
        }
        .overlay {
            if mints == nil {
                ProgressView()
            } else if mints?.isEmpty == true {
                ContentUnavailableView {
                    Label("No Mints Available", systemImage: "building.columns")
                } description: {
                    Text("The mint directories could not be reached. Pull down to try again.")
                }
            }
        }
        .navigationDestination(for: DiscoveredMint.self) { MintDiscoveryDetail(mint: $0) }
        .refreshable { await load() }
        .task {
            if mints == nil { await load() }
        }
        .navigationTitle("Discover Mints")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }

    private func sourcesFooter(_ mints: [DiscoveredMint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Swipe left on a mint to add it.")
            if let host = mints.lazy.compactMap({ $0.reviews?.host.host() }).first {
                Text("Ratings from \(host)")
            }
            if let host = mints.lazy.compactMap({ $0.audit?.host.url.host() }).first {
                Text("Availability audited by \(host)")
            }
        }
    }

    private func load() async {
        let result = await MintDirectory.load()
        // A cancelled load (tab switch) retries on the next appearance; a failed refresh keeps the list on screen.
        guard !Task.isCancelled, !result.isEmpty || mints == nil else { return }
        withAnimation { mints = result }
    }

    private func add(_ mint: DiscoveredMint) {
        guard let wallet = wallets.first, adding.insert(mint.id).inserted else { return }
        Task {
            defer { adding.remove(mint.id) }
            do {
                try await MintManagerView.addMint(url: mint.url, to: wallet, in: modelContext)
            } catch {
                logger.error("could not add discovered mint \(mint.url.absoluteString): \(error)")
                currentAlert = AlertDetail(with: error)
                showAlert = true
            }
        }
    }
}

struct MintDiscoveryRow: View {
    let mint: DiscoveredMint
    var added = false
    var adding = false

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            MintIcon(url: mint.iconURL, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(mint.displayURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Stacks rating and availability when large text leaves no room side by side.
                ViewThatFits(in: .horizontal) {
                    // Only picked when its ideal width fits, so pin it there; sub-point rounding otherwise truncates "4,9" to "4…".
                    HStack(spacing: 12) { ratingAndAvailability }
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 2) { ratingAndAvailability }
                }
                .font(.caption)
                .lineLimit(1)
                .padding(.top, 2)
            }
            // Takes all free width; a Spacer here competes for it and squeezes the rating to "…".
            .frame(maxWidth: .infinity, alignment: .leading)
            if adding {
                ProgressView()
            } else if added {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Added")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var ratingAndAvailability: some View {
        if let reviews = mint.reviews, let average = reviews.average {
            HStack(spacing: 4) {
                Stars(value: average)
                Text(average, format: .number.precision(.fractionLength(1)))
                Text(verbatim: "(\(reviews.count))")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rating: \(average.formatted(.number.precision(.fractionLength(1)))) of 5. Reviews: \(reviews.count)")
        }
        if let audit = mint.audit {
            AvailabilityBadge(audit: audit)
        }
    }
}

// MARK: - Components

struct MintIcon: View {
    let url: URL?
    let size: CGFloat

    @State private var image: UIImage?
    @ObservedObject private var network = NetworkController.shared

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "building.columns")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white)
                }
            }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(network.torOnly)") {
            image = nil
            guard let url, let (data, _) = try? await network.data(from: url), !Task.isCancelled else { return }
            image = UIImage(data: data)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct Stars: View {
    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                let position = value - Double(star)
                let fill = position >= -0.25 ? 1.0 : position >= -0.75 ? 0.5 : 0
                // A grey star with a white one masked to the filled share on top.
                Image(systemName: "star.fill")
                    .foregroundStyle(.tertiary)
                    .overlay {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.primary)
                            .mask { Rectangle().scaleEffect(x: fill, y: 1, anchor: .leading) }
                    }
            }
        }
        .imageScale(.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.formatted(.number.precision(.fractionLength(0...1)))) of 5 stars")
    }
}

/// Share of the auditor's test swaps the mint completed; red when the latest check failed.
struct AvailabilityBadge: View {
    let audit: DiscoveredMint.Audit

    private var color: Color {
        guard audit.healthy else { return .failureRed }
        guard let rate = audit.successRate else { return .gray }
        return rate >= 0.95 ? .successGreen : .orange
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if let rate = audit.successRate {
                Text(rate, format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
            } else {
                Text("Not audited yet")
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let rate = audit.successRate?.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
        switch (rate, audit.healthy) {
        case (nil, _): return String(localized: "Not audited yet")
        case (let rate?, true): return String(localized: "Availability \(rate)")
        case (let rate?, false): return String(localized: "Availability \(rate), last check failed")
        }
    }
}

#if DEBUG
#Preview("List") {
    NavigationStack {
        MintDiscovery()
    }
    .previewEnvironment()
}

#Preview("Row") {
    NavigationStack {
        List {
            NavigationLink { } label: { MintDiscoveryRow(mint: .preview) }
            NavigationLink { } label: { MintDiscoveryRow(mint: .preview, added: true) }
        }
    }
}

extension DiscoveredMint {
    static var preview: DiscoveredMint {
        var mint = DiscoveredMint(url: "https://mint.minibits.cash/Bitcoin", name: "Minibits mint",
                                  info: #"{"name":"Minibits mint","description":"Minibits wallet mint","version":"Nutshell/0.17.0"}"#)!
        mint.reviews = .init(host: MintDirectory.reviewHosts[0], id: "aHR0cHM6Ly9taW50Lm1pbmliaXRzLmNhc2gvQml0Y29pbg",
                             count: 27, average: 4.77)
        mint.audit = .init(host: MintDirectory.auditorHosts[0], id: 2, healthy: true, successes: 210, errors: 2)
        return mint
    }
}
#endif
