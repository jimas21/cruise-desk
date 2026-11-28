import SwiftUI

/// Opens the answer sheet for one deal with a verdict already chosen.
struct AnswerTarget: Identifiable {
    let deal: Deal
    let verdict: Verdict
    var id: String { "\(deal.id)/\(verdict.rawValue)" }
}

/// Tab 1: deals with no answer yet, in two buckets (DESIGN_V2 section 2): Best deals (everything, best first)
/// and For my trip (the ones that pass My Trip). A sort menu and a filter sheet work on both.
struct DealsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @State private var bucket: DealBucket
    @AppStorage("dealSort") private var sort: DealSort = .score
    @AppStorage("dealFilters") private var filtersText: String = ""
    @State private var showStatus = false
    @State private var showSettings = false
    @State private var showFilters = false
    @State private var showTrip = false
    @State private var answering: AnswerTarget?
    // v4
    @State private var showDigest = false
    @State private var showSearch = false

    init(bucket: DealBucket = .best) {
        _bucket = State(initialValue: bucket)
    }

    private var filters: DealFilters { DealFilters.decode(filtersText) }

    private var filtersBinding: Binding<DealFilters> {
        Binding(get: { DealFilters.decode(filtersText) }, set: { filtersText = $0.encoded() })
    }

    var body: some View {
        let filters = self.filters
        let best = store.bucket(.best, filters: filters, sort: sort)
        let mine = store.bucket(.trip, filters: filters, sort: sort)
        let items = bucket == .best ? best : mine

        NavigationStack(path: $router.dealsPath) {
            List {
                Section {
                    if !store.digestItems.isEmpty {
                        // v4: the newsletters, folded into one list; it opens only when tapped.
                        DigestCard(newCount: store.digestNewCount, total: store.digestItems.count) { showDigest = true }
                            .listRowInsets(EdgeInsets(top: 6, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    DealsHeader(status: store.status, syncing: store.syncing) { showStatus = true }
                        .listRowInsets(EdgeInsets(top: 4, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    Picker("Show", selection: $bucket.animation(Motion.snappy)) {
                        Text("\(DealBucket.best.title)  \(best.count)").tag(DealBucket.best)
                        Text("\(DealBucket.trip.title)  \(mine.count)").tag(DealBucket.trip)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if store.showsDefaultLinesBanner {
                        DefaultLinesBanner()
                            .listRowInsets(EdgeInsets(top: 2, leading: CardList.gutter + 4, bottom: 2, trailing: CardList.gutter))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if bucket == .trip {
                        TripSummaryRow(trip: store.trip) { showTrip = true }
                            .listRowInsets(EdgeInsets(top: 4, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if filters.isActive {
                        FilterSummaryRow(filters: filters, open: { showFilters = true }, clear: {
                            withAnimation(Motion.snappy) { filtersText = "" }
                        })
                        .listRowInsets(EdgeInsets(top: 2, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listSectionSeparator(.hidden)

                if let problem = store.problem {
                    ProblemRow(problem: problem, lastSync: store.lastSync) { showSettings = true }
                }

                if items.isEmpty {
                    Section {
                        emptyState(bestCount: best.count)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                } else {
                    Section {
                        ForEach(items) { deal in
                            card(deal)
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .cardList()
            .onChange(of: bucket) { Haptics.tap() }
            .navigationTitle("Deals")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                    Button {
                        router.showAsk = true
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel(Text("Ask Deal Desk"))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search every sailing"))
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill"
                                                           : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(Text(filters.isActive ? "Filters, \(filters.activeCount) on" : "Filters"))
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(DealSort.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(Text("Sort, \(sort.title)"))
                }
            }
            .refreshable {
                await store.refresh(reason: .pull)
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
            .sheet(isPresented: $showFilters) {
                FilterSheet(filters: filtersBinding, deals: store.inbox, myLines: store.trip?.effectiveLines ?? [],
                            minPctUnder: store.trip?.minPctUnder ?? 15, fits: { store.fit($0).fits })
            }
            .sheet(isPresented: $showTrip) {
                TripEditor(start: store.trip ?? TripPrefs(), isNew: store.trip == nil)
            }
            .sheet(isPresented: $router.showAsk) {
                AskSheet()
            }
            .sheet(item: $answering) { target in
                AnswerSheet(deal: target.deal, verdict: target.verdict, existing: nil)
            }
            .sheet(isPresented: $showDigest, onDismiss: { store.markDigestSeen() }) {
                DigestSheet()
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
        }
    }

    // MARK: Cards

    /// The card: as before, or (v4) with the Book bar and the soft port note inside it. The card itself opens the
    /// details; only the Book bar opens a site.
    @ViewBuilder
    private func cardBody(_ deal: Deal, note: FitNote?) -> some View {
        let book = store.has(.booking) ? store.bookChoice(for: deal) : BookChoice()
        let port = store.portFit(deal)
        if book.isEmpty && port == nil {
            Button {
                router.dealsPath.append(deal.id)
            } label: {
                DealCard(deal: deal, note: note)
            }
            .buttonStyle(CardPressStyle())
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    router.dealsPath.append(deal.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        DealRow(deal: deal, note: note)
                        if let port {
                            PortFitCaption(fit: port)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                BookBar(choice: book)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(highlight: deal.isExceptional))
        }
    }

    private func card(_ deal: Deal) -> some View {
        let fit = store.fit(deal)
        let note = bucket == .best ? FitNote.best(fit) : FitNote.trip(fit)
        return cardBody(deal, note: note)
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

    // MARK: Empty states

    @ViewBuilder
    private func emptyState(bestCount: Int) -> some View {
        if filters.isActive {
            VStack(spacing: 0) {
                IllustratedEmpty(title: "Nothing matches these filters",
                                 message: "Clear them to see every deal again.")
                Button("Clear filters") {
                    withAnimation(Motion.snappy) { filtersText = "" }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity)
        } else if bucket == .trip {
            VStack(spacing: 0) {
                IllustratedEmpty(title: "Nothing fits your trip yet",
                                 message: bestCount > 0
                                    ? "\(bestCount) other \(bestCount == 1 ? "deal is" : "deals are") under Best deals. Loosen My Trip to see more here."
                                    : "Claude checks every hour and pings you when one fits.")
                Button("Edit My Trip") { showTrip = true }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity)
        } else {
            IllustratedEmpty(title: "All caught up",
                             message: "No deals waiting for an answer. Claude checks every hour and pings you when one is worth a look.")
        }
    }
}

/// For my trip: what the bucket is measuring against, one line, with a way to change it.
struct TripSummaryRow: View {
    let trip: TripPrefs?
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "suitcase.fill")
                    .font(.body)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Trip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(trip?.summary ?? "Not set up yet: using Claude's own trip rules")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("Edit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(CardBackground())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens My Trip"))
    }
}

/// "Filters: Oasis · Balcony" with Clear, shown while any filter is on.
private struct FilterSummaryRow: View {
    let filters: DealFilters
    let open: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(filters.summary)
                        .lineLimit(1)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 8)
            Button("Clear", action: clear)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 4)
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

#Preview("Deals") {
    DealsView()
        .environmentObject(Store.preview())
        .environmentObject(Router())
}

#Preview("For my trip") {
    DealsView(bucket: .trip)
        .environmentObject(Store.preview())
        .environmentObject(Router())
}
