import SwiftUI

/// My Trip (DESIGN_V2 section 1): every trip setting in plain words, with chips, steppers, toggles and a slider.
/// The count at the top moves as you change things; Save writes `prefs/trip`, the buckets re-sort at once, and
/// Claude uses the same settings on its next check.
struct TripEditor: View {
    let isNew: Bool
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
        _draft = State(initialValue: start)
        let known = start.childAges ?? []
        _ages = State(initialValue: (0..<max(start.children, 0)).map { index -> Int? in
            index < known.count ? known[index] : nil
        })
    }

    /// Homeports the line sails from (public, not anyone's trip); the deals' own ports are added to these.
    private static let commonPorts = ["Seattle", "Vancouver", "Los Angeles", "San Diego", "Galveston", "New Orleans",
                                      "Miami", "Fort Lauderdale", "Port Canaveral", "Tampa", "Cape Liberty",
                                      "Baltimore", "Boston", "San Juan"]
    private static let commonRegions = ["Caribbean", "Bahamas", "Mexico", "Alaska", "Hawaii", "Pacific Coast",
                                        "Bermuda", "Canada & New England", "Europe", "Asia", "Australia"]

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
        names(TripEditor.commonPorts, store.deals.map { $0.data.port }, draft.portsPreferred, draft.portsExcluded)
    }

    private var regionIds: [String] {
        names(TripEditor.commonRegions, store.deals.map { $0.data.region }, draft.regions)
    }

    var body: some View {
        NavigationStack {
            Form {
                countSection
                shipsSection
                lengthSection
                cabinSection
                partySection
                budgetSection
                placesSection
                datesSection
                alertsSection
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
                        .disabled(draft.shipClasses.isEmpty || draft.cabinTypes.isEmpty)
                }
            }
        }
    }

    // MARK: Sections

    private var countSection: some View {
        let waiting = store.inbox.filter { $0.kind != .sale }
        let fitting = waiting.filter { TripCheck.evaluate($0, draft.cleaned()).fits }.count
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
                Text("Claude is still using the trip rules it started with. Saving here takes over: these become the rules for For my trip and for Claude's next check.")
            } else {
                Text("For my trip re-sorts as soon as you save. Claude uses the same settings on its next check.")
            }
        }
    }

    private var shipsSection: some View {
        Group {
            Section {
                ChipPicker(options: classOptions, selection: chosen(\.shipClasses, order: classIds))
            } header: {
                Text("Ship classes")
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

    private var budgetSection: some View {
        Section {
            MoneyField(label: "Most for the trip", value: $draft.budgetTotal)
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
            Text("Totals are for everyone going, taxes and tips in, before flights. Between the two amounts a deal still fits, marked as a trade-off.")
        }
    }

    private var placesSection: some View {
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
        } header: {
            Text("When")
        } footer: {
            Text("Holiday weeks: Thanksgiving, Christmas to New Year, and July 4th.")
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
