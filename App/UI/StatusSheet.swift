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
