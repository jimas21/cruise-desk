import SwiftUI

/// The deal sheet (CONTRACT_V5 section 2.8): one view for a deal, a tracked sailing and a search row. The trip
/// cost for the party with every line tagged by where it came from, the verdict in one word and one line, the
/// cabin against the budget, then What to buy, Getting there and Pay & cancel. Every figure is the server's.
struct DealSheetSections: View {
    /// The trip cost alone (it leads a deal), the rest alone (after the scoop), or all of it.
    enum Part {
        case all, cost, more
    }

    let sheet: DealSheet
    let line: String
    var part: Part = .all
    /// The fare score, relabelled "Price score": the verdict is the trip-level answer.
    var priceScore: Int? = nil
    var priceLabel: String? = nil
    @EnvironmentObject private var store: Store
    @State private var showMissing = false

    var body: some View {
        Group {
            if part != .more {
                costSection
            }
            if part != .cost {
                buySection
                travelSection
                paySection
            }
        }
    }

    // MARK: Trip cost

    private var missing: [String] { sheet.total?.missing ?? [] }

    private var costSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        costCaption
                        Spacer(minLength: 8)
                        VerdictChip(label: sheet.verdict?.label)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        costCaption
                        VerdictChip(label: sheet.verdict?.label)
                    }
                }
                Text(sheet.total?.headline ?? "Not known yet")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                if let firm = sheet.firmText {
                    Text(firm)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let line = sheet.verdict?.line?.trimmed, !line.isEmpty {
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let score = priceScore {
                    Text("Price score \(score)" + (priceLabel.map { " · \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            if !missing.isEmpty {
                Button {
                    withAnimation(Motion.snappy) { showMissing.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showMissing ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                        Text(missing.count == 1 ? "+ 1 not shown" : "+ \(missing.count) not shown")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.call)
                }
                .buttonStyle(.borderless)
                .accessibilityHint(Text("Lists what the total leaves out"))
                if showMissing {
                    Text("Not in the total: \(ListText.join(missing)). The total is a range until these are known.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(sheet.lines) { item in
                SheetLineRow(line: item)
            }
            if let budget = sheet.budget?.line {
                Text(budget)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(sheet.budget?.state == "over" ? Palette.call : Color.secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("Trip cost")
        } footer: {
            if let refAsOf = sheet.refAsOf?.trimmed, !refAsOf.isEmpty {
                Text("Line rates (tips, add-ons) as of \(refAsOf). Each figure says where it came from.")
            } else {
                Text("Each figure says where it came from.")
            }
        }
    }

    private var costCaption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TRIP COST")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if let party = sheet.partyText {
                Text(party)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: What to buy

    @ViewBuilder
    private var buySection: some View {
        let hasContent = !sheet.whatToBuy.isEmpty || sheet.bundle?.summary != nil
        if hasContent || store.has(.reference) {
            Section {
                if let bundle = sheet.bundle, let summary = bundle.summary {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let bare = bundle.barePP {
                            Text("Without the promo: \(Fmt.usd(bare)) pp" +
                                 (bundle.bareSource.map { " (\($0))" } ?? ""))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if let note = bundle.note?.trimmed, !note.isEmpty {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(sheet.whatToBuy) { item in
                    WhatToBuyRow(item: item)
                }
                if !hasContent {
                    Text("Nothing listed for this sailing yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if store.has(.reference) {
                    NavigationLink {
                        AddonsGuideView(line: line)
                    } label: {
                        Label("What to buy on \(line)", systemImage: "list.bullet.rectangle")
                    }
                }
            } header: {
                Text("What to buy")
            } footer: {
                Text("Add-ons are bought after booking, in \(line)'s own planner, usually for less before the cruise. Only what you said you usually buy counts in the total.")
            }
        }
    }

    // MARK: Getting there

    private var travelSection: some View {
        Section {
            if let travel = sheet.travel {
                TravelRows(travel: travel, flightsOn: store.has(.flights))
            } else {
                Text("Set your home airport in My Trip to see how you'd get to the ship.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Getting there")
        } footer: {
            if !store.has(.flights) {
                Text("Flight estimates switch on once the deal server has them; until then nothing for flights is in the total.")
            }
        }
    }

    // MARK: Pay & cancel

    private var paySection: some View {
        Section {
            if let pay = sheet.pay, pay.basisValue != .notShown {
                if let deposit = pay.depositPP {
                    InfoRow(label: "Deposit", value: "\(Fmt.usd(deposit)) pp", note: pay.depositNote)
                } else if let note = pay.depositNote?.trimmed, !note.isEmpty {
                    InfoRow(label: "Deposit", value: note)
                }
                if let day = Fmt.day(pay.finalPaymentDate) {
                    let left = Fmt.daysLeft(day)
                    InfoRow(label: "Final payment", value: Fmt.fullDay(day),
                            note: left >= 0 ? (left == 1 ? "1 day from now" : "\(left) days from now") : "passed")
                }
                if let refundable = pay.refundableBeforeFinal {
                    InfoRow(label: "Refundable before then", value: refundable ? "Yes" : "No")
                }
                if let note = pay.note?.trimmed, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                BasisTag(text: [pay.basisValue.title, pay.asOf.map { "as of \($0)" }].compactMap { $0 }
                    .joined(separator: " · "))
            } else {
                Text(sheet.pay?.note?.trimmed.isEmpty == false ? sheet.pay!.note! : "Not researched yet; check on \(line)'s page.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Pay & cancel")
        }
    }
}

/// One money line: what it is, the amount, and a small tag saying where it came from.
struct SheetLineRow: View {
    let line: SheetLine
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dimmed: Bool { line.counted == false || line.basisValue == .notShown }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    labelBlock
                    amountBlock(alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    labelBlock
                    Spacer(minLength: 8)
                    amountBlock(alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.title)
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
            if let detail = line.detail?.trimmed, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func amountBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(line.amountText)
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
            BasisTag(text: line.tag)
        }
    }
}

/// One add-on worth knowing about: its range for the party and the cruise, when to buy, and whether it counts.
struct WhatToBuyRow: View {
    let item: WhatToBuyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                Spacer(minLength: 6)
                if item.counted == true {
                    TagLabel(text: "in the total", color: Palette.fits)
                }
            }
            Text(item.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let worth = item.worthIt?.trimmed, !worth.isEmpty {
                Text(worth)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Home, drive or fly; the line's own air program as an option (never a price); the hotel night.
private struct TravelRows: View {
    let travel: SheetTravel
    let flightsOn: Bool

    var body: some View {
        switch travel.modeValue {
        case .home:
            Label("You live here: no flight and no hotel to add.", systemImage: "house")
        case .drive:
            Label("Drive or take the train; not priced and not in the total.", systemImage: "car")
        case .fly:
            flyRows
        case .notKnown:
            Label("Set your home airport in My Trip to work this out.", systemImage: "airplane")
                .foregroundStyle(.secondary)
        case .other(let raw):
            Text(Words.humanize(raw))
                .foregroundStyle(.secondary)
        }
        if let air = travel.lineAir, let program = air.program?.trimmed, !program.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("The line's own air: \(program)")
                if let note = air.note?.trimmed, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let link = air.link {
                    Link("Quote it on the line's site", destination: link)
                        .font(.footnote.weight(.semibold))
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var flyRows: some View {
        let route = [travel.fromAirport, travel.toAirport].compactMap { $0 }.joined(separator: "–")
        if let flight = travel.flight, flightsOn, let pp = flight.pp {
            InfoRow(label: route.isEmpty ? "Flight" : "Fly \(route)", value: "about \(Fmt.usd(pp)) pp",
                    note: [flight.ageDays.map { "estimate · \($0 == 1 ? "1 day" : "\($0) days") old" },
                           flight.provider].compactMap { $0 }.joined(separator: " · "))
        } else {
            InfoRow(label: route.isEmpty ? "Fly" : "Fly \(route)",
                    value: flightStateText(travel.flight?.state),
                    note: Fmt.day(travel.departDate).map { "out \(Fmt.shortDay($0))" })
        }
        if let hotel = travel.hotel, (hotel.nights ?? 0) > 0 {
            if let range = Money.range(hotel.low, hotel.high) {
                InfoRow(label: "Hotel the night before", value: range, note: "estimate · 1 room")
            } else {
                InfoRow(label: "Hotel the night before", value: "not priced", note: "in the not-shown list")
            }
        }
        if let link = travel.searchLink {
            Link(destination: link) {
                Label("Look up flights (opens Google Flights)", systemImage: "arrow.up.right.square")
            }
            .font(.subheadline)
        }
    }

    private func flightStateText(_ state: String?) -> String {
        switch state ?? "" {
        case "pending": return "looking up an estimate"
        case "not_set_up": return "estimate not set up"
        case "none": return "no estimate"
        default: return flightsOn ? "no estimate yet" : "estimate not set up"
        }
    }
}

// MARK: - Any search row, opened (CONTRACT_V5 section 1.7)

/// A search row opened: the same sheet as a deal (`GET /v1/sheet`), or the row's own facts on a server without
/// it. From here Jim can track the sailing, save the search as a plan, or book on the line.
struct SailingSheetScreen: View {
    let row: SearchRow
    var cabin: String? = nil
    var savePlan: (() -> Void)? = nil
    @EnvironmentObject private var store: Store
    @State private var sheet: DealSheet?
    @State private var loaded = false
    @State private var message: String?

    private var group: ShipClassGroup? {
        store.catalog.classGroup(line: row.lineName, ship: row.shipName ?? row.ship)
            ?? store.catalog.classGroup(line: row.lineName, classKey: row.shipClass)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.eyebrow)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(row.shipTitle)
                        .font(.title3.weight(.semibold))
                    if !row.datesLine.isEmpty {
                        Text(row.datesLine)
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    if let route = row.route {
                        Text(route)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let cabin = row.cabinType ?? cabin.flatMap({ CabinType(rawValue: $0) }) {
                        Text(cabin.title)
                            .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if let sheet {
                DealSheetSections(sheet: sheet, line: row.lineName, priceScore: row.score, priceLabel: row.scoreLabel)
            } else if store.has(.sheet) && !loaded {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Working out the trip cost…").foregroundStyle(.secondary)
                    }
                }
            } else {
                priceSection
            }

            if group != nil || ShipScaleStrip.available(store, line: row.lineName, ship: row.shipTitle) {
                Section("Ship") {
                    if let group {
                        ClassShipsRow(group: group, current: row.shipName ?? row.ship)
                    }
                    if ShipScaleStrip.available(store, line: row.lineName, ship: row.shipTitle) {
                        ShipScaleStrip(line: row.lineName, ship: row.shipTitle)
                    }
                }
            }

            Section {
                BookBar(choice: store.bookChoice(for: row))
                HStack(spacing: 12) {
                    Button {
                        track()
                    } label: {
                        Label(isTracked ? "Tracking" : "Track it", systemImage: isTracked ? "checkmark" : "binoculars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTracked)
                    if let savePlan {
                        Button {
                            savePlan()
                        } label: {
                            Label("Save the search", systemImage: "bookmark")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }

            if let sources = row.sources, !sources.isEmpty {
                Section("Sources") {
                    ForEach(sources, id: \.self) { source in
                        SourceRow(source: source)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(row.shipTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: row.id) {
            await store.loadShipPhotos()
            if store.has(.sheet) {
                sheet = await store.sheet(sailingId: row.sailingId, cabin: row.cabin ?? cabin)
            }
            loaded = true
        }
        .alert("Track", isPresented: messageShown) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private var isTracked: Bool {
        if let id = row.trackedId, store.trackedSailing(id) != nil { return true }
        return store.trackedMatch(key: row.trackPick(cabin: cabin).key) != nil
    }

    private func track() {
        switch store.track(row.trackPick(cabin: cabin)) {
        case .added: message = nil
        case .already: message = "You already track this sailing."
        case .comingSoon: message = "Tracking switches on once the deal server has it."
        case .full: message = "You track \(Store.trackedLimit) sailings, the most there is. Stop one first."
        case .invalid(let why): message = why
        }
    }

    @ViewBuilder
    private var priceSection: some View {
        Section {
            if let price = row.pricePP, price > 0 {
                InfoRow(label: "Per person", value: Fmt.usd(price),
                        note: [row.priceIncludesTaxes == true ? "taxes in" : nil, row.priceSource].compactMap { $0 }
                            .joined(separator: " · "))
                if let typical = row.typicalPP, typical > 0 {
                    InfoRow(label: "Typical", value: "\(Fmt.usd(typical)) pp")
                }
                if let lowest = row.lowestSeenPP, lowest > 0 {
                    InfoRow(label: "Lowest seen", value: "\(Fmt.usd(lowest)) pp")
                }
            } else {
                Text(row.scheduleOnly ? "Price not seen: a schedule lists this sailing, no source shows a fare yet."
                                      : "No current price for this cabin.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Price")
        } footer: {
            if !store.has(.sheet) {
                Text("The whole trip cost for your party (taxes, tips, add-ons) switches on once the deal server has it.")
            }
        }
    }
}
