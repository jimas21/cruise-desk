import SwiftUI

/// My Trip (DESIGN_V2 section 1, DESIGN_V3 section 3): every trip setting in plain words, with chips, steppers,
/// toggles and a slider: lines, ship sizes, Royal classes, length, cabin, who's going, budget, ports and regions,
/// dates and sail months, what counts as a deal, alerts and how often to check. The count at the top moves as you
/// change things; Save writes `prefs/trip`, the buckets re-sort at once, and Claude uses the same settings on its
/// next check. The v3 settings show only once the deal server can keep them.
struct TripEditor: View {
    let isNew: Bool
    /// What the screen opened with, so a phone with no `prefs/trip` yet cannot save the generic starting values
    /// untouched over the trip rules the brain is using.
    private let start: TripPrefs
    private let startAges: [Int?]
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TripPrefs
    @State private var ages: [Int?]
    @State private var newShip = ""
    @State private var newPort = ""
    @State private var newSkipPort = ""
    @State private var newRegion = ""

    init(start: TripPrefs, isNew: Bool = false) {
        self.isNew = isNew
        self.start = start
        _draft = State(initialValue: start)
        let known = start.childAges ?? []
        let firstAges = (0..<max(start.children, 0)).map { index -> Int? in
            index < known.count ? known[index] : nil
        }
        startAges = firstAges
        _ages = State(initialValue: firstAges)
    }

    /// Not set up yet and nothing changed: Save stays off, so the starting values never replace the real rules.
    private var untouchedStart: Bool { isNew && draft == start && ages == startAges }

    /// v5: ports and regions come from the catalog pickers, never a hand-kept list (CONTRACT_V5 section 1.7).
    private var pickers: Bool { store.has(.catalog5) }

    private var classIds: [String] { ShipClass.allCases.map { $0.rawValue } }
    private var classOptions: [ReasonOption] {
        ShipClass.allCases.map { ReasonOption(id: $0.rawValue, title: $0 == .other ? "Smaller ships" : $0.short) }
    }
    private var balconyIds: [String] { TripPrefs.balconyKinds.map { $0.id } }
    private var balconyOptions: [ReasonOption] { TripPrefs.balconyKinds.map { ReasonOption(id: $0.id, title: $0.title) } }

    private func names(_ base: [String], _ fromDeals: [String?], _ chosen: [String]...) -> [String] {
        var out: [String] = []
        for name in base + fromDeals.compactMap({ $0?.trimmed }) + chosen.flatMap({ $0 }) {
            guard !name.isEmpty, !out.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            out.append(name)
        }
        return out
    }

    private var portIds: [String] {
        names([], store.deals.map { $0.data.port }, draft.portsPreferred, draft.portsExcluded)
    }

    private var regionIds: [String] {
        names([], store.deals.map { $0.data.region }, draft.regions)
    }

    private func listBinding(_ path: WritableKeyPath<TripPrefs, [String]>, most: Int) -> Binding<[String]> {
        Binding(get: { draft[keyPath: path] },
                set: { draft[keyPath: path] = Array($0.map { $0.trimmed.capped(30) }.filter { !$0.isEmpty }.prefix(most)) })
    }

    var body: some View {
        NavigationStack {
            Form {
                countSection
                if store.isV3 {
                    linesSection
                } else {
                    comingSoonSection
                }
                shipsSection
                lengthSection
                cabinSection
                partySection
                budgetSection
                placesSection
                datesSection
                if store.isV3 {
                    dealsSection
                }
                alertsSection
                if store.isV3 {
                    checksSection
                }
                Section {
                    TextField("Anything else Claude should weigh", text: notes, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Notes for Claude")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("My Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled((showsRoyalClasses && draft.shipClasses.isEmpty) || draft.cabinTypes.isEmpty
                                  || untouchedStart)
                }
            }
        }
    }

    // MARK: Sections

    private var countSection: some View {
        let waiting = store.inbox.filter { $0.kind != .sale }
        let fitting = waiting.filter { TripCheck.evaluate($0, draft.cleaned(), softBudget: store.has(.sheet)).fits }.count
        return Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(fitting)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: fitting)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fitting == 1 ? "deal fits these settings" : "deals fit these settings")
                        .font(.subheadline.weight(.semibold))
                    Text("of \(waiting.count) sailings waiting")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        } footer: {
            if isNew {
                Text("Not set up yet. For my trip and Claude still use the trip rules on the server; the values below are only a starting point, not your trip. Save turns on once you change something, and then everything on this screen replaces those rules.")
            } else {
                Text("For my trip re-sorts as soon as you save. Claude uses the same settings on its next check.")
            }
        }
    }

    // MARK: v3: lines, sizes, what counts as a deal, checks

    private var comingSoonSection: some View {
        Section {
            Label {
                Text("Any cruise line, ship sizes, sail months and the kinds of deal to show arrive with the deal server's next update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.accent)
            }
        } header: {
            Text("Coming soon")
        }
    }

    private var linesSection: some View {
        Section {
            NavigationLink {
                LinesView(selection: linesBinding)
            } label: {
                ValueLabel(label: "Lines", value: draft.linesSummary)
            }
        } header: {
            Text("My lines")
        } footer: {
            Text("For my trip and Claude's checks cover these lines. Royal Caribbean is fully covered; others fill in as their sources come online.")
        }
    }

    /// My Lines saves on every change once the trip settings exist (CONTRACT_V5 R1); a first-run form saves with
    /// the rest, and a change there is enough to turn Save on.
    private var linesBinding: Binding<[String]> {
        Binding(get: { draft.effectiveLines }, set: { lines in
            draft.lines = lines
            if !isNew && store.trip != nil { store.saveLines(lines) }
        })
    }

    /// Royal Caribbean's own classes matter only while Royal Caribbean is one of the lines.
    private var showsRoyalClasses: Bool { !store.isV3 || draft.includesRoyal }

    private var sizeIds: [String] { ShipSize.allCases.map { $0.rawValue } }

    private var dealsSection: some View {
        Section {
            ChipPicker(options: DealType.allCases.map { ReasonOption(id: $0.rawValue, title: $0.title) },
                       selection: chosen(\.dealTypes, order: DealType.allCases.map { $0.rawValue }))
            Stepper(value: $draft.minPctUnder, in: 0...90, step: 5) {
                ValueLabel(label: "Under typical by", value: "\(draft.minPctUnder)% or more")
            }
            Toggle("Lowest score", isOn: minScoreOn)
            if let floor = draft.minScore {
                VStack(alignment: .leading, spacing: 4) {
                    ValueLabel(label: "Show deals from", value: "\(floor)")
                    Slider(value: minScoreValue, in: 0...100, step: 5)
                        .accessibilityLabel(Text("Lowest score"))
                        .accessibilityValue(Text("\(floor)"))
                }
            }
        } header: {
            Text("What counts as a deal")
        } footer: {
            Text("Best deals shows a deal that is at least one of the kinds picked; none picked means every kind. The lowest score applies to both lists; sales always show.")
        }
    }

    private var minScoreOn: Binding<Bool> {
        Binding(get: { draft.minScore != nil }, set: { draft.minScore = $0 ? 60 : nil })
    }

    private var minScoreValue: Binding<Double> {
        Binding(get: { Double(draft.minScore ?? 60) }, set: { draft.minScore = Int($0.rounded()) })
    }

    private var checksSection: some View {
        Section {
            Picker("Check every", selection: $draft.refreshMinutes) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("60 min").tag(60)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("Check every"))
        } header: {
            Text("Background checks")
        } footer: {
            Text("How often Deal Desk re-reads the sources that allow it, your tracked sailings first. Opening the app also asks for a fresh look.")
        }
    }

    private var monthIds: [String] { (1...12).map { String($0) } }

    private var sailMonthsBinding: Binding<Set<String>> {
        Binding(get: { Set(draft.sailMonths.map { String($0) }) },
                set: { picked in draft.sailMonths = (1...12).filter { picked.contains(String($0)) } })
    }

    // MARK: Ships

    private var shipsSection: some View {
        Group {
            if store.isV3 {
                Section {
                    ChipPicker(options: ShipSize.allCases.map { ReasonOption(id: $0.rawValue, title: $0.title) },
                               selection: chosen(\.shipSizes, order: sizeIds))
                } header: {
                    Text("Ship size")
                } footer: {
                    Text("None picked means any size. Small is under 70k tons, mid-size to 120k, large to 180k, mega above.")
                }
            }
            if showsRoyalClasses {
                Section {
                    ChipPicker(options: classOptions, selection: chosen(\.shipClasses, order: classIds))
                    let groups = store.catalog.classGroups(line: CruiseLine.royal)
                    if !groups.isEmpty {
                        DisclosureGroup("Ships in each class") {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title)
                                        .font(.subheadline.weight(.semibold))
                                    ClassShipsLine(group: group)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } header: {
                    Text(store.isV3 ? "Royal Caribbean classes" : "Ship classes")
                } footer: {
                    if draft.shipClasses.isEmpty {
                        Text("Pick at least one.").foregroundStyle(Palette.call)
                    } else {
                        Text("Icon is the newest and biggest, then Oasis, then Quantum.")
                    }
                }
                Section("Rank these first") {
                    ChipPicker(options: classOptions.filter { draft.shipClasses.contains($0.id) },
                               selection: chosen(\.preferredClasses, order: classIds))
                }
            }
            Section("Ships to skip") {
                ForEach(draft.excludeShips, id: \.self) { ship in
                    Text(ship)
                }
                .onDelete { draft.excludeShips.remove(atOffsets: $0) }
                AddRow(placeholder: "Add a ship to skip", text: $newShip) {
                    add(newShip, to: \.excludeShips, cap: 40, most: 30)
                    newShip = ""
                }
            }
        }
    }

    private var lengthSection: some View {
        Section("Length") {
            Stepper(value: $draft.nightsMin, in: 1...min(max(draft.nightsMax, 1), 30)) {
                ValueLabel(label: "At least", value: Fmt.nights(draft.nightsMin))
            }
            Stepper(value: $draft.nightsMax, in: min(max(draft.nightsMin, 1), 30)...30) {
                ValueLabel(label: "At most", value: Fmt.nights(draft.nightsMax))
            }
            Toggle("Rank longer trips first", isOn: preferLonger)
            if draft.nightsPreferredMin != nil {
                Stepper(value: preferredNights, in: 1...30) {
                    ValueLabel(label: "Longer means", value: "\(preferredNights.wrappedValue)+ nights")
                }
            }
        }
    }

    private var cabinSection: some View {
        Group {
            Section {
                ChipPicker(options: CabinType.allOptions, selection: chosen(\.cabinTypes, order: CabinType.allIds))
                Toggle("A balcony must face the ocean", isOn: $draft.requireOceanView)
            } header: {
                Text("Cabin")
            } footer: {
                if draft.cabinTypes.isEmpty {
                    Text("Pick at least one.").foregroundStyle(Palette.call)
                }
            }
            Section {
                ChipPicker(options: balconyOptions, selection: chosen(\.excludeBalconyTypes, order: balconyIds))
            } header: {
                Text("Balconies to skip")
            } footer: {
                Text("A deal for one of these doesn't count as a balcony for this trip.")
            }
        }
    }

    private var partySection: some View {
        Section("Who's going") {
            Stepper(value: $draft.adults, in: 1...8) {
                ValueLabel(label: "Adults", value: "\(draft.adults)")
            }
            Stepper(value: children, in: 0...8) {
                ValueLabel(label: "Children", value: "\(draft.children)")
            }
            ForEach(0..<draft.children, id: \.self) { index in
                Picker("Child \(index + 1) age", selection: age(index)) {
                    Text("Not set").tag(-1)
                    ForEach(0..<18, id: \.self) { years in
                        Text(years == 0 ? "Under 1" : "\(years)").tag(years)
                    }
                }
            }
        }
    }

    /// v5 (the server lists `sheet`): the budget is a soft target, never a filter.
    private var softBudget: Bool { store.has(.sheet) }

    private var budgetSection: some View {
        Section {
            MoneyField(label: softBudget ? "Target for the trip" : "Most for the trip", value: $draft.budgetTotal)
            Toggle("Trade-off zone", isOn: tradeoffOn)
            if draft.tradeoffBudget != nil {
                MoneyField(label: "Comfortable up to", value: tradeoff)
            }
            HStack {
                Text("Home airport")
                Spacer(minLength: 8)
                TextField("Code", text: airport)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 90)
            }
        } header: {
            Text("Budget")
        } footer: {
            Text(budgetFooter)
        }
    }

    private var budgetFooter: String {
        guard softBudget else {
            return "Totals are for everyone going, taxes and tips in, before flights. Between the two amounts a deal still fits, marked as a trade-off."
        }
        let counts = store.trip?.budgetBasis == "trip"
            ? "It counts the whole trip for everyone going: fare, taxes, tips, what you usually buy, flights and the hotel night."
            : "It counts the cabin for everyone going: fare and taxes, before tips and flights."
        return "A soft target, never a filter: a sailing over it still shows, and its trip cost says how far over (\"$640 over your \(Fmt.usd(draft.budgetTotal)) target\"). Less is better, so the verdict leans to cheaper sailings. \(counts) Change what it counts in Settings > Trip cost."
    }

    @ViewBuilder
    private var placesSection: some View {
        if pickers {
            Section {
                PickerLink(label: "Favourite ports",
                           value: draft.portsPreferred.isEmpty ? "None" : ListText.join(draft.portsPreferred)) {
                    PortPickerScreen(title: "Favourite ports", kind: .embark,
                                     selection: listBinding(\.portsPreferred, most: 20), most: 20,
                                     footer: "Sailings from these rank first; others still count.")
                }
                PickerLink(label: "Ports to skip",
                           value: draft.portsExcluded.isEmpty ? "None" : ListText.join(draft.portsExcluded)) {
                    PortPickerScreen(title: "Ports to skip", kind: .any,
                                     selection: listBinding(\.portsExcluded, most: 20), most: 20)
                }
                PickerLink(label: "Regions", value: draft.regions.isEmpty ? "Anywhere" : ListText.join(draft.regions)) {
                    RegionPickerScreen(selection: listBinding(\.regions, most: 12))
                }
            } header: {
                Text("Ports and regions")
            } footer: {
                Text("From Deal Desk's catalog of every line's ports. No region picked means anywhere.")
            }
        } else {
            legacyPlacesSection
        }
    }

    private var legacyPlacesSection: some View {
        Group {
            Section {
                ChipPicker(options: portIds.map { ReasonOption(id: $0, title: $0) },
                           selection: chosen(\.portsPreferred, order: portIds))
                AddRow(placeholder: "Add a port", text: $newPort) {
                    add(newPort, to: \.portsPreferred, cap: 30, most: 20)
                    newPort = ""
                }
            } header: {
                Text("Favourite ports")
            } footer: {
                Text("Sailings from these rank first; others still count.")
            }
            Section {
                ChipPicker(options: portIds.map { ReasonOption(id: $0, title: $0) },
                           selection: chosen(\.portsExcluded, order: portIds))
                AddRow(placeholder: "Add a port to skip", text: $newSkipPort) {
                    add(newSkipPort, to: \.portsExcluded, cap: 30, most: 20)
                    newSkipPort = ""
                }
            } header: {
                Text("Ports to skip")
            }
            Section {
                ChipPicker(options: regionIds.map { ReasonOption(id: $0, title: $0) },
                           selection: chosen(\.regions, order: regionIds))
                AddRow(placeholder: "Add a region", text: $newRegion) {
                    add(newRegion, to: \.regions, cap: 30, most: 12)
                    newRegion = ""
                }
            } header: {
                Text("Regions")
            } footer: {
                Text("None picked means anywhere.")
            }
        }
    }

    private var datesSection: some View {
        Section {
            Toggle("Only certain dates", isOn: datesOn)
            if draft.dateFrom != nil || draft.dateTo != nil {
                DatePicker("From", selection: day(\.dateFrom, fallback: Date()), displayedComponents: .date)
                DatePicker("To", selection: day(\.dateTo, fallback: Date().addingTimeInterval(365 * 86400)),
                           displayedComponents: .date)
            }
            Toggle("Avoid holiday weeks", isOn: $draft.avoidHolidays)
            if store.isV3 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sail months")
                    ChipPicker(options: monthIds.map { ReasonOption(id: $0, title: Fmt.monthShort(Int($0) ?? 0)) },
                               selection: sailMonthsBinding)
                }
            }
        } header: {
            Text("When")
        } footer: {
            Text(store.isV3 ? "Holiday weeks: Thanksgiving, Christmas to New Year, and July 4th. No sail month picked means any month."
                            : "Holiday weeks: Thanksgiving, Christmas to New Year, and July 4th.")
        }
    }

    private var alertsSection: some View {
        Section {
            Toggle("Deals that fit my trip", isOn: $draft.alertForMyTrip)
            Toggle("Must-see deals", isOn: $draft.alertMustSee)
            VStack(alignment: .leading, spacing: 4) {
                ValueLabel(label: "Must-see from score", value: "\(draft.mustSeeMinScore)")
                Slider(value: mustSee, in: 50...100, step: 5)
                    .accessibilityLabel(Text("Must-see from score"))
                    .accessibilityValue(Text("\(draft.mustSeeMinScore)"))
            }
            Toggle("Quiet hours", isOn: quietOn)
            if draft.quietHoursStart != nil || draft.quietHoursEnd != nil {
                DatePicker("From", selection: clock(\.quietHoursStart, fallback: "22:00"), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: clock(\.quietHoursEnd, fallback: "07:00"), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Claude reads these with the rest of My Trip on its next check.")
        }
    }

    // MARK: Saving

    private func save() {
        var prefs = draft
        let set = ages.compactMap { $0 }
        prefs.childAges = set.isEmpty ? nil : set
        store.saveTrip(prefs)
        dismiss()
    }

    private func add(_ text: String, to key: WritableKeyPath<TripPrefs, [String]>, cap: Int, most: Int) {
        let value = text.trimmed.capped(cap)
        guard !value.isEmpty, draft[keyPath: key].count < most,
              !draft[keyPath: key].contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        withAnimation(Motion.snappy) { draft[keyPath: key].append(value) }
        Haptics.tap()
    }

    // MARK: Bindings

    /// A chip set over one of the trip's lists, kept in `order` (then anything else, in the order it was added).
    private func chosen(_ key: WritableKeyPath<TripPrefs, [String]>, order: [String]) -> Binding<Set<String>> {
        Binding(
            get: { Set(draft[keyPath: key]) },
            set: { picked in
                let current = draft[keyPath: key]
                let ordered = order.filter { picked.contains($0) }
                let extra = current.filter { picked.contains($0) && !order.contains($0) }
                draft[keyPath: key] = ordered + extra
            }
        )
    }

    private var preferLonger: Binding<Bool> {
        Binding(get: { draft.nightsPreferredMin != nil },
                set: { draft.nightsPreferredMin = $0 ? max(draft.nightsMin, min(5, draft.nightsMax)) : nil })
    }

    private var preferredNights: Binding<Int> {
        Binding(get: { draft.nightsPreferredMin ?? draft.nightsMin }, set: { draft.nightsPreferredMin = $0 })
    }

    private var children: Binding<Int> {
        Binding(get: { draft.children }, set: { count in
            draft.children = count
            if ages.count < count {
                ages.append(contentsOf: Array(repeating: nil, count: count - ages.count))
            } else if ages.count > count {
                ages = Array(ages.prefix(count))
            }
        })
    }

    private func age(_ index: Int) -> Binding<Int> {
        Binding(
            get: { index < ages.count ? (ages[index] ?? -1) : -1 },
            set: { years in
                while ages.count <= index { ages.append(nil) }
                ages[index] = years < 0 ? nil : years
            }
        )
    }

    private var tradeoffOn: Binding<Bool> {
        Binding(get: { draft.tradeoffBudget != nil },
                set: { draft.tradeoffBudget = $0 ? max(draft.budgetTotal - 500, 0) : nil })
    }

    private var tradeoff: Binding<Int> {
        Binding(get: { draft.tradeoffBudget ?? draft.budgetTotal }, set: { draft.tradeoffBudget = $0 })
    }

    private var airport: Binding<String> {
        Binding(get: { draft.homeAirport ?? "" },
                set: { draft.homeAirport = String($0.uppercased().prefix(4)) })
    }

    private var notes: Binding<String> {
        Binding(get: { draft.notes ?? "" }, set: { draft.notes = String($0.prefix(500)) })
    }

    private var datesOn: Binding<Bool> {
        Binding(get: { draft.dateFrom != nil || draft.dateTo != nil }, set: { on in
            if on {
                draft.dateFrom = Fmt.isoDay(Date())
                draft.dateTo = Fmt.isoDay(Date().addingTimeInterval(365 * 86400))
            } else {
                draft.dateFrom = nil
                draft.dateTo = nil
            }
        })
    }

    private func day(_ key: WritableKeyPath<TripPrefs, String?>, fallback: Date) -> Binding<Date> {
        Binding(get: { Fmt.day(draft[keyPath: key]) ?? fallback }, set: { draft[keyPath: key] = Fmt.isoDay($0) })
    }

    private var mustSee: Binding<Double> {
        Binding(get: { Double(draft.mustSeeMinScore) }, set: { draft.mustSeeMinScore = Int($0.rounded()) })
    }

    private var quietOn: Binding<Bool> {
        Binding(get: { draft.quietHoursStart != nil || draft.quietHoursEnd != nil }, set: { on in
            draft.quietHoursStart = on ? "22:00" : nil
            draft.quietHoursEnd = on ? "07:00" : nil
        })
    }

    private func clock(_ key: WritableKeyPath<TripPrefs, String?>, fallback: String) -> Binding<Date> {
        Binding(get: { Fmt.clock(draft[keyPath: key]) ?? Fmt.clock(fallback) ?? Date() },
                set: { draft[keyPath: key] = Fmt.clockText($0) })
    }
}

/// "Most for the trip        $ 3,000" with a number pad.
private struct MoneyField: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Spacer(minLength: 8)
            Text("$").foregroundStyle(.secondary)
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 110)
        }
    }
}

/// A text field with an Add button, for ships, ports and regions not in the chips.
private struct AddRow: View {
    let placeholder: String
    @Binding var text: String
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .onSubmit(add)
            Button("Add", action: add)
                .buttonStyle(.borderless)
                .disabled(text.trimmed.isEmpty)
        }
    }
}

#Preview("My Trip") {
    TripEditor(start: Samples.trip)
        .environmentObject(Store.preview())
}
