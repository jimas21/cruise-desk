import SwiftUI
import UIKit

/// Track a cruise (DESIGN_V3 section 2): line -> ship -> date -> nights -> cabin, on one calm screen, or filled from
/// a pasted link. The sailings Deal Desk already knows for the ship are offered first, so most picks are one tap.
/// On Track the sailing shows at once in Tracking with every price "filling…" until the server fills it.
struct TrackBuilder: View {
    let seed: TrackSeed
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var pick: TrackPick
    @State private var typingShip: Bool
    @State private var linkText: String
    @State private var fromLink: LinkPick?
    @State private var linkMiss = false
    @State private var sailings: [FareSailing] = []
    @State private var loading = false
    @State private var showAll = false
    @State private var alert: String?
    /// v4: the line link last handed to the deal server to read (its text only).
    @State private var askedURL: String?
    @FocusState private var linkFocused: Bool

    /// Starts from a deal's sailing, from a link (or an empty link box), or blank.
    init(seed: TrackSeed) {
        self.seed = seed
        var start = seed.pick ?? TrackPick()
        var found: LinkPick?
        let text = seed.text ?? ""
        if !text.trimmed.isEmpty, let read = LinkPick.read(text) {
            found = read
            TrackBuilder.apply(read, to: &start)
        }
        _pick = State(initialValue: start)
        _fromLink = State(initialValue: found)
        _linkText = State(initialValue: text)
        let ships = CatalogIndex.current.ships(for: start.line)
        let listed = ships.contains { $0.key == Slug.ship(start.ship) }
        _typingShip = State(initialValue: !start.ship.trimmed.isEmpty && !listed)
    }

    private static let farOff: TimeInterval = 120 * 86400

    private var ships: [CatalogShip] { store.catalog.ships(for: pick.line) }
    private var existing: TrackedSailing? { store.trackedMatch(key: pick.key) }
    private var lineNames: [String] {
        var names = store.catalog.lineNames
        if !names.contains(where: { CruiseLine.same($0, pick.line) }) { names.insert(pick.line, at: 0) }
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                linkSection
                lineSection
                shipSection
                sailingSection
                cabinSection
                Section {
                    TextField("Anything to remember (optional)", text: capped(\.note, 120), axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Deal Desk fills in the price, the typical price and the lowest it has seen from the fares it already collects, and sets a price alert wherever a site offers one. Until then each field says “filling…”; nothing is made up.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Track a cruise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Track" : "Open") { track() }
                        .fontWeight(.semibold)
                        .disabled(existing == nil && pick.problem != nil)
                }
            }
            .task(id: "\(pick.line)|\(Slug.ship(pick.ship))") {
                await loadSailings()
            }
            .onAppear {
                if seed.text != nil && seed.pick == nil && fromLink == nil { linkFocused = true }
            }
            .alert("Can't track this yet", isPresented: alertShown) {
                Button("OK", role: .cancel) { alert = nil }
            } message: {
                Text(alert ?? "")
            }
        }
    }

    // MARK: From a link

    private var linkSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Paste a sailing link", text: $linkText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($linkFocused)
                    .onSubmit { read(linkText) }
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    DispatchQueue.main.async {
                        linkText = text
                        read(text)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            if let fromLink, fromLink.foundSailing || fromLink.line != nil {
                Label {
                    Text("From the link: \(fromLink.summary.isEmpty ? (fromLink.line ?? "") : fromLink.summary)")
                } icon: {
                    Image(systemName: "link")
                }
                .font(.footnote)
                .foregroundStyle(Palette.accent)
            } else if linkMiss {
                Text("No sailing found in that link. Pick it below instead.")
                    .font(.footnote)
                    .foregroundStyle(Palette.call)
            }
        } header: {
            Text("Add from a link")
        } footer: {
            Text(store.has(.booking)
                 ? "A sailing page from AllAboardDeals or a cruise line's own site, with its title if you have it. It's read on this phone, and a line's own link by the deal server from its text; nothing is fetched."
                 : "A sailing page from AllAboardDeals or a cruise line's site, with its title if you have it. It's read on this phone only; nothing is fetched.")
        }
        .onChange(of: linkText) { _, text in
            if text.contains("://") { read(text) }
        }
    }

    private func read(_ text: String) {
        guard !text.trimmed.isEmpty else { return }
        let local = LinkPick.read(text, catalog: store.catalog)
        defer { askServer(text, local: local) }
        guard let found = local, found.foundSailing || found.line != nil else {
            fromLink = nil
            linkMiss = true
            return
        }
        linkMiss = false
        if found == fromLink { return }
        fromLink = found
        withAnimation(Motion.snappy) {
            TrackBuilder.apply(found, to: &pick)
            typingShip = !pick.ship.trimmed.isEmpty && !ships.contains { $0.key == Slug.ship(pick.ship) }
        }
        Haptics.tap()
    }

    /// v4 (CONTRACT_V4 slice 0c): a cruise line's own link also goes to `POST /v1/link/parse`, which reads the
    /// line, ship and date from the link's text with the catalog's ship codes. Nothing is fetched by anyone.
    private func askServer(_ text: String, local: LinkPick?) {
        guard store.has(.booking), let url = LinkPick.firstURL(in: text), let host = url.host,
              CruiseLine.fromHost(host) != nil else { return }
        let address = url.absoluteString
        guard address != askedURL else { return }
        askedURL = address
        Task {
            guard let parsed = await store.parseLink(address), askedURL == address else { return }
            var merged = local ?? LinkPick()
            if let line = parsed.line.flatMap({ CruiseLine.canonical($0) }) { merged.line = line }
            if let ship = parsed.ship?.trimmed, !ship.isEmpty { merged.ship = ship }
            if let day = parsed.sailDate, Fmt.day(day) != nil { merged.sailDate = day }
            if merged.link == nil { merged.link = TrackPick.validLink(address) }
            guard merged.foundSailing || merged.line != nil, merged != fromLink else { return }
            linkMiss = false
            fromLink = merged
            withAnimation(Motion.snappy) {
                TrackBuilder.apply(merged, to: &pick)
                typingShip = !pick.ship.trimmed.isEmpty && !ships.contains { $0.key == Slug.ship(pick.ship) }
            }
            Haptics.tap()
        }
    }

    static func apply(_ found: LinkPick, to pick: inout TrackPick) {
        if let line = found.line { pick.line = line }
        if let ship = found.ship { pick.ship = ship.capped(40) }
        if let day = Fmt.day(found.sailDate) { pick.sailDate = day }
        if let nights = found.nights { pick.nights = nights }
        if let link = found.link { pick.link = link }
        pick.via = "link"
    }

    // MARK: Line

    private var lineSection: some View {
        Section {
            Picker("Line", selection: lineBinding) {
                ForEach(lineNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            if store.isV3 {
                LineRow(name: pick.line, line: store.catalog.line(pick.line),
                        countText: store.has(.catalog5) ? LineRow.catalogCount(store.catalog.line(pick.line)) : nil)
            }
        } header: {
            Text("Line")
        }
    }

    /// The catalog port picker, for the one port a tracked sailing leaves from.
    private var portPick: Binding<[String]> {
        Binding(get: { pick.port.trimmed.isEmpty ? [] : [pick.port] },
                set: { pick.port = ($0.last ?? "").capped(30) })
    }

    private var lineBinding: Binding<String> {
        Binding(get: { pick.line }, set: { line in
            guard line != pick.line else { return }
            pick.line = line
            if !ships.contains(where: { $0.key == Slug.ship(pick.ship) }) {
                pick.ship = ""
                typingShip = ships.isEmpty
            }
        })
    }

    // MARK: Ship

    private var shipSection: some View {
        Section {
            if typingShip || ships.isEmpty {
                TextField("Ship name", text: capped(\.ship, 40))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if !ships.isEmpty {
                    Button("Pick from the list") {
                        typingShip = false
                        if !ships.contains(where: { $0.key == Slug.ship(pick.ship) }) { pick.ship = "" }
                    }
                }
            } else {
                Picker("Ship", selection: shipBinding) {
                    Text("Choose a ship").tag("")
                    ForEach(ships, id: \.key) { ship in
                        Text(ship.name ?? ship.key).tag(ship.name ?? ship.key)
                    }
                    Text("Another ship…").tag(TrackBuilder.otherShip)
                }
            }
        } header: {
            Text("Ship")
        } footer: {
            if let known = store.catalog.ship(line: pick.line, named: pick.ship) {
                VStack(alignment: .leading, spacing: 4) {
                    Text([known.tier?.shipTitle, known.className.map { "\($0) class" }].compactMap { $0 }
                        .joined(separator: " · "))
                    if let group = store.catalog.classGroup(line: pick.line, ship: pick.ship) {
                        ClassShipsLine(group: group, current: pick.ship)
                    }
                }
            } else if ships.isEmpty {
                Text("Deal Desk doesn't list \(pick.line)'s ships yet; type the name as the line writes it.")
            }
        }
    }

    private static let otherShip = "\u{1}other"

    private var shipBinding: Binding<String> {
        Binding(get: { pick.ship }, set: { name in
            if name == TrackBuilder.otherShip {
                typingShip = true
                pick.ship = ""
            } else {
                pick.ship = name
            }
        })
    }

    // MARK: Sailing

    private var sailingSection: some View {
        Section {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for known sailings…").foregroundStyle(.secondary)
                }
            } else if !sailings.isEmpty {
                ForEach(showAll ? sailings : Array(sailings.prefix(6))) { sailing in
                    Button {
                        choose(sailing)
                    } label: {
                        SailingChoiceRow(sailing: sailing, cabin: pick.cabin, chosen: isChosen(sailing))
                    }
                    .accessibilityAddTraits(isChosen(sailing) ? .isSelected : [])
                }
                if sailings.count > 6 {
                    Button(showAll ? "Show fewer" : "Show all \(sailings.count) sailings") {
                        withAnimation(Motion.snappy) { showAll.toggle() }
                    }
                }
            }
            if pick.sailDate != nil {
                DatePicker("Sail date", selection: dateBinding, in: Calendar.current.startOfDay(for: Date())...,
                           displayedComponents: .date)
            } else {
                Button("Choose the sail date") {
                    pick.sailDate = Date().addingTimeInterval(TrackBuilder.farOff)
                }
            }
            Stepper(value: $pick.nights, in: 1...30) {
                ValueLabel(label: "Nights", value: Fmt.nights(pick.nights))
            }
            if store.has(.catalog5) {
                // Picker only (CONTRACT_V5 1.7): typed text would skip the catalog's port keys.
                PickerLink(label: "Leaves from (optional)", value: pick.port.trimmed.isEmpty ? "Pick a port" : pick.port) {
                    PortPickerScreen(title: "Leaves from", kind: .embark, selection: portPick, most: 1,
                                     footer: "From Deal Desk's port catalog. Pick one, or leave it empty.")
                }
            } else {
                TextField("Leaves from (optional)", text: capped(\.port, 30))
            }
        } header: {
            Text("Sailing")
        } footer: {
            if !sailings.isEmpty {
                Text("Sailings Deal Desk already sees for this ship, with today's lowest price for the cabin below. Or set the date yourself.")
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { pick.sailDate ?? Date().addingTimeInterval(TrackBuilder.farOff) },
                set: { pick.sailDate = $0 })
    }

    private func isChosen(_ sailing: FareSailing) -> Bool {
        guard let day = pick.sailDate, let sail = sailing.sailDate else { return false }
        return Fmt.isoDay(day) == String(sail.prefix(10)) && sailing.nights == pick.nights
    }

    private func choose(_ sailing: FareSailing) {
        withAnimation(Motion.snappy) {
            if let day = sailing.sailDay { pick.sailDate = day }
            if let nights = sailing.nights, (1...30).contains(nights) { pick.nights = nights }
            if let port = sailing.embarkPort?.trimmed, !port.isEmpty, pick.port.trimmed.isEmpty {
                pick.port = port.capped(30)
            }
        }
        Haptics.tap()
    }

    private func loadSailings() async {
        let ship = pick.ship.trimmed
        guard store.isV3, !ship.isEmpty else {
            sailings = []
            loading = false
            return
        }
        // While a name is being typed, wait for a pause before asking.
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        loading = true
        let found = await store.knownSailings(line: pick.line, ship: ship)
        if Task.isCancelled { return }
        loading = false
        sailings = found
        showAll = false
    }

    // MARK: Cabin

    private var cabinSection: some View {
        Section {
            Picker("Cabin", selection: $pick.cabin) {
                ForEach(CabinType.allIds, id: \.self) { id in
                    if let type = CabinType(rawValue: id) {
                        Text(type.title).tag(type)
                    }
                }
            }
            .pickerStyle(.segmented)
            TextField(categoryPrompt, text: capped(\.cabinName, 40))
                .textInputAutocapitalization(.words)
        } header: {
            Text("Cabin")
        } footer: {
            if let existing {
                Text("Already tracking this sailing in this cabin (\(existing.ship)). Open shows it.")
                    .foregroundStyle(Palette.call)
            } else {
                Text("With an exact category, the price is for that category whenever a source names it.")
            }
        }
    }

    private var categoryPrompt: String {
        switch pick.cabin {
        case .balcony: return "Exact category, e.g. Ocean View Balcony (optional)"
        case .suite: return "Exact category, e.g. Grand Suite (optional)"
        case .oceanview: return "Exact category, e.g. Ocean View (optional)"
        case .interior: return "Exact category (optional)"
        }
    }

    // MARK: Track

    private func track() {
        if let existing {
            dismiss()
            router.openTracked(existing.id)
            return
        }
        switch store.track(pick) {
        case .added:
            dismiss()
        case .already(let id):
            dismiss()
            router.openTracked(id)
        case .full:
            alert = "You're tracking \(Store.trackedLimit) sailings, the most there's room for. Stop one to add this."
        case .comingSoon:
            alert = "Tracking switches on once the deal server's next update lands."
        case .invalid(let why):
            alert = why
        }
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }

    private func capped(_ key: WritableKeyPath<TrackPick, String>, _ limit: Int) -> Binding<String> {
        Binding(get: { pick[keyPath: key] }, set: { pick[keyPath: key] = String($0.prefix(limit)) })
    }
}

/// One known sailing: "Sat Jun 12, 2027 · 7 nights" over "Port Canaveral · from $1,312 pp", checked when chosen.
private struct SailingChoiceRow: View {
    let sailing: FareSailing
    let cabin: CabinType
    let chosen: Bool

    private var when: String {
        var parts: [String] = []
        if let day = sailing.sailDay { parts.append("\(Fmt.weekday(day)), \(Fmt.fullDay(day).suffix(4))") }
        if let nights = sailing.nights { parts.append(Fmt.nights(nights)) }
        return parts.joined(separator: " · ")
    }

    private var detail: String {
        var parts: [String] = []
        if let port = sailing.embarkPort?.trimmed, !port.isEmpty { parts.append(port) }
        if let fare = sailing.bestByClass?[cabin.rawValue], let price = fare.pricePP {
            parts.append("from \(Fmt.usd(price)) pp \(cabin.title.lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(when)
                    .foregroundStyle(Color.primary)
                    .monospacedDigit()
                if !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Track a cruise") {
    TrackBuilder(seed: TrackSeed())
        .environmentObject(Store.preview())
        .environmentObject(Router())
}
