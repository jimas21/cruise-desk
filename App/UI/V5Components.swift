import SwiftUI

// MARK: - The visible default (CONTRACT_V5 section 1.7)

/// "Showing Royal Caribbean only (the default) · Change": shown while Jim has never saved his lines, so nothing
/// narrows silently. Change opens My Lines, which saves on every change.
struct DefaultLinesBanner: View {
    @EnvironmentObject private var store: Store
    @State private var showLines = false

    var body: some View {
        if store.showsDefaultLinesBanner {
            Button {
                showLines = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.accent)
                    (Text("Showing Royal Caribbean only (the default) · ")
                        .foregroundStyle(Color.primary)
                        + Text("Change").foregroundStyle(Palette.accent).bold())
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Showing Royal Caribbean only, the default"))
            .accessibilityHint(Text("Opens My Lines to choose more lines"))
            .sheet(isPresented: $showLines) {
                NavigationStack {
                    LinesView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showLines = false }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Verdict and basis

extension VerdictWord {
    var color: Color {
        switch self {
        case .book: return Palette.fits
        case .wait: return Palette.accent
        case .skip: return Color(uiColor: .systemRed)
        case .yourCall: return Palette.call
        case .unknown: return .secondary
        }
    }
}

/// BOOK / WAIT / SKIP / YOUR CALL, as a small filled capsule. An unknown label is shown neutrally.
struct VerdictChip: View {
    let label: String?
    var small = false

    var body: some View {
        let word = VerdictWord(label)
        Text(word.title)
            .font((small ? Font.caption2 : Font.caption).weight(.bold))
            .tracking(0.5)
            .foregroundStyle(word.color)
            .padding(.horizontal, small ? 7 : 9)
            .padding(.vertical, small ? 2 : 4)
            .background(word.color.opacity(0.14), in: Capsule())
            .fixedSize()
            .accessibilityLabel(Text("Verdict: \(word.spoken)"))
    }
}

/// "read · Costco", "rule · Disney 2026", "estimate · 3 days old", "not shown".
struct BasisTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .lineLimit(1)
            .accessibilityLabel(Text("Basis: \(text)"))
    }
}

/// The trip cost on a list row: "Trip $5,980–7,240 · YOUR CALL".
struct TripCostLine: View {
    let cost: TripCost

    var body: some View {
        if let range = cost.range {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Trip")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(range)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if cost.complete == false {
                    Text("+ not shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if cost.verdict != nil {
                    VerdictChip(label: cost.verdict, small: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Ship classes, every ship named (Jim: never "+ N more")

/// "2 ships in this class: Norwegian Getaway, Norwegian Breakaway", each name tappable to open that ship.
struct ClassShipsLine: View {
    let group: ShipClassGroup
    /// The ship this screen is about, shown in bold.
    var current: String? = nil
    /// Opens a ship; when nil the line opens its own ship sheet.
    var open: ((ShipRef) -> Void)? = nil
    @State private var shown: ShipRef?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.countText + ":")
                .font(.footnote)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(Array(group.shipNames.enumerated()), id: \.offset) { item in
                    let name = item.element
                    let isLast = item.offset == group.shipNames.count - 1
                    let mine = current.map { Slug.ship($0) == Slug.ship(name) } ?? false
                    Button {
                        let ref = ShipRef(line: group.line, name: name)
                        if let open { open(ref) } else { shown = ref }
                    } label: {
                        Text(name + (isLast ? "" : ","))
                            .font(.footnote.weight(mine ? .semibold : .regular))
                            .foregroundStyle(Palette.accent)
                            .underline(!mine, color: Palette.accent.opacity(0.35))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(name))
                    .accessibilityHint(Text("Opens \(name)"))
                }
            }
        }
        .sheet(item: $shown) { ref in
            ShipSheet(ref: ref)
        }
    }
}

/// The ship class row of a detail screen: "Ship class  Breakaway" and every ship of the class below it.
struct ClassShipsRow: View {
    let group: ShipClassGroup
    var current: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                Text(group.name)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text("Ship class").foregroundStyle(.secondary)
            }
            ClassShipsLine(group: group, current: current)
        }
    }
}

/// One ship: its line and class (every sister named), size, guests and year, its class photo drawn to scale
/// beside the ship Jim sailed last, and the sailings Deal Desk has seen.
struct ShipSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var current: ShipRef
    @State private var sailings: [FareSailing] = []
    @State private var loaded = false

    init(ref: ShipRef) {
        _current = State(initialValue: ref)
    }

    private var ship: CatalogShip? { store.catalog.ship(line: current.line, named: current.name) }
    private var group: ShipClassGroup? { store.catalog.classGroup(line: current.line, ship: current.name) }

    var body: some View {
        NavigationStack {
            List {
                if ShipScaleStrip.available(store, line: current.line, ship: current.name) {
                    Section {
                        ShipScaleStrip(line: current.line, ship: current.name)
                    }
                }
                Section("Ship") {
                    InfoRow(label: "Line", value: current.line)
                    if let group {
                        LabeledContent {
                            Text(group.name)
                        } label: {
                            Text("Class").foregroundStyle(.secondary)
                        }
                        ClassShipsLine(group: group, current: current.name) { ref in
                            withAnimation(Motion.snappy) { current = ref }
                        }
                    }
                    if let tier = ship?.tier {
                        InfoRow(label: "Size", value: tier.shipTitle, note: tier.tonnage)
                    }
                    if let gt = ship?.gt {
                        InfoRow(label: "Gross tonnage", value: Fmt.usd(gt).replacingOccurrences(of: "$", with: ""))
                    }
                    if let length = ship?.lengthFt {
                        InfoRow(label: "Length", value: ShipScale.lengthText(length))
                    }
                    if let guests = ship?.passengers {
                        InfoRow(label: "Guests", value: Fmt.usd(guests).replacingOccurrences(of: "$", with: ""),
                                note: "2 to a cabin")
                    }
                    if let year = ship?.maidenYear {
                        InfoRow(label: "First sailed", value: String(year))
                    }
                    if ship == nil {
                        Text("Deal Desk's catalog doesn't list this ship yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if store.isV3 {
                    Section {
                        if !loaded {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Looking for known sailings…").foregroundStyle(.secondary)
                            }
                        } else if sailings.isEmpty {
                            Text("No upcoming sailings of \(current.name) in Deal Desk's fare data yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(sailings.prefix(8)) { sailing in
                            ShipSailingRow(sailing: sailing)
                        }
                    } header: {
                        Text("Sailings Deal Desk has seen")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: current) {
                await store.loadShipPhotos()
                loaded = false
                sailings = await store.knownSailings(line: current.line, ship: current.name)
                loaded = true
            }
        }
    }
}

private struct ShipSailingRow: View {
    let sailing: FareSailing

    private var cheapest: Int? {
        (sailing.bestByClass ?? [:]).values.compactMap { $0.pricePP }.filter { $0 > 0 }.min()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let day = sailing.sailDay {
                    Text(Fmt.fullDay(day))
                        .monospacedDigit()
                }
                Text([sailing.nights.map { Fmt.nights($0) }, sailing.embarkPort].compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let cheapest {
                Text("from \(Fmt.usd(cheapest)) pp")
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Catalog pickers (one component for lines, ports and regions; CONTRACT_V5 section 1.7)

/// A row that opens a picker: the label, then what is chosen in full below it.
struct PickerLink<Destination: View>: View {
    let label: String
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension LineRow {
    /// "412 sailings we can see", or "0 we can see": a line with none is shown, never hidden.
    static func catalogCount(_ line: CatalogLine?) -> String? {
        guard let sailings = line?.sailings else { return nil }
        if sailings == 0 { return "0 we can see" }
        return sailings == 1 ? "1 sailing we can see" : "\(sailings) sailings we can see"
    }
}

/// Every catalog line, each with its coverage and count, multi-select. Empty means any line.
struct LinesPickerScreen: View {
    @Binding var selection: [String]
    var title = "Lines"
    /// Deals on the board per line (the Deals filter); nil shows the catalog's sailing counts.
    var dealCounts: [String: Int]? = nil
    var footer = "None picked means every line."
    @EnvironmentObject private var store: Store

    private var names: [String] { CruiseLine.choosable(store.catalog) }

    var body: some View {
        List {
            Section {
                Button {
                    selection = []
                    Haptics.tap()
                } label: {
                    HStack {
                        Text("Any line").foregroundStyle(Color.primary)
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                        }
                    }
                }
                .accessibilityAddTraits(selection.isEmpty ? .isSelected : [])
            }
            Section {
                ForEach(names, id: \.self) { name in
                    Button {
                        toggle(name)
                    } label: {
                        LineRow(name: name, line: store.catalog.line(name), picked: isPicked(name),
                                countText: countText(name))
                    }
                    .accessibilityAddTraits(isPicked(name) ? .isSelected : [])
                }
            } footer: {
                Text(footer)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countText(_ name: String) -> String? {
        if let dealCounts {
            let n = dealCounts.first { CruiseLine.same($0.key, name) }?.value ?? 0
            return n == 1 ? "1 deal on the board" : "\(n) deals on the board"
        }
        return LineRow.catalogCount(store.catalog.line(name))
    }

    private func isPicked(_ name: String) -> Bool { selection.contains { CruiseLine.same($0, name) } }

    private func toggle(_ name: String) {
        var next = selection
        if isPicked(name) {
            next.removeAll { CruiseLine.same($0, name) }
        } else {
            next.append(name)
        }
        selection = names.filter { line in next.contains { CruiseLine.same($0, line) } }
        Haptics.tap()
    }
}

/// Search-as-you-type over the catalog's ports (`GET /v1/catalog/ports?kind=`), multi-select.
struct PortPickerScreen: View {
    let title: String
    let kind: PortKind
    @Binding var selection: [String]
    var most = 10
    var footer: String? = nil
    @EnvironmentObject private var store: Store
    @State private var text = ""
    @State private var results: [CatalogPort] = []
    @State private var loading = false

    var body: some View {
        List {
            if !selection.isEmpty {
                Section("Chosen") {
                    ForEach(selection, id: \.self) { name in
                        Button {
                            remove(name)
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(Color.primary)
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel(Text(name))
                        .accessibilityHint(Text("Removes it"))
                    }
                }
            }
            Section {
                if loading && results.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking up ports…").foregroundStyle(.secondary)
                    }
                } else if results.isEmpty {
                    Text(text.trimmed.isEmpty ? "Type a port's name." : "No port in the catalog matches “\(text.trimmed)”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { port in
                    let picked = isPicked(port.name)
                    Button {
                        toggle(port.name)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(port.name).foregroundStyle(Color.primary)
                                if !port.detail.isEmpty {
                                    Text(port.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if picked {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .disabled(!picked && selection.count >= most)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            } header: {
                Text(text.trimmed.isEmpty ? "Ports" : "Matches")
            } footer: {
                Text(footer ?? "Pick up to \(most). The list comes from Deal Desk's port catalog.")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search ports"))
        .autocorrectionDisabled()
        .task(id: text) {
            if !text.isEmpty { try? await Task.sleep(nanoseconds: 250_000_000) }
            if Task.isCancelled { return }
            loading = true
            let found = await store.catalogPorts(matching: text, kind: kind)
            if Task.isCancelled { return }
            results = found
            loading = false
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isPicked(_ name: String) -> Bool {
        selection.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func toggle(_ name: String) {
        if isPicked(name) {
            remove(name)
        } else if selection.count < most {
            selection.append(name)
            Haptics.tap()
        }
    }

    private func remove(_ name: String) {
        selection.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        Haptics.tap()
    }
}

/// The region tree: Caribbean > Western / Eastern / Southern, Bahamas, Alaska, Pacific Coastal... A parent
/// takes its children.
struct RegionPickerScreen: View {
    @Binding var selection: [String]
    var most = 12
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section {
                Button {
                    selection = []
                    Haptics.tap()
                } label: {
                    HStack {
                        Text("Anywhere").foregroundStyle(Color.primary)
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
            ForEach(store.regionTree) { node in
                Section {
                    row(node.region, under: nil)
                    ForEach(node.children) { child in
                        row(child, under: node.region)
                    }
                }
            }
            if store.regionTree.isEmpty {
                Section {
                    Text("The region list arrives with the deal server's next update.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Regions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isPicked(_ region: CatalogRegion) -> Bool {
        selection.contains { region.named($0) }
    }

    @ViewBuilder
    private func row(_ region: CatalogRegion, under parent: CatalogRegion?) -> some View {
        let byParent = parent.map { isPicked($0) } ?? false
        let picked = byParent || isPicked(region)
        Button {
            toggle(region, children: store.regionTree.first { $0.region.key == region.key }?.children ?? [])
        } label: {
            HStack(spacing: 10) {
                if parent != nil {
                    Spacer().frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name).foregroundStyle(Color.primary)
                    if let sailings = region.sailings {
                        Text(sailings == 0 ? "0 we can see" : (sailings == 1 ? "1 sailing" : "\(sailings) sailings"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if picked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(byParent ? Color.secondary : Palette.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .disabled(byParent || (!picked && selection.count >= most))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityHint(Text(byParent ? "Included with \(parent?.name ?? "its region")" : ""))
    }

    private func toggle(_ region: CatalogRegion, children: [CatalogRegion]) {
        if isPicked(region) {
            selection.removeAll { region.named($0) }
        } else {
            // A parent takes its children, so they leave the list.
            selection.removeAll { name in children.contains { $0.named(name) } }
            selection.append(region.name)
        }
        Haptics.tap()
    }
}
