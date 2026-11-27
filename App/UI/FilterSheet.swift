import SwiftUI

/// Narrows both buckets: ship class, nights, cabin type, where it leaves from, sail month and the most for the
/// trip. Nothing picked means "any". Changes apply on Done.
struct FilterSheet: View {
    @Binding var filters: DealFilters
    let deals: [Deal]
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DealFilters

    init(filters: Binding<DealFilters>, deals: [Deal]) {
        _filters = filters
        self.deals = deals
        _draft = State(initialValue: filters.wrappedValue)
    }

    private static let totals = [2000, 2500, 3000, 3500, 4000, 5000, 7500, 10000]

    private var matching: Int { deals.filter { draft.matches($0) }.count }

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
                Section("Ship class") {
                    ChipPicker(options: ShipClass.allCases.map { ReasonOption(id: $0.rawValue, title: $0.short) },
                               selection: chosen(\.shipClasses, order: ShipClass.allCases.map { $0.rawValue }))
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
                if !placeIds.isEmpty {
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
                Section {
                    Picker("Most for the trip", selection: maxTotal) {
                        Text("Any").tag(0)
                        ForEach(FilterSheet.totals, id: \.self) { total in
                            Text(Fmt.usd(total)).tag(total)
                        }
                    }
                } footer: {
                    Text("Uses the total for 3 when the deal has one, otherwise the per-person price times 3.")
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
}
