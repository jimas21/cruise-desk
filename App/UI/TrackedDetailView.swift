import SwiftUI

/// One tracked sailing: the hero, then the price against typical and the lowest seen, the history, what Deal Desk
/// can see for it, the trip, cabin options, price alerts, Claude's note, sources and Jim's own pick. Every field
/// the server or Claude has not filled yet says so ("filling…"); nothing is guessed.
struct TrackedDetailView: View {
    let trackedId: String
    @EnvironmentObject private var store: Store

    var body: some View {
        if let item = store.trackedSailing(trackedId) {
            TrackedDetailContent(item: item)
        } else {
            ContentUnavailableView {
                Label("Not tracked", systemImage: "binoculars")
            } description: {
                Text("This sailing isn't in Tracking any more. Pull to refresh on the Tracking tab.")
            }
        }
    }
}

private struct TrackedDetailContent: View {
    let item: TrackedSailing
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmStop = false

    private var d: TrackedData { item.data }

    var body: some View {
        List {
            Section {
                TrackedHero(item: item)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)

            if item.isLocal {
                Section {
                    Label("Saved on this phone. It goes to Deal Desk as soon as there's a connection, and then the prices start filling in.",
                          systemImage: "arrow.up.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            priceSection
            historySection
            coverageSection
            tripSection
            cabinOptionsSection
            alertsSection
            noteSection
            sourcesSection
            pickSection
            Section {
                Button("Stop tracking", role: .destructive) { confirmStop = true }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        .navigationTitle(item.ship)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .refreshable { await store.refresh(reason: .pull) }
        .sheet(isPresented: $editing) {
            TrackedEditSheet(item: item)
        }
        .confirmationDialog("Stop tracking this sailing?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop tracking", role: .destructive) {
                store.stopTracking(item)
                dismiss()
            }
        } message: {
            Text("Deal Desk stops watching it for you. You can track it again any time.")
        }
    }

    // MARK: Price

    private var priceSection: some View {
        Section("Price") {
            if let range = item.priceRange {
                PriceMeter(range: range, pctUnder: d.pctUnderTypical, style: .detail)
                    .padding(.vertical, 6)
            }
            row("Now", d.pricePP.map { "\(Fmt.usd($0)) pp" }, note: taxesNote)
            row("Per night", d.perNightPP.map { "\(Fmt.usd($0)) pp" })
            if d.pricePP != nil {
                InfoRow(label: "Category", value: d.priceCategory ?? "category not confirmed",
                        valueColor: d.priceCategory == nil ? Color.secondary : nil)
            }
            row("Typical", d.typicalPP.map { "\(Fmt.usd($0)) pp" }, kind: .typical,
                note: d.typicalN.map { $0 == 1 ? "from 1 price" : "from \($0) prices" })
            if d.lowPP != nil || d.highPP != nil {
                InfoRow(label: "Low – high", value: lowHigh)
            }
            row("Lowest seen", d.lowestSeenPP.map { "\(Fmt.usd($0)) pp" }, note: seenNote(d.lowestSeenAt))
            if d.pricePP != nil, d.typicalPP != nil {
                InfoRow(label: "Against typical",
                        value: UnderTypical.text(pct: d.pctUnderTypical, typical: nil) ?? "not comparable",
                        note: d.pctUnderTypical == nil ? "the prices count taxes differently" : nil,
                        valueColor: (d.pctUnderTypical ?? 0) > 0 ? Palette.fits : nil)
            }
            if let source = d.priceSource, !source.isEmpty {
                InfoRow(label: "From", value: source, note: seenNote(d.priceSeenAt))
            }
        }
    }

    private var taxesNote: String? {
        switch d.priceIncludesTaxes {
        case true?: return "taxes included"
        case false?: return "plus taxes"
        case nil: return nil
        }
    }

    private var lowHigh: String {
        let low = d.lowPP.map { Fmt.usd($0) } ?? "?"
        let high = d.highPP.map { Fmt.usd($0) } ?? "?"
        return "\(low) – \(high)"
    }

    private func seenNote(_ text: String?) -> String? {
        if let stamp = Fmt.timestamp(text) { return "seen \(Fmt.when(stamp))" }
        if let day = Fmt.day(text) { return "seen \(Fmt.fullDay(day))" }
        return nil
    }

    /// A label/value row whose value says "filling…" (or why it's missing) until there is one.
    private func row(_ label: String, _ value: String?, kind: Fill.Kind = .fill, note: String? = nil) -> some View {
        InfoRow(label: label, value: value ?? item.missing(kind), note: value == nil ? nil : note,
                valueColor: value == nil ? Color.secondary : nil)
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        let points = item.historyPoints
        Section("Price history") {
            if points.count >= 2 {
                PriceHistoryChart(points: points)
                    .padding(.vertical, 6)
            } else {
                InfoRow(label: "History", value: points.isEmpty ? item.missing() : "one price so far",
                        valueColor: Color.secondary)
            }
        }
    }

    // MARK: Coverage

    private var coverageSection: some View {
        Section {
            HStack(spacing: 10) {
                CoverageBadge(coverage: item.coverage)
                Text(item.state.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let coverage = item.coverage {
                Text(coverage.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let filled = Fmt.timestamp(d.filledAt) {
                InfoRow(label: "Last filled", value: Fmt.when(filled))
            }
        } header: {
            Text("What Deal Desk can see")
        }
    }

    // MARK: Trip

    private var tripSection: some View {
        Section("Trip") {
            row("Leaves from", item.portName)
            if let back = Fmt.day(d.returnDate) {
                InfoRow(label: "Back", value: Fmt.weekday(back), note: Fmt.fullDay(back))
            }
            if let route = item.route {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route").foregroundStyle(.secondary)
                    Text(route)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            row("Region", d.region, kind: .enrich)
            let days = (d.itineraryDays ?? []).filter { ($0.port ?? "").isEmpty == false }
            if !days.isEmpty {
                ForEach(Array(days.enumerated()), id: \.offset) { entry in
                    ItineraryRow(day: entry.element, fallbackDay: entry.offset + 1)
                }
            } else {
                row("Day by day", nil, kind: .enrich)
            }
            InfoRow(label: "Line", value: item.line)
            if let size = item.size {
                InfoRow(label: "Ship size", value: size.title, note: size.tonnage)
            }
        }
    }

    // MARK: Cabins

    @ViewBuilder
    private var cabinOptionsSection: some View {
        let options = (d.cabinOptions ?? []).filter { ($0.category ?? "").isEmpty == false }
        if !options.isEmpty {
            Section("Cabin options") {
                ForEach(Array(options.enumerated()), id: \.offset) { entry in
                    CabinOptionRow(option: entry.element, current: isCurrent(entry.element))
                }
            }
        }
    }

    private func isCurrent(_ option: CabinOption) -> Bool {
        guard let price = option.pricePP, price == d.pricePP else { return false }
        if let name = d.priceCategory, let category = option.category {
            return name.caseInsensitiveCompare(category) == .orderedSame
        }
        return option.type == d.cabin
    }

    // MARK: Alerts

    private var alertsSection: some View {
        Section {
            let alerts = d.alerts ?? []
            if alerts.isEmpty {
                row("Price alerts", nil, kind: .enrich)
            } else {
                ForEach(Array(alerts.enumerated()), id: \.offset) { entry in
                    InfoRow(label: entry.element.site ?? "Site", value: entry.element.stateTitle,
                            note: entry.element.note,
                            valueColor: entry.element.state == "set" ? Palette.fits
                                : (entry.element.state == "needs_jim" ? Palette.call : nil))
                }
            }
            ForEach(Array((d.alertPrices ?? []).enumerated()), id: \.offset) { entry in
                let price = entry.element
                InfoRow(label: price.source ?? "Alert email",
                        value: price.pricePP.map { "\(Fmt.usd($0)) pp" } ?? Fill.notShown,
                        note: [price.category, seenNote(price.seenAt)].compactMap { $0 }.joined(separator: " · "))
            }
        } header: {
            Text("Price alerts")
        } footer: {
            Text("Deal Desk sets a price alert for this sailing wherever a site offers one, and reads the alert emails that come back.")
        }
    }

    // MARK: Claude's note

    private var noteSection: some View {
        Section {
            if let note = d.brainNote?.trimmed, !note.isEmpty {
                TextBlock(text: note)
            } else {
                Text(item.missing(.enrich))
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Claude's note")
            }
        }
    }

    // MARK: Sources

    @ViewBuilder
    private var sourcesSection: some View {
        let sources = d.sources ?? []
        if !sources.isEmpty {
            Section("Sources") {
                ForEach(Array(sources.enumerated()), id: \.offset) { entry in
                    SourceRow(source: entry.element)
                }
            }
        }
    }

    // MARK: Jim's pick

    private var pickSection: some View {
        Section {
            InfoRow(label: "Line", value: item.line)
            InfoRow(label: "Ship", value: item.ship)
            if let day = item.sailDay {
                InfoRow(label: "Sails", value: Fmt.weekday(day), note: Fmt.fullDay(day))
            }
            if let nights = d.nights {
                InfoRow(label: "Nights", value: String(nights))
            }
            InfoRow(label: "Cabin", value: item.cabinType?.title ?? (d.cabin.map { Words.humanize($0) } ?? "Any"))
            InfoRow(label: "Category wanted", value: d.cabinName?.trimmed.isEmpty == false ? d.cabinName ?? "" : "any")
            if let port = d.port, !port.isEmpty {
                InfoRow(label: "Port", value: port)
            }
            if let note = d.note, !note.isEmpty {
                InfoRow(label: "Note", value: note)
            }
            if let added = item.added {
                InfoRow(label: "Added", value: Fmt.when(added), note: addedVia)
            }
        } header: {
            Text("Your pick")
        } footer: {
            Text("To change the ship, date, nights or cabin, stop tracking and track the new one.")
        }
    }

    private var addedVia: String? {
        switch d.addedVia {
        case "link"?: return "from a link"
        case "pick"?: return "picked in the app"
        case "seed"?: return "set up for you"
        default: return nil
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        let deal = d.dealId.flatMap { store.deal($0) }
        if deal != nil || item.link != nil {
            HStack(spacing: 10) {
                if let deal {
                    Button {
                        router.openDeal(deal.id)
                    } label: {
                        Label("See the deal", systemImage: "tag")
                            .font(.headline)
                            .foregroundStyle(Palette.onAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
                if let url = item.link {
                    Link(destination: url) {
                        Label("Open the page", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(.bar)
        }
    }
}

/// The tracked sailing's hero: the deep sea gradient, the ship large, and the dates, pick and price in white.
struct TrackedHero: View {
    let item: TrackedSailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.eyebrow.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
                Spacer(minLength: 8)
                TrackedStateBadge(item: item, onColor: true)
            }
            Text(item.ship)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                if !item.datesLine.isEmpty {
                    Text(item.datesLine)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.95))
                }
                if !item.pickLine.isEmpty {
                    Text(item.pickLine)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(3)
                }
                TrackedPriceLine(item: item, onColor: true)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroBackdrop(kind: nil) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Changes the extras on a tracked sailing: the exact category wanted, the port, the link and a note.
private struct TrackedEditSheet: View {
    let item: TrackedSailing
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var cabinName: String
    @State private var port: String
    @State private var link: String
    @State private var note: String

    init(item: TrackedSailing) {
        self.item = item
        _cabinName = State(initialValue: item.data.cabinName ?? "")
        _port = State(initialValue: item.data.port ?? "")
        _link = State(initialValue: item.data.link ?? "")
        _note = State(initialValue: item.data.note ?? "")
    }

    private var linkOK: Bool { link.trimmed.isEmpty || TrackPick.validLink(link) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exact category, e.g. Ocean View Balcony", text: capped($cabinName, 40))
                } header: {
                    Text("Category wanted")
                } footer: {
                    Text("With a category, the price is for that category whenever a source names it.")
                }
                Section("Leaves from") {
                    TextField("Port (optional)", text: capped($port, 30))
                }
                Section {
                    TextField("https://…", text: capped($link, 500))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Link")
                } footer: {
                    if !linkOK {
                        Text("The link must start with https://.").foregroundStyle(Palette.call)
                    } else {
                        Text("The page you found it on. Deal Desk never fetches it for you.")
                    }
                }
                Section("Note") {
                    TextField("Anything to remember", text: capped($note, 120), axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.editTracked(item, cabinName: cabinName, port: port, link: link, note: note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!linkOK)
                }
            }
        }
    }

    private func capped(_ binding: Binding<String>, _ limit: Int) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = String($0.prefix(limit)) })
    }
}

#Preview("Tracked") {
    NavigationStack {
        TrackedDetailView(trackedId: "trk-sample-star")
    }
    .environmentObject(Store.preview())
    .environmentObject(Router())
}
