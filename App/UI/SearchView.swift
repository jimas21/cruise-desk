import SwiftUI

/// Search and plans (DESIGN_V4 section B, CONTRACT_V4 section 3): every sailing the fare sources have seen,
/// filtered by line, ship or size, port or region, dates, nights, cabin, budget and deal kind. Each result books
/// on its own line's site or is tracked in one tap. A search can be saved as a plan Deal Desk watches, edited,
/// and promoted to My Trip.
struct SearchView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query: SearchQuery
    @State private var rows: [SearchRow] = []
    @State private var result: SearchResult?
    @State private var loading = false
    @State private var failure: String?
    @State private var editingFilters = false
    @State private var planEditor: PlanEditorTarget?
    @State private var promoting: Plan?
    @State private var activePlan: String?
    @State private var message: String?
    @State private var dealShown: String?
    /// v5: a row opened as its sheet.
    @State private var rowShown: SearchRow?

    init(initialQuery: SearchQuery? = nil) {
        _query = State(initialValue: initialQuery ?? SearchMemory.load())
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.has(.search) {
                    Section {
                        IllustratedEmpty(title: "Search is coming soon",
                                         message: "Find any sailing Deal Desk has seen, by line, ship, port, dates, nights, cabin and budget. This switches on by itself once the deal server lists it.")
                            .listRowBackground(Color.clear)
                    }
                } else {
                    if store.has(.plans) { plansSection }
                    filtersSection
                    resultsSection
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if store.has(.plans) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            planEditor = .new(query)
                        } label: {
                            Label("Save as plan", systemImage: "bookmark")
                        }
                        .accessibilityLabel(Text("Save this search as a plan"))
                    }
                }
            }
            .task(id: query) {
                SearchMemory.save(query)
                guard store.has(.search) else { return }
                await run(reset: true)
            }
            .refreshable { await run(reset: true) }
            .navigationDestination(item: $dealShown) { id in
                DealDetailView(dealId: id)
            }
            .navigationDestination(item: $rowShown) { row in
                SailingSheetScreen(row: row, cabin: query.cabin, savePlan: savePlanAction)
            }
            .sheet(isPresented: $editingFilters) {
                SearchFiltersSheet(query: $query)
            }
            .sheet(item: $planEditor) { target in
                PlanEditor(target: target)
            }
            .confirmationDialog("Make this plan My Trip?", isPresented: promotingShown, titleVisibility: .visible,
                                presenting: promoting) { plan in
                Button("Promote to my trip") {
                    store.promote(plan)
                    message = "My Trip now follows “\(plan.name)”."
                }
            } message: { plan in
                Text(PromoteText.message(plan))
            }
            .alert("Search", isPresented: messageShown) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    /// From an opened row: save the search that found it as a plan.
    private var savePlanAction: (() -> Void)? {
        guard store.has(.plans) else { return nil }
        let current = query
        return { planEditor = .new(current) }
    }

    private var promotingShown: Binding<Bool> {
        Binding(get: { promoting != nil }, set: { if !$0 { promoting = nil } })
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    // MARK: Plans

    private var plansSection: some View {
        Section {
            if store.plans.isEmpty {
                Text("Save a search as a plan (the bookmark at the top) and Deal Desk checks it on every run.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.plans) { plan in
                PlanRow(plan: plan, active: activePlan == plan.id, use: { use(plan) },
                        edit: { planEditor = .edit(plan) }, promote: { promoting = plan },
                        delete: { withAnimation(Motion.spring) { store.deletePlan(plan) } })
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            withAnimation(Motion.spring) { store.deletePlan(plan) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            planEditor = .edit(plan)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Palette.accent)
                    }
            }
        } header: {
            Text("My plans")
        }
    }

    private func use(_ plan: Plan) {
        activePlan = plan.id
        withAnimation(Motion.snappy) { query = plan.query }
        Haptics.tap()
    }

    // MARK: Filters

    private var filtersSection: some View {
        Section {
            DefaultLinesBanner()
            Button {
                editingFilters = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(Palette.accent)
                    Text(query.summary)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("Edit")
                        .foregroundStyle(Palette.accent)
                }
                .font(.subheadline)
            }
            .accessibilityLabel(Text("Filters: \(query.summary)"))
            .accessibilityHint(Text("Opens the search filters"))
            Picker("Sort", selection: sortBinding) {
                ForEach(SearchSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            if !query.isEmpty {
                Button("Clear filters", role: .destructive) {
                    activePlan = nil
                    withAnimation(Motion.snappy) { query = SearchQuery(sort: query.sort) }
                }
                .font(.subheadline)
            }
        }
    }

    private var sortBinding: Binding<SearchSort> {
        Binding(get: { SearchSort(raw: query.sort) }, set: { query.sort = $0.rawValue })
    }

    // MARK: Results

    /// Rows of a known region first; with a region filter, rows whose region is not known sit under their own
    /// header after them (CONTRACT_V5 section 1.6).
    private var splitsUnknownRegion: Bool { store.has(.catalog5) && !query.regions.isEmpty }
    private var knownRows: [SearchRow] { splitsUnknownRegion ? rows.filter { !$0.regionUnknown } : rows }
    private var unknownRegionRows: [SearchRow] { splitsUnknownRegion ? rows.filter { $0.regionUnknown } : [] }

    private func rowView(_ row: SearchRow) -> some View {
        SearchRowView(row: row, book: store.bookChoice(for: row), hasDeal: row.dealId.flatMap { store.deal($0) } != nil,
                      tracked: isTracked(row), track: { track(row) }, openDeal: { dealShown = row.dealId },
                      open: { rowShown = row })
    }

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            if loading && rows.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching the sailings Deal Desk has seen…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let failure, rows.isEmpty {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if rows.isEmpty {
                if let result, result.hasExplanation {
                    EmptySearchExplained(result: result)
                } else {
                    Text("No sailings match. A fact Deal Desk doesn't know never hides a sailing, so try fewer filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(knownRows) { row in
                rowView(row)
            }
            if result?.nextOffset != nil && unknownRegionRows.isEmpty {
                Button {
                    Task { await run(reset: false) }
                } label: {
                    HStack {
                        Text("Show more")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .disabled(loading)
            }
        } header: {
            Text(countLine)
        } footer: {
            if !footerLines.isEmpty && unknownRegionRows.isEmpty {
                Text(footerLines.joined(separator: "\n"))
            }
        }
        if !unknownRegionRows.isEmpty {
            Section {
                ForEach(unknownRegionRows) { row in
                    rowView(row)
                }
                if result?.nextOffset != nil {
                    Button {
                        Task { await run(reset: false) }
                    } label: {
                        HStack {
                            Text("Show more")
                            if loading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(loading)
                }
            } header: {
                Text("Region not known (\(unknownRegionRows.count))")
            } footer: {
                if !footerLines.isEmpty {
                    Text(footerLines.joined(separator: "\n"))
                }
            }
        }
    }

    private var countLine: String {
        guard let result else { return "Sailings" }
        let total = result.total ?? rows.count
        return total == 1 ? "1 sailing" : "\(total) sailings"
    }

    private var footerLines: [String] {
        var lines: [String] = (result?.notes ?? []).map { Words.capitalizedFirst($0) }
        if !rows.isEmpty { lines.append("Only sailings a source has shown in the last 45 days; prices as each source states them.") }
        return lines
    }

    private func isTracked(_ row: SearchRow) -> Bool {
        if let id = row.trackedId, store.trackedSailing(id) != nil { return true }
        return store.trackedMatch(key: row.trackPick(cabin: query.cabin).key) != nil
    }

    private func track(_ row: SearchRow) {
        switch store.track(row.trackPick(cabin: query.cabin)) {
        case .added: message = nil
        case .already: message = "You already track this sailing."
        case .comingSoon: message = "Tracking switches on once the deal server has it."
        case .full: message = "You track \(Store.trackedLimit) sailings, the most there is. Stop one first."
        case .invalid(let why): message = why
        }
    }

    private func run(reset: Bool) async {
        let offset = reset ? 0 : (result?.nextOffset ?? rows.count)
        loading = true
        defer { loading = false }
        do {
            let fresh = try await store.search(query, offset: offset)
            if Task.isCancelled { return }
            if reset { rows = fresh.rows } else { rows += fresh.rows.filter { row in !rows.contains { $0.id == row.id } } }
            result = fresh
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if reset { rows = [] }
            failure = Problem(error).detail
        }
    }
}

/// The last search, kept on the phone so Search opens where Jim left it.
enum SearchMemory {
    private static let key = "search.lastQuery"

    static func load() -> SearchQuery {
        guard let data = UserDefaults.standard.data(forKey: key),
              let query = try? JSONDecoder().decode(SearchQuery.self, from: data) else { return SearchQuery() }
        return query
    }

    static func save(_ query: SearchQuery) {
        if let data = try? JSONEncoder().encode(query) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum PromoteText {
    static func message(_ plan: Plan) -> String {
        var text = "My Trip takes this plan's lines, ship sizes, dates, sail months, nights, cabin and deal kinds."
        let left = PlanPromotion.notCopied(plan)
        if !left.isEmpty { text += " Not copied (My Trip has no place for them): \(left.joined(separator: ", "))." }
        return text
    }
}

// MARK: - Rows

/// One saved plan: its name, what it looks for, Deal Desk's last look, and a menu.
struct PlanRow: View {
    let plan: Plan
    let active: Bool
    let use: () -> Void
    let edit: () -> Void
    let promote: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: use) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                        if plan.watching {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundStyle(Palette.accent)
                                .accessibilityLabel(Text("Watched"))
                        }
                        if plan.isLocal {
                            Image(systemName: "arrow.up.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("Saving"))
                        }
                    }
                    Text(plan.query.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if let check = plan.checkLine {
                        Text(check)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let note = plan.data.brainNote?.trimmed, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.accent)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows this plan's sailings"))
            if active {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel(Text("Showing"))
            }
            Menu {
                Button(action: edit) { Label("Edit", systemImage: "pencil") }
                Button(action: promote) { Label("Promote to my trip", systemImage: "suitcase") }
                Button(role: .destructive, action: delete) { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Plan options"))
        }
    }
}

/// One search result: the sailing at a glance, then Book on <Line> and Track.
struct SearchRowView: View {
    let row: SearchRow
    let book: BookChoice
    let hasDeal: Bool
    let tracked: Bool
    let track: () -> Void
    var openDeal: () -> Void = {}
    /// v5: opens the row as its sheet (trip cost, verdict); nil keeps the v4 row.
    var open: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                open?()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.eyebrow)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(row.shipTitle)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            if open != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if !row.datesLine.isEmpty {
                            Text(row.datesLine)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                                .monospacedDigit()
                                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    Spacer(minLength: 8)
                    if let score = row.score {
                        ScoreRing(score: score, label: row.scoreLabel)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(open == nil)
            .accessibilityHint(Text(open == nil ? "" : "Opens the trip cost and details"))
            if let route = row.route {
                Text(route)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
            priceLine
            if let cost = row.tripCost {
                TripCostLine(cost: cost)
            }
            if !row.typeChips.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(row.typeChips, id: \.self) { chip in
                        TagLabel(text: chip, color: Palette.fits)
                    }
                }
            }
            if let fit = row.fit, !fit.reasons.isEmpty {
                PortFitCaption(fit: fit)
            }
            if let unknown = row.unknownNote {
                Text(unknown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 10) {
                if hasDeal {
                    Button(action: openDeal) {
                        Label("See the deal", systemImage: "tag")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(action: track) {
                    Label(tracked ? "Tracking" : "Track", systemImage: tracked ? "checkmark" : "binoculars")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(tracked)
                .accessibilityHint(Text(tracked ? "Already tracked" : "Tracks this sailing; prices fill in from Deal Desk's data"))
            }
            BookBar(choice: book)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var priceLine: some View {
        if let price = row.pricePP, price > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.usd(price))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(priceDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else if row.scheduleOnly {
            Text("Price not seen · a schedule lists this sailing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("No current price · \(row.cabinType?.title.lowercased() ?? "any cabin")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var priceDetail: String {
        var parts = ["pp"]
        if row.priceIncludesTaxes == true { parts.append("taxes in") }
        if let cabin = row.cabinType { parts.append(cabin.title.lowercased()) }
        if let typical = row.typicalPP, typical > 0 { parts.append("typical \(Fmt.usd(typical))") }
        if let source = row.priceSource?.trimmed, !source.isEmpty { parts.append(source) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Filters

/// The search filters. Empty means any; a fact Deal Desk doesn't know never fails a filter.
struct SearchFiltersSheet: View {
    @Binding var query: SearchQuery
    var title = "Filters"
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SearchQuery

    init(query: Binding<SearchQuery>, title: String = "Filters") {
        _query = query
        self.title = title
        _draft = State(initialValue: query.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            SearchFiltersForm(draft: $draft)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            query = draft.cleaned()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

struct SearchFiltersForm: View {
    @Binding var draft: SearchQuery
    @EnvironmentObject private var store: Store
    @State private var portsText = ""
    @State private var regionsText = ""
    @State private var budgetText = ""

    private var lineOptions: [ReasonOption] {
        CruiseLine.choosable(store.catalog).map { ReasonOption(id: $0, title: $0) }
    }

    private var pickers: Bool { store.has(.catalog5) }

    private func listBinding(_ path: WritableKeyPath<SearchQuery, [String]>) -> Binding<[String]> {
        Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0 })
    }

    private func chosenText(_ items: [String], none: String) -> String {
        items.isEmpty ? none : ListText.join(items)
    }

    private var shipOptions: [ReasonOption] {
        var out: [ReasonOption] = []
        for line in draft.lines {
            for ship in store.catalog.ships(for: line) {
                guard let name = ship.name, !out.contains(where: { $0.id == name }) else { continue }
                out.append(ReasonOption(id: name, title: name))
            }
        }
        return Array(out.prefix(60))
    }

    var body: some View {
        Form {
            Section {
                if pickers {
                    PickerLink(label: "Lines", value: chosenText(draft.lines, none: "Any line")) {
                        LinesPickerScreen(selection: listBinding(\.lines))
                    }
                } else {
                    ChipPicker(options: lineOptions, selection: set(\.lines))
                }
            } header: {
                Text("Lines")
            } footer: {
                Text(pickers ? "Every line is offered, with what Deal Desk can see for it. None picked means every line."
                             : "None picked means every line.")
            }
            Section {
                ChipPicker(options: ShipSize.allCases.map { ReasonOption(id: $0.rawValue, title: $0.title) },
                           selection: set(\.sizes))
                if !shipOptions.isEmpty {
                    ChipPicker(options: shipOptions, selection: set(\.ships))
                }
            } header: {
                Text("Ship or size")
            } footer: {
                Text(draft.lines.isEmpty ? "Pick a line to choose its ships." : "A ship whose size isn't known still shows.")
            }
            if pickers {
                Section {
                    PickerLink(label: "Leaving from", value: chosenText(draft.ports, none: "Any port")) {
                        PortPickerScreen(title: "Leaving from", kind: .embark, selection: listBinding(\.ports))
                    }
                    PickerLink(label: "Visits", value: chosenText(draft.calls, none: "Any port of call")) {
                        PortPickerScreen(title: "Visits", kind: .visit, selection: listBinding(\.calls),
                                         footer: "Sailings that stop at any of these. Scenic cruising counts too: Glacier Bay, Hubbard Glacier, Tracy Arm.")
                    }
                    PickerLink(label: "Region", value: chosenText(draft.regions, none: "Anywhere")) {
                        RegionPickerScreen(selection: listBinding(\.regions))
                    }
                } header: {
                    Text("Where")
                } footer: {
                    Text("A sailing whose region isn't known is listed last, under its own heading.")
                }
            } else {
                Section("Leaving from") {
                    TextField("Ports, separated by commas", text: $portsText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: portsText) { _, text in draft.ports = SearchFiltersForm.split(text) }
                    TextField("Regions, separated by commas", text: $regionsText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: regionsText) { _, text in draft.regions = SearchFiltersForm.split(text) }
                }
            }
            datesSection
            nightsSection
            Section {
                Picker("Cabin", selection: cabinBinding) {
                    Text("Cheapest priced").tag("")
                    ForEach([CabinType.interior, .oceanview, .balcony, .suite], id: \.rawValue) { cabin in
                        Text(cabin.title).tag(cabin.rawValue)
                    }
                }
                HStack {
                    Text("Up to")
                    TextField("any", text: $budgetText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: budgetText) { _, text in
                            let digits = text.filter { $0.isNumber }
                            draft.maxPP = Int(digits.prefix(7)).flatMap { $0 > 0 ? $0 : nil }
                        }
                    Text("pp")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Cabin and budget")
            } footer: {
                Text("A sailing with no current price still shows; it says so.")
            }
            Section("Deal kind") {
                ChipPicker(options: SearchDealType.allCases.map { ReasonOption(id: $0.rawValue, title: $0.title) },
                           selection: set(\.dealTypes))
            }
        }
        .onAppear {
            portsText = draft.ports.joined(separator: ", ")
            regionsText = draft.regions.joined(separator: ", ")
            budgetText = draft.maxPP.map { String($0) } ?? ""
        }
    }

    private var datesSection: some View {
        Section {
            Toggle("From", isOn: dateOn(\.dateFrom, default: Date()))
            if let from = Fmt.day(draft.dateFrom) {
                DatePicker("Sailing on or after", selection: dateBinding(\.dateFrom, fallback: from),
                           displayedComponents: .date)
            }
            Toggle("To", isOn: dateOn(\.dateTo, default: Fmt.adding(days: 180, to: Date()) ?? Date()))
            if let to = Fmt.day(draft.dateTo) {
                DatePicker("Sailing on or before", selection: dateBinding(\.dateTo, fallback: to),
                           displayedComponents: .date)
            }
            ChipPicker(options: (1...12).map { ReasonOption(id: String($0), title: Fmt.monthShort($0)) },
                       selection: monthsBinding)
        } header: {
            Text("Dates")
        } footer: {
            Text("No month picked means any month.")
        }
    }

    private var nightsSection: some View {
        Section("Nights") {
            Toggle("Any length", isOn: anyNights)
            if draft.nightsMin != nil || draft.nightsMax != nil {
                Stepper("At least \(draft.nightsMin ?? 1)", value: nightsBinding(\.nightsMin, 1), in: 1...30)
                Stepper("At most \(draft.nightsMax ?? 30)", value: nightsBinding(\.nightsMax, 30), in: 1...30)
            }
        }
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    private func set(_ path: WritableKeyPath<SearchQuery, [String]>) -> Binding<Set<String>> {
        Binding(get: { Set(draft[keyPath: path]) }, set: { draft[keyPath: path] = Array($0).sorted() })
    }

    private var monthsBinding: Binding<Set<String>> {
        Binding(get: { Set(draft.months.map { String($0) }) },
                set: { draft.months = $0.compactMap { Int($0) }.sorted() })
    }

    private var cabinBinding: Binding<String> {
        Binding(get: { draft.cabin ?? "" }, set: { draft.cabin = $0.isEmpty ? nil : $0 })
    }

    private func dateOn(_ path: WritableKeyPath<SearchQuery, String?>, default start: Date) -> Binding<Bool> {
        Binding(get: { draft[keyPath: path] != nil },
                set: { on in draft[keyPath: path] = on ? Fmt.isoDay(start) : nil })
    }

    private func dateBinding(_ path: WritableKeyPath<SearchQuery, String?>, fallback: Date) -> Binding<Date> {
        Binding(get: { Fmt.day(draft[keyPath: path]) ?? fallback },
                set: { draft[keyPath: path] = Fmt.isoDay($0) })
    }

    private var anyNights: Binding<Bool> {
        Binding(get: { draft.nightsMin == nil && draft.nightsMax == nil },
                set: { any in
                    if any {
                        draft.nightsMin = nil
                        draft.nightsMax = nil
                    } else {
                        draft.nightsMin = 5
                        draft.nightsMax = 8
                    }
                })
    }

    private func nightsBinding(_ path: WritableKeyPath<SearchQuery, Int?>, _ fallback: Int) -> Binding<Int> {
        Binding(get: { draft[keyPath: path] ?? fallback }, set: { draft[keyPath: path] = $0 })
    }
}

// MARK: - An empty search explains itself (CONTRACT_V5 section 1.6)

/// Why nothing matched, in the server's words; the funnel as a short list ("Disney 289 → Alaska 0"); and the one
/// thing to do about it: start collecting the line, or open the line's own site.
struct EmptySearchExplained: View {
    let result: SearchResult
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    @State private var started: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing matches")
                .font(.headline)
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.funnel.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Where the sailings went")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(result.funnel.prefix(12).enumerated()), id: \.offset) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.offset == 0 ? "circle" : "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(item.element.text)
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle((item.element.remaining ?? 1) == 0 ? Palette.call : Color.secondary)
                        }
                        .padding(.leading, CGFloat(min(item.offset, 6)) * 6)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(actions, id: \.self) { gap in
                actionButton(gap)
            }
        }
        .padding(.vertical, 4)
    }

    /// `why` first; else each gap's note (or its reason in words).
    private var lines: [String] {
        if !result.whyLines.isEmpty { return result.whyLines }
        let notes = result.coverageGap.map { gap -> String in
            if let note = gap.note?.trimmed, !note.isEmpty { return note }
            return gap.reasonText
        }
        return notes.isEmpty ? ["A fact Deal Desk doesn't know never hides a sailing, so try fewer filters."] : notes
    }

    private var actions: [CoverageGap] {
        result.coverageGap.filter { $0.action == "collect_line" || $0.action == "open_line" }
    }

    @ViewBuilder
    private func actionButton(_ gap: CoverageGap) -> some View {
        let line = gap.lineName
        if gap.action == "collect_line" {
            if store.has(.collect) {
                let done = started.contains(line) || store.collectPrefs.has(line)
                Button {
                    if store.startCollecting(line) { started.insert(line) }
                } label: {
                    Label(done ? "Collecting \(line): first results in about a day" : "Start collecting \(line)",
                          systemImage: done ? "checkmark.circle" : "plus.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(done)
            }
        } else if let home = store.catalog.line(line)?.booking?.home, let url = Fmt.webURL(home) {
            Button {
                openURL(url)
            } label: {
                Label("Open \(store.catalog.line(line)?.booking?.short ?? line)'s own site", systemImage: "safari")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Plan editor

enum PlanEditorTarget: Identifiable {
    case new(SearchQuery)
    case edit(Plan)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let plan): return plan.id
        }
    }
}

/// Name a search, say whether Deal Desk watches it and may alert on a match, and adjust its filters.
struct PlanEditor: View {
    let target: PlanEditorTarget
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanDraft
    @State private var editingFilters = false
    @State private var alert: String?

    init(target: PlanEditorTarget) {
        self.target = target
        switch target {
        case .new(let query):
            var d = PlanDraft()
            d.query = query
            _draft = State(initialValue: d)
        case .edit(let plan):
            _draft = State(initialValue: PlanDraft(plan: plan))
        }
    }

    private var editing: Plan? {
        if case .edit(let plan) = target { return plan }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Icon from Galveston, fall 2027", text: nameBinding)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Plan")
                }
                Section {
                    Button {
                        editingFilters = true
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(draft.query.summary)
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text("Edit")
                        }
                    }
                } header: {
                    Text("Looks for")
                }
                Section {
                    Toggle("Deal Desk checks it on every run", isOn: $draft.watch)
                    Toggle("Alert me when a match is a deal", isOn: $draft.alerts)
                        .disabled(!draft.watch)
                } footer: {
                    Text("An alert follows the usual rule: at most one a run, and only for a real deal.")
                }
                Section("Note") {
                    TextField("Anything to remember (optional)", text: noteBinding, axis: .vertical)
                        .lineLimit(1...3)
                }
                if let plan = editing, let check = plan.checkLine {
                    Section("Deal Desk's last look") {
                        Text(check)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle(editing == nil ? "Save as plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.problem != nil)
                }
            }
            .sheet(isPresented: $editingFilters) {
                SearchFiltersSheet(query: $draft.query, title: "Plan filters")
            }
            .alert("Can't save this plan", isPresented: alertShown) {
                Button("OK", role: .cancel) { alert = nil }
            } message: {
                Text(alert ?? "")
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { draft.name = String($0.prefix(60)) })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { draft.note }, set: { draft.note = String($0.prefix(120)) })
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }

    private func save() {
        if !draft.watch { draft.alerts = false }
        switch store.savePlan(draft, editing: editing) {
        case .saved: dismiss()
        case .already: alert = "A plan with that name already exists. Pick another name."
        case .comingSoon: alert = "Plans switch on once the deal server has them."
        case .full: alert = "You have \(Store.plansLimit) plans, the most there is. Delete one first."
        case .invalid(let why): alert = why
        }
    }
}
