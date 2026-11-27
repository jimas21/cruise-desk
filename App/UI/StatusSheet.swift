import SwiftUI

/// Tapping "Checked 9:12 · …": the last check, which sources worked or failed, what Claude is watching,
/// and this phone's sync state.
struct StatusSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                lastCheck
                if let status = store.status {
                    if !status.worked.isEmpty {
                        Section("Sources that worked · \(status.worked.count)") {
                            ForEach(Array(status.worked.enumerated()), id: \.offset) { item in
                                Label {
                                    Text(item.element)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.fits)
                                }
                            }
                        }
                    }
                    if !status.failedSources.isEmpty {
                        Section("Sources that failed · \(status.failedSources.count)") {
                            ForEach(Array(status.failedSources.enumerated()), id: \.offset) { item in
                                Label {
                                    Text(item.element)
                                } icon: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.call)
                                }
                            }
                        }
                    }
                }
                if store.isV3 {
                    linesSection
                    freshSection
                }
                if !store.watchlist.isEmpty {
                    Section("Watching · \(store.watchlist.count)") {
                        ForEach(store.watchlist) { item in
                            WatchRow(item: item)
                        }
                    }
                }
                Section {
                    if let synced = store.lastSync {
                        InfoRow(label: "Last synced", value: Fmt.when(synced))
                    }
                    if store.pendingCount > 0 {
                        InfoRow(label: "Waiting to send", value: String(store.pendingCount))
                    }
                    if let problem = store.problem {
                        InfoRow(label: problem.title, value: "", note: problem.detail)
                    }
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Text("Sync now")
                            Spacer()
                            if store.syncing { ProgressView() }
                        }
                    }
                    .disabled(store.syncing)
                    NavigationLink("Settings") {
                        SettingsView()
                    }
                } header: {
                    Text("This phone")
                } footer: {
                    Text("Deal Desk \(AppVersion.display)")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await store.loadRefreshState() }
    }

    /// What Deal Desk can see on each of My Lines (from the deal server's catalog).
    private var linesSection: some View {
        let mine = store.trip?.effectiveLines ?? [CruiseLine.royal]
        let names = mine.isEmpty ? CruiseLine.choosable(store.catalog) : mine
        return Section {
            ForEach(names, id: \.self) { name in
                LineRow(name: name, line: store.catalog.line(name))
            }
        } header: {
            Text(mine.isEmpty ? "Every line" : "My lines")
        }
    }

    /// The last "fresh look" this phone asked for, and how far the collector got with it.
    @ViewBuilder
    private var freshSection: some View {
        let state = store.refreshState
        if store.nudgedAt != nil || state?.requestedAt != nil {
            Section {
                if let asked = store.nudgedAt {
                    InfoRow(label: "Asked", value: Fmt.when(asked),
                            note: store.nudge?.accepted == false ? "the server had just checked" : nil)
                }
                if let next = Fmt.timestamp(store.nudge?.nextAllowedAt), next > Date() {
                    InfoRow(label: "Next allowed", value: Fmt.when(next))
                }
                if let seen = Fmt.timestamp(state?.collectorSeenAt) {
                    InfoRow(label: "Collector started", value: Fmt.when(seen))
                }
                if let done = Fmt.timestamp(state?.collectorDoneAt) {
                    InfoRow(label: "Collector done", value: Fmt.when(done))
                }
                if let refilled = Fmt.timestamp(state?.refilledAt) {
                    InfoRow(label: "Tracked prices filled", value: Fmt.when(refilled))
                }
            } header: {
                Text("Fresh look")
            } footer: {
                Text("Only the sources that allow automated checks are refreshed; others reach Deal Desk through their own alert emails.")
            }
        }
    }

    @ViewBuilder
    private var lastCheck: some View {
        Section("Last check") {
            if let status = store.status {
                if let run = status.lastRun {
                    InfoRow(label: "When", value: Fmt.when(run))
                }
                InfoRow(label: "Result", value: status.failed ? "Failed" : "OK",
                        valueColor: status.failed ? Palette.call : Palette.fits)
                if let sailings = status.data.sailingsChecked {
                    InfoRow(label: "Sailings checked", value: String(sailings))
                }
                if let new = status.data.newItems {
                    InfoRow(label: "New items", value: String(new))
                }
                if let summary = status.data.summary, !summary.isEmpty {
                    TextBlock(text: summary)
                }
                if let error = status.data.error, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.call)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No check has reported yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WatchRow: View {
    let item: WatchItem

    var body: some View {
        let d = item.data
        VStack(alignment: .leading, spacing: 3) {
            Text(d.ship ?? "Sailing").font(.subheadline.weight(.semibold))
            if let line = d.line, !CruiseLine.isRoyal(line) {
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
            Text(line)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let now = d.nowPP {
                HStack(spacing: 4) {
                    Text("\(Fmt.usd(now)) pp").fontWeight(.semibold)
                    if let low = d.lowestSeenPP {
                        Text("· low \(Fmt.usd(low))").foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        var parts: [String] = []
        if let day = item.sailDay { parts.append(Fmt.fullDay(day)) }
        if let nights = item.data.nights { parts.append(Fmt.nights(nights)) }
        if let port = item.data.port, !port.isEmpty { parts.append(port) }
        if let cabin = item.data.cabin.flatMap({ CabinType(rawValue: $0) }) { parts.append(cabin.title) }
        return parts.joined(separator: " · ")
    }
}

#Preview("Status") {
    StatusSheet()
        .environmentObject(Store.preview())
}
