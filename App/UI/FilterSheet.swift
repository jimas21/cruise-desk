import SwiftUI

/// Narrows both buckets: line, ship size, Royal class, nights, cabin type, where it leaves from, sail month, the
/// kind of deal, the lowest score and the most for the trip. Nothing picked means "any". Changes apply on Done.
struct FilterSheet: View {
    @Binding var filters: DealFilters
    let deals: [Deal]
    /// My Lines, offered first.
    let myLines: [String]
    let minPctUnder: Int
    /// Does a deal pass My Trip (for the "Fits my trip" kind).
    let fits: (Deal) -> Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var draft: DealFilters

    init(filters: Binding<DealFilters>, deals: [Deal], myLines: [String] = [], minPctUnder: Int = 15,
         fits: @escaping (Deal) -> Bool = { _ in false }) {
        _filters = filters
        self.deals = deals
        self.myLines = myLines
        self.minPctUnder = minPctUnder
        self.fits = fits
        _draft = State(initialValue: filters.wrappedValue)
    }

    private static let totals = [2000, 2500, 3000, 3500, 4000, 5000, 7500, 10000]
    private static let scores = [50, 60, 70, 80, 90]

    private var matching: Int {
        deals.filter { draft.matches($0, fits: fits($0), minPctUnder: minPctUnder) }.count
    }

    /// "Royal Caribbean: tracking live · Celebrity: limited data", from the deal server's catalog (v3 only).
    private var coverageNote: String? {
        let catalog = CatalogIndex.current
        guard catalog.isV3 else { return nil }
        let parts = lineIds.compactMap { name -> String? in
            guard let state = catalog.line(name)?.coverageState else { return nil }
            return "\(name): \(state.title.lowercased())"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// My Lines, then any other line a deal is on, then anything already picked.
    private var lineIds: [String] {
        var out: [String] = []
        for name in myLines + deals.map({ $0.line }) + draft.lines {
            if !out.contains(where: { CruiseLine.same($0, name) }) { out.append(name) }
        }
        return out
    }

    private var placeIds: [String] {
        var seen: [String] = []
        for deal in deals {
            for value in [deal.data.port, deal.data.region] {
                if let place = value?.trimmed, !place.isEmpty, !seen.contains(place) { seen.append(place) }
            }
        }
        return seen.sorted() + draft.places.filter { !seen.contains($0) }
    }

    private var monthIds: [String] {
        let present = Set(deals.compactMap { $0.data.sailDate.map { String($0.prefix(7)) } })
        return present.union(draft.months).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Showing") {
                        Text("\(matching) of \(deals.count) deals")
                            .monospacedDigit()
                    }
                }
                Section {
                    if pickers {
                        PickerLink(label: "Lines", value: draft.lines.isEmpty ? "Any line" : ListText.join(draft.lines)) {
                            LinesPickerScreen(selection: $draft.lines, dealCounts: dealCounts,
                                              footer: "Every line Deal Desk knows, with how many deals it has on the board now. None picked means any line.")
                        }
                    } else {
                        ChipPicker(options: lineIds.map { ReasonOption(id: $0, title: $0) },
                                   selection: chosen(\.lines, order: lineIds))
                    }
                } header: {
                    Text("Line")
                } footer: {
                    if let coverage = coverageNote, !pickers {
                        Text(coverage)
                    }
                }
                Section {
                    ChipPicker(options: ShipSize.allCases.map { ReasonOption(id: $0.rawValue, title: $0.title) },
                               selection: chosen(\.sizes, order: ShipSize.allCases.map { $0.rawValue }))
                } header: {
                    Text("Ship size")
                } footer: {
                    Text("Small is under 70k tons, mid-size to 120k, large to 180k, mega above. A ship of unknown size still shows.")
                }
                Section {
                    ChipPicker(options: ShipClass.allCases.map { ReasonOption(id: $0.rawValue, title: $0.short) },
                               selection: chosen(\.shipClasses, order: ShipClass.allCases.map { $0.rawValue }))
                } header: {
                    Text("Royal Caribbean class")
                } footer: {
                    Text("Picking a class keeps Royal Caribbean ships of that class only.")
                }
                Section("Nights") {
                    Stepper(value: nightsMin, in: 0...30) {
                        ValueLabel(label: "At least", value: draft.nightsMin.map { Fmt.nights($0) } ?? "Any")
                    }
                    Stepper(value: nightsMax, in: 1...31) {
                        ValueLabel(label: "At most", value: draft.nightsMax.map { Fmt.nights($0) } ?? "Any")
                    }
                }
                Section("Cabin") {
                    ChipPicker(options: CabinType.allOptions, selection: chosen(\.cabinTypes, order: CabinType.allIds))
                }
                if pickers {
                    Section {
                        PickerLink(label: "Leaving from", value: portPlaces.isEmpty ? "Any port" : ListText.join(portPlaces)) {
                            PortPickerScreen(title: "Leaving from", kind: .embark, selection: portPlacesBinding)
                        }
                        PickerLink(label: "Region", value: regionPlaces.isEmpty ? "Anywhere" : ListText.join(regionPlaces)) {
                            RegionPickerScreen(selection: regionPlacesBinding)
                        }
                    } header: {
                        Text("Where")
                    } footer: {
                        Text("Ports and regions come from Deal Desk's catalog, not just the deals on the board.")
                    }
                } else if !placeIds.isEmpty {
                    Section("Leaving from") {
                        ChipPicker(options: placeIds.map { ReasonOption(id: $0, title: $0) },
                                   selection: chosen(\.places, order: placeIds))
                    }
                }
                if !monthIds.isEmpty {
                    Section("Sail month") {
                        ChipPicker(options: monthIds.map { ReasonOption(id: $0, title: Fmt.monthTitle($0)) },
                                   selection: chosen(\.months, order: monthIds))
                    }
                }
                Section("Kind of deal") {
                    ChipPicker(options: DealType.allCases.map { ReasonOption(id: $0.rawValue, title: $0.title) },
                               selection: chosen(\.dealTypes, order: DealType.allCases.map { $0.rawValue }))
                }
                Section {
                    Picker("Lowest score", selection: minScore) {
                        Text("Any").tag(0)
                        ForEach(FilterSheet.scores, id: \.self) { score in
                            Text("\(score)+").tag(score)
                        }
                    }
                } footer: {
                    Text("Sales always show.")
                }
                Section {
                    Picker("Most for the trip", selection: maxTotal) {
                        Text("Any").tag(0)
                        ForEach(FilterSheet.totals, id: \.self) { total in
                            Text(Fmt.usd(total)).tag(total)
                        }
                    }
                } footer: {
                    Text("Uses the deal's trip cost or total for your party when it has one, otherwise the per-person price times the party.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        filters = draft
                        Haptics.tap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear all") {
                        withAnimation(Motion.snappy) { draft = DealFilters() }
                    }
                    .disabled(!draft.isActive)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: v5 catalog pickers (CONTRACT_V5 section 1.7)

    private var pickers: Bool { store.has(.catalog5) }

    /// Deals on the board per line, for the line picker.
    private var dealCounts: [String: Int] {
        var out: [String: Int] = [:]
        for deal in deals { out[deal.line, default: 0] += 1 }
        return out
    }

    private func isRegion(_ place: String) -> Bool { store.catalog.region(named: place) != nil }
    private var portPlaces: [String] { draft.places.filter { !isRegion($0) } }
    private var regionPlaces: [String] { draft.places.filter { isRegion($0) } }

    private var portPlacesBinding: Binding<[String]> {
        Binding(get: { portPlaces }, set: { draft.places = $0 + regionPlaces })
    }

    private var regionPlacesBinding: Binding<[String]> {
        Binding(get: { regionPlaces }, set: { draft.places = portPlaces + $0 })
    }

    // MARK: Bindings

    /// A chip set over one of the filter's lists, keeping `order` (then anything else, sorted).
    private func chosen(_ key: WritableKeyPath<DealFilters, [String]>, order: [String]) -> Binding<Set<String>> {
        Binding(
            get: { Set(draft[keyPath: key]) },
            set: { picked in
                draft[keyPath: key] = order.filter { picked.contains($0) } + picked.filter { !order.contains($0) }.sorted()
            }
        )
    }

    private var nightsMin: Binding<Int> {
        Binding(get: { draft.nightsMin ?? 0 }, set: { draft.nightsMin = $0 == 0 ? nil : $0 })
    }

    /// 31 reads as "Any".
    private var nightsMax: Binding<Int> {
        Binding(get: { draft.nightsMax ?? 31 }, set: { draft.nightsMax = $0 >= 31 ? nil : $0 })
    }

    private var minScore: Binding<Int> {
        Binding(get: { draft.minScore ?? 0 }, set: { draft.minScore = $0 == 0 ? nil : $0 })
    }

    private var maxTotal: Binding<Int> {
        Binding(get: { draft.maxTotal ?? 0 }, set: { draft.maxTotal = $0 == 0 ? nil : $0 })
    }
}

/// "At least        6 nights": a label on the left, its value quieter on the right.
struct ValueLabel: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

extension CabinType {
    static let allIds = ["interior", "oceanview", "balcony", "suite"]

    static var allOptions: [ReasonOption] {
        allIds.compactMap { id in CabinType(rawValue: id).map { ReasonOption(id: id, title: $0.title) } }
    }
}

#Preview("Filters") {
    FilterSheet(filters: .constant(DealFilters()), deals: Samples.deals)
        .environmentObject(Store.preview())
}
