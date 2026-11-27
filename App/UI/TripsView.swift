import SwiftUI

/// My trips (DESIGN_V4 section C, CONTRACT_V4 section 4): the cruises Jim took, each port rated 1-10, and what
/// that history does to his picks. Ratings and recent visits only nudge the order and the wording; a deal is never
/// hidden because of them ("for the right deal I would take a back-to-back").
enum TripEditorTarget: Identifiable {
    case new
    case edit(PastTrip)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let trip): return trip.id
        }
    }
}

/// The Tracking tab's "My trips" side: trips, then the ports they visited, then how ports count.
struct MyTripsSections: View {
    @EnvironmentObject private var store: Store
    @Binding var editor: TripEditorTarget?
    @Binding var port: PortSummary?

    var body: some View {
        if !store.has(.trips) {
            Section {
                IllustratedEmpty(title: "My trips is coming soon",
                                 message: "Log the cruises you took and rate each port 1 to 10. Deal Desk then leans toward ports you loved and away from ones you just visited, without ever hiding a deal.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)
        } else if store.trips.isEmpty {
            Section {
                VStack(spacing: 0) {
                    IllustratedEmpty(title: "No trips logged yet",
                                     message: "Add a cruise you took: pick the line, ship and date, and Deal Desk fills in the ports it knows. Then rate them.")
                    Button("Add a trip") { editor = .new }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)
        } else {
            Section {
                ForEach(store.trips) { trip in
                    Button {
                        editor = .edit(trip)
                    } label: {
                        PastTripCard(trip: trip)
                    }
                    .buttonStyle(CardPressStyle())
                    .cardRow()
                    .accessibilityHint(Text("Opens the trip to rate its ports"))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            withAnimation(Motion.spring) { store.deleteTrip(trip) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listSectionSeparator(.hidden)
            if let summary = store.ports, !summary.visited.isEmpty {
                Section {
                    ForEach(summary.visited) { entry in
                        Button {
                            port = entry
                        } label: {
                            PortCard(port: entry)
                        }
                        .buttonStyle(CardPressStyle())
                        .cardRow()
                        .accessibilityHint(Text("Opens the port's history"))
                    }
                } header: {
                    SectionHeading(text: "Ports")
                }
                .listSectionSeparator(.hidden)
            }
            PortKnobsSection()
        }
    }
}

/// A plain-list section title that lines up with the cards.
struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.primary)
            .textCase(nil)
            .padding(.leading, 4)
    }
}

/// One past cruise at a glance:
///
///     Norwegian                                             8/10
///     Norwegian Aqua
///     Sun Nov 1 – Sun Nov 8, 2026 · 7 nights
///     Miami → Roatan · Harvest Caye · Costa Maya · Cozumel
///     [Roatan 9] [Harvest Caye 8] [Costa Maya 3] [Cozumel ·]
struct PastTripCard: View {
    let trip: PastTrip
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.line)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(trip.ship)
                        .font(.headline)
                }
                Spacer(minLength: 8)
                if trip.isLocal {
                    Label("Saving", systemImage: "arrow.up.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if let rating = trip.data.rating {
                    RatingBadge(rating: rating)
                }
            }
            if !trip.datesLine.isEmpty {
                Text(trip.datesLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.85)
            }
            if let route = trip.route {
                Text(route)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 5 : 2)
            }
            if !trip.ports.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(trip.ports.enumerated()), id: \.offset) { entry in
                        PortChip(name: entry.element.name ?? "", rating: entry.element.rating)
                    }
                }
                .padding(.top, 2)
            }
            if trip.ratedCount == 0 && !trip.ports.isEmpty {
                Text("Tap to rate the ports")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(speech))
    }

    private var speech: String {
        var parts = ["\(trip.line), \(trip.ship)"]
        if !trip.datesLine.isEmpty { parts.append(trip.datesLine) }
        if let rating = trip.data.rating { parts.append("rated \(rating) out of 10") }
        let ports = trip.ports.map { port -> String in
            let name = port.name ?? ""
            return port.rating.map { "\(name) \($0) out of 10" } ?? "\(name) not rated"
        }
        if !ports.isEmpty { parts.append(ports.joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }
}

/// "8/10", tinted by how much Jim liked it.
struct RatingBadge: View {
    let rating: Int

    var body: some View {
        Text("\(rating)/10")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(RatingBadge.color(rating))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RatingBadge.color(rating).opacity(0.13), in: Capsule())
            .accessibilityLabel(Text("Rated \(rating) out of 10"))
    }

    static func color(_ rating: Int?) -> Color {
        guard let rating else { return Color.secondary }
        if rating >= 8 { return Palette.fits }
        if rating <= 4 { return Palette.call }
        return Palette.accent
    }
}

/// "Roatan 9" in a small capsule; an unrated port shows its name alone.
struct PortChip: View {
    let name: String
    let rating: Int?

    var body: some View {
        let short = name.split(whereSeparator: { $0 == "(" || $0 == "," }).first.map(String.init)?.trimmed ?? name
        HStack(spacing: 4) {
            Text(short.isEmpty ? name : short)
            if let rating {
                Text("\(rating)")
                    .fontWeight(.bold)
                    .foregroundStyle(RatingBadge.color(rating))
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

/// One port from the summary: its latest rating, visits and last visit.
struct PortCard: View {
    let port: PortSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(port.title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(PortText.visits(port))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let rating = port.rating {
                RatingBadge(rating: rating)
            } else {
                Text("Not rated")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

enum PortText {
    /// "Visited once · 4 weeks ago"
    static func visits(_ port: PortSummary) -> String {
        var parts: [String] = []
        let n = port.visits ?? 0
        parts.append(n == 1 ? "Visited once" : "Visited \(n) times")
        if let days = port.daysSince { parts.append(PortFit.agoWords(days)) }
        return parts.joined(separator: " · ")
    }

    /// What this port does to Jim's picks right now, in plain words.
    static func effect(_ port: PortSummary, trip: TripPrefs?) -> String {
        let rating = port.ratingAdj ?? 0
        let recency = port.recencyAdj ?? 0
        var parts: [String] = []
        if rating > 0, let stars = port.rating {
            parts.append("You rated it \(stars)/10, so sailings that stop here rank a little higher.")
        } else if rating < 0, let stars = port.rating {
            parts.append("You rated it \(stars)/10, so sailings that stop here rank a little lower.")
        }
        if recency < 0, let days = port.daysSince {
            var text = "You were here \(PortFit.agoWords(days)), so it counts a little less for now"
            if let last = Fmt.day(port.lastVisited), let fade = trip?.fadeMonths,
               let until = Calendar.current.date(byAdding: .month, value: fade, to: last) {
                text += "; that fades out by \(Fmt.monthTitle(String(Fmt.isoDay(until).prefix(7))))"
            }
            parts.append(text + ".")
        }
        if parts.isEmpty { parts.append("It doesn't change what Deal Desk shows first right now.") }
        parts.append("It never hides a deal.")
        return parts.joined(separator: " ")
    }
}

// MARK: - The trip editor

/// Add or change a past trip: line, ship and date first (Deal Desk fills in the ports it knows), then a 1-10 rating
/// for each port and the cruise overall.
struct PastTripEditor: View {
    let target: TripEditorTarget
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TripDraft
    @State private var typingShip: Bool
    @State private var portsTouched: Bool
    @State private var newPort = ""
    @State private var prefillNote: String?
    @State private var alert: String?
    @State private var confirmDelete = false
    @State private var priceText: String

    init(target: TripEditorTarget) {
        self.target = target
        var start = TripDraft()
        switch target {
        case .new:
            break
        case .edit(let trip):
            start = TripDraft(trip: trip)
        }
        _draft = State(initialValue: start)
        let ships = CatalogIndex.current.ships(for: start.line)
        _typingShip = State(initialValue: !start.ship.trimmed.isEmpty && !ships.contains { $0.key == Slug.ship(start.ship) })
        _portsTouched = State(initialValue: !start.ports.isEmpty)
        _priceText = State(initialValue: start.pricePaidPP.map { String($0) } ?? "")
    }

    private var editing: PastTrip? {
        if case .edit(let trip) = target { return trip }
        return nil
    }

    private var ships: [CatalogShip] { store.catalog.ships(for: draft.line) }

    private var prefillKey: String {
        "\(draft.line)|\(Slug.ship(draft.ship))|\(draft.sailDate.map { Fmt.isoDay($0) } ?? "")"
    }

    var body: some View {
        NavigationStack {
            Form {
                sailingSection
                if let prefillNote {
                    Section {
                        Label(prefillNote, systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(Palette.accent)
                    }
                }
                portsSection
                Section {
                    RatingRow(title: "The cruise overall", rating: $draft.rating)
                } header: {
                    Text("Overall")
                }
                detailsSection
                if editing != nil {
                    Section {
                        Button("Delete this trip", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Add a trip" : "Your trip")
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
            .task(id: prefillKey) {
                await prefill()
            }
            .alert("Can't save this trip", isPresented: alertShown) {
                Button("OK", role: .cancel) { alert = nil }
            } message: {
                Text(alert ?? "")
            }
            .confirmationDialog("Delete this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editing { store.deleteTrip(editing) }
                    dismiss()
                }
            } message: {
                Text("Its port ratings stop counting toward your picks.")
            }
        }
    }

    // MARK: Sailing

    private var sailingSection: some View {
        Section {
            Picker("Line", selection: lineBinding) {
                ForEach(lineNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            if typingShip || ships.isEmpty {
                TextField("Ship name", text: shipText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if !ships.isEmpty {
                    Button("Pick from the list") { typingShip = false }
                        .font(.subheadline)
                }
            } else {
                Picker("Ship", selection: shipBinding) {
                    Text("Pick a ship").tag("")
                    ForEach(ships, id: \.key) { ship in
                        Text(ship.name ?? ship.key).tag(ship.name ?? ship.key)
                    }
                }
                Button("Type a ship name") { typingShip = true }
                    .font(.subheadline)
            }
            if let day = draft.sailDate {
                DatePicker("Sailed", selection: Binding(get: { day }, set: { draft.sailDate = $0 }),
                           in: ...(Fmt.adding(days: 1, to: Date()) ?? Date()), displayedComponents: .date)
            } else {
                Button("Pick the sail date") {
                    draft.sailDate = Fmt.adding(days: -7, to: Date()) ?? Date()
                }
            }
            Stepper("\(Fmt.nights(draft.nights))", value: $draft.nights, in: 1...30)
            LabeledContent("Left from") {
                TextField("optional, e.g. Miami", text: embarkText)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("The cruise")
        } footer: {
            Text("A sailing still to come belongs in Tracking.")
        }
    }

    private var lineNames: [String] {
        var names = CruiseLine.choosable(store.catalog)
        if !names.contains(where: { CruiseLine.same($0, draft.line) }) { names.insert(draft.line, at: 0) }
        return names
    }

    private var lineBinding: Binding<String> {
        Binding(get: { draft.line }, set: { line in
            guard line != draft.line else { return }
            draft.line = line
            if !ships.contains(where: { $0.key == Slug.ship(draft.ship) }) {
                draft.ship = ""
                typingShip = ships.isEmpty
            }
        })
    }

    private var shipBinding: Binding<String> {
        Binding(get: { draft.ship }, set: { draft.ship = $0 })
    }

    private var shipText: Binding<String> {
        Binding(get: { draft.ship }, set: { draft.ship = String($0.prefix(40)) })
    }

    private var embarkText: Binding<String> {
        Binding(get: { draft.embarkPort }, set: { draft.embarkPort = String($0.prefix(30)) })
    }

    // MARK: Ports

    private var portsSection: some View {
        Section {
            ForEach($draft.ports) { $port in
                RatingRow(title: port.name, rating: $port.rating)
            }
            .onDelete { offsets in
                draft.ports.remove(atOffsets: offsets)
                portsTouched = true
            }
            .onMove { from, to in
                draft.ports.move(fromOffsets: from, toOffset: to)
                portsTouched = true
            }
            if draft.cleanPorts.count < 14 {
                HStack {
                    TextField("Add a port", text: $newPort)
                        .textInputAutocapitalization(.words)
                        .onSubmit(addPort)
                    Button("Add", action: addPort)
                        .disabled(newPort.trimmed.isEmpty)
                }
            }
        } header: {
            Text("Ports and ratings")
        } footer: {
            Text("Rate each port 1 to 10 (sea days aren't listed). Loved ports lift sailings that stop there; ports you just visited count a little less for a while. Neither ever hides a deal.")
        }
    }

    private func addPort() {
        let name = newPort.trimmed.capped(40)
        guard !name.isEmpty else { return }
        draft.ports.append(TripDraft.Port(name: name, rating: nil))
        newPort = ""
        portsTouched = true
        Haptics.tap()
    }

    // MARK: Details

    private var detailsSection: some View {
        Section {
            Picker("Cabin", selection: cabinBinding) {
                Text("Not set").tag("")
                ForEach([CabinType.interior, .oceanview, .balcony, .suite], id: \.rawValue) { cabin in
                    Text(cabin.title).tag(cabin.rawValue)
                }
            }
            HStack {
                Text("Paid")
                TextField("optional", text: $priceText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: priceText) { _, text in
                        draft.pricePaidPP = Int(text.filter { $0.isNumber }.prefix(7))
                    }
                Text("pp")
                    .foregroundStyle(.secondary)
            }
            TextField("Notes (optional)", text: notesText, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("Details")
        }
    }

    private var cabinBinding: Binding<String> {
        Binding(get: { draft.cabin?.rawValue ?? "" }, set: { draft.cabin = CabinType(rawValue: $0) })
    }

    private var notesText: Binding<String> {
        Binding(get: { draft.notes }, set: { draft.notes = String($0.prefix(500)) })
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }

    // MARK: Prefill and save

    /// Line, ship and date are in: fill in what Deal Desk knows, unless Jim has already set the ports.
    private func prefill() async {
        guard let day = draft.sailDate, !draft.ship.trimmed.isEmpty, !portsTouched else { return }
        guard let found = await store.prefill(line: draft.line, ship: draft.ship, sailDate: day), found.found,
              !portsTouched else { return }
        withAnimation(Motion.snappy) {
            if !found.ports.isEmpty {
                draft.ports = found.ports.prefix(14).map { TripDraft.Port(name: $0.capped(40), rating: nil) }
            }
            if let nights = found.nights, (1...30).contains(nights) { draft.nights = nights }
            if draft.embarkPort.trimmed.isEmpty, let port = found.embarkPort { draft.embarkPort = port.capped(30) }
            draft.via = "catalog"
        }
        let from: String
        switch found.source {
        case "deal": from = "a deal it posted"
        case "tracked": from = "a sailing you tracked"
        default: from = "its fare data"
        }
        prefillNote = "Filled in from \(from). Check the ports, then rate them."
    }

    private func save() {
        switch store.logTrip(draft, editing: editing) {
        case .saved: dismiss()
        case .already: alert = "That sailing is already in My trips."
        case .comingSoon: alert = "My trips switches on once the deal server has it."
        case .full: alert = "You have \(Store.tripsLimit) trips logged, the most there is."
        case .invalid(let why): alert = why
        }
    }
}

/// A 1-10 slider for one port (or the whole cruise); "Not rated" until Jim taps Rate.
struct RatingRow: View {
    let title: String
    @Binding var rating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(rating.map { "\($0)/10" } ?? "Not rated")
                    .font(.subheadline.weight(rating == nil ? .regular : .bold))
                    .monospacedDigit()
                    .foregroundStyle(RatingBadge.color(rating))
            }
            if let value = rating {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { Double(value) }, set: { rating = Int($0.rounded()) }),
                           in: 1...10, step: 1) {
                        Text("\(title) rating")
                    } minimumValueLabel: {
                        Text("1").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("10").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityValue(Text("\(value) out of 10"))
                    Button {
                        rating = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Clear the rating for \(title)"))
                }
            } else {
                Button("Rate it") { rating = 7 }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel(Text("Rate \(title)"))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Port detail

struct PortDetailView: View {
    let port: PortSummary
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(port.title)
                                .font(.title2.weight(.semibold))
                            Spacer(minLength: 8)
                            if let rating = port.rating {
                                RatingBadge(rating: rating)
                            }
                        }
                        if let region = port.region, !region.isEmpty {
                            Text(region)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Your visits") {
                    InfoRow(label: "Visits", value: String(port.visits ?? 0))
                    if let last = Fmt.day(port.lastVisited) {
                        InfoRow(label: "Last there", value: Fmt.fullDay(last),
                                note: port.daysSince.map { PortFit.agoWords($0) })
                    }
                    InfoRow(label: "Your rating", value: port.rating.map { "\($0)/10" } ?? "Not rated")
                }
                Section("What it does to your picks") {
                    TextBlock(text: PortText.effect(port, trip: store.trip))
                }
                if let history = port.history, !history.isEmpty {
                    Section("Rating history") {
                        ForEach(Array(history.enumerated()), id: \.offset) { entry in
                            let visit = entry.element
                            InfoRow(label: Fmt.day(visit.sailDate).map { Fmt.fullDay($0) } ?? (visit.sailDate ?? ""),
                                    value: visit.rating.map { "\($0)/10" } ?? "Not rated",
                                    note: visit.tripId.flatMap { store.pastTrip($0)?.ship })
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(port.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - How ports count

/// The three port knobs on the trip settings (CONTRACT_V4 section 4.2), saved as Jim changes them.
struct PortKnobsSection: View {
    @EnvironmentObject private var store: Store
    @State private var months = 6
    @State private var fade = 12
    @State private var useRatings = true
    @State private var loaded = false

    var body: some View {
        if store.trip != nil {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use my port ratings", isOn: $useRatings)
                    Stepper(months == 0 ? "Recent visits: no effect" : "Recent visits count less for \(months) mo",
                            value: $months, in: 0...24)
                    if months > 0 {
                        Stepper("Fading out by \(fade) mo", value: $fade, in: max(months, 1)...36)
                    }
                    Text("Only the order and the wording change; no deal is ever hidden or held back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(CardBackground())
                .cardRow()
            } header: {
                SectionHeading(text: "How ports count")
            }
            .listSectionSeparator(.hidden)
            .onAppear(perform: load)
            .onChange(of: months) { _, value in
                if fade < value { fade = value }
                save()
            }
            .onChange(of: fade) { save() }
            .onChange(of: useRatings) { save() }
        }
    }

    private func load() {
        guard let trip = store.trip else { return }
        months = trip.recencyMonths
        fade = trip.fadeMonths
        useRatings = trip.usesPortRatings
        loaded = true
    }

    private func save() {
        guard loaded, let trip = store.trip else { return }
        if trip.recencyMonths == months && trip.fadeMonths == max(fade, months, 1) && trip.usesPortRatings == useRatings {
            return
        }
        store.savePortKnobs(recencyMonths: months, fadeMonths: max(fade, months, 1), useRatings: useRatings)
    }
}
