import SwiftUI

enum DealFilter: String, CaseIterable, Identifiable {
    case all, fits, call, drop, sale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .fits: return "Fits"
        case .call: return "Your call"
        case .drop: return "Drops"
        case .sale: return "Sales"
        }
    }

    func matches(_ deal: Deal) -> Bool {
        self == .all || deal.kind?.rawValue == rawValue
    }
}

enum DealSort: String, CaseIterable, Identifiable {
    case newest, score

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .score: return "Best score"
        }
    }
}

/// Opens the answer sheet for one deal with a verdict already chosen.
struct AnswerTarget: Identifiable {
    let deal: Deal
    let verdict: Verdict
    var id: String { "\(deal.id)/\(verdict.rawValue)" }
}

/// Tab 1: deals with no answer yet.
struct DealsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @State private var filter: DealFilter = .all
    @AppStorage("dealSort") private var sort: DealSort = .newest
    @State private var showStatus = false
    @State private var showSettings = false
    @State private var answering: AnswerTarget?

    private var items: [Deal] {
        let matching = store.inbox.filter { filter.matches($0) }
        switch sort {
        case .newest:
            return matching
        case .score:
            return matching.sorted { ($0.data.score ?? 0, $0.latest) > ($1.data.score ?? 0, $1.latest) }
        }
    }

    var body: some View {
        NavigationStack(path: $router.dealsPath) {
            List {
                Section {
                    DealsHeader(status: store.status, syncing: store.syncing) { showStatus = true }
                        .listRowInsets(EdgeInsets(top: 4, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    Picker("Show", selection: $filter.animation(Motion.snappy)) {
                        ForEach(DealFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: CardList.gutter, bottom: 8, trailing: CardList.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)

                if let problem = store.problem {
                    ProblemRow(problem: problem, lastSync: store.lastSync) { showSettings = true }
                }

                if items.isEmpty {
                    Section {
                        EmptyInbox(filter: filter, anyDeals: !store.inbox.isEmpty)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                } else {
                    Section {
                        ForEach(items) { deal in
                            Button {
                                router.dealsPath.append(deal.id)
                            } label: {
                                DealCard(deal: deal)
                            }
                            .buttonStyle(CardPressStyle())
                            .cardRow()
                            .accessibilityHint(Text("Opens the details"))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    answering = AnswerTarget(deal: deal, verdict: .interested)
                                } label: {
                                    Label("Interested", systemImage: Verdict.interested.symbol)
                                }
                                .tint(Palette.fits)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    answering = AnswerTarget(deal: deal, verdict: .pass)
                                } label: {
                                    Label("Not for me", systemImage: Verdict.pass.symbol)
                                }
                                .tint(.red)
                                Button {
                                    withAnimation(Motion.spring) {
                                        store.answer(deal, verdict: .later, reasons: [], note: "")
                                    }
                                } label: {
                                    Label("Later", systemImage: Verdict.later.symbol)
                                }
                                .tint(.gray)
                            }
                            .accessibilityAction(named: Text("Interested")) {
                                answering = AnswerTarget(deal: deal, verdict: .interested)
                            }
                            .accessibilityAction(named: Text("Not for me")) {
                                answering = AnswerTarget(deal: deal, verdict: .pass)
                            }
                            .accessibilityAction(named: Text("Later")) {
                                withAnimation(Motion.spring) {
                                    store.answer(deal, verdict: .later, reasons: [], note: "")
                                }
                            }
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .cardList()
            .onChange(of: filter) { Haptics.tap() }
            .navigationTitle("Deals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(DealSort.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(Text("Sort"))
                }
            }
            .refreshable {
                await store.refresh()
            }
            .navigationDestination(for: String.self) { id in
                DealDetailView(dealId: id)
            }
            .sheet(isPresented: $showStatus) {
                StatusSheet()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(item: $answering) { target in
                AnswerSheet(deal: target.deal, verdict: target.verdict, existing: nil)
            }
        }
    }
}

/// The top of the Deals tab: a small sea scene (day sky, or night sky in dark mode) with the check line on a
/// frosted label at its foot. Tapping it opens the status sheet.
struct DealsHeader: View {
    let status: RunStatus?
    let syncing: Bool
    let onTap: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: typeSize.isAccessibilitySize ? 112 : 96)
                CheckLine(status: status, syncing: syncing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { SeaScene() }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
            }
        }
        .buttonStyle(CardPressStyle())
    }
}

/// "Checked 9:12 · 203 sailings · 10 sources", or the failed check in plain words.
struct CheckLine: View {
    let status: RunStatus?
    let syncing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var lines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    var body: some View {
        HStack(spacing: 6) {
            if syncing {
                ProgressView().controlSize(.mini)
            }
            if let status {
                if status.failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.call)
                    Text(failedText(status))
                        .lineLimit(lines)
                } else {
                    Text(okText(status))
                        .monospacedDigit()
                        .lineLimit(lines)
                }
            } else {
                Text("Waiting for the first check")
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityHint(Text("Shows which sources worked"))
    }

    private func okText(_ status: RunStatus) -> String {
        var parts: [String] = []
        if let run = status.lastRun { parts.append("Checked \(Fmt.when(run))") }
        if let sailings = status.data.sailingsChecked { parts.append("\(sailings) sailings") }
        if !status.worked.isEmpty { parts.append("\(status.worked.count) sources") }
        return parts.isEmpty ? "Checked" : parts.joined(separator: " · ")
    }

    private func failedText(_ status: RunStatus) -> String {
        let when = status.lastRun.map { " \(Fmt.when($0))" } ?? ""
        if let error = status.data.error, !error.isEmpty {
            return "Last check failed\(when) — \(error)"
        }
        return "Last check failed\(when)"
    }
}

/// Offline / not set up / token refused, with a way out.
struct ProblemRow: View {
    let problem: Problem
    let lastSync: Date?
    let openSettings: () -> Void

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: problem.symbol)
                    .font(.title3)
                    .foregroundStyle(Palette.call)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.title).font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if needsSettings {
                        Button("Open Settings", action: openSettings)
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(CardBackground())
            .cardRow()
        }
        .listSectionSeparator(.hidden)
    }

    private var needsSettings: Bool {
        switch problem {
        case .notConfigured, .unauthorized: return true
        case .offline, .server: return false
        }
    }

    private var detail: String {
        if case .offline = problem, let lastSync {
            return "Showing what was saved \(Fmt.when(lastSync)). Answers are kept and sent when you're back online."
        }
        return problem.detail
    }
}

private struct EmptyInbox: View {
    let filter: DealFilter
    let anyDeals: Bool

    var body: some View {
        if filter != .all && anyDeals {
            IllustratedEmpty(title: "None in \(filter.title)", message: "Other deals are waiting under All.")
        } else {
            IllustratedEmpty(title: "All caught up",
                             message: "No deals waiting for an answer. Claude checks every hour and pings you when one is worth a look.")
        }
    }
}

#Preview("Deals") {
    DealsView()
        .environmentObject(Store.preview())
        .environmentObject(Router())
}
