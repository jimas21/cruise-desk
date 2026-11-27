import SwiftUI

/// Places in the detail view a push, a link or a screenshot can open at.
enum DetailFocus: String, Hashable {
    case scoop, price, cabins, itinerary, history, ask
}

/// One deal: the hero, then The scoop first, then short labelled sections (DESIGN_V2 section 3).
struct DealDetailView: View {
    let dealId: String
    var focus: DetailFocus? = nil
    @EnvironmentObject private var store: Store

    var body: some View {
        if let deal = store.deal(dealId) {
            DealDetailContent(deal: deal, feedback: store.feedback[deal.id],
                              pending: store.isPending("feedback", deal.id), focus: focus)
        } else {
            ContentUnavailableView {
                Label(store.syncing ? "Loading the deal" : "Deal not found", systemImage: "tray")
            } description: {
                Text(store.syncing ? "Fetching the latest from the deal server."
                                   : "It may have been removed. Pull to refresh on the Deals tab.")
            }
            .task { await store.refresh() }
        }
    }
}

private struct DealDetailContent: View {
    let deal: Deal
    let feedback: Feedback?
    let pending: Bool
    let focus: DetailFocus?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @State private var answering: Verdict?
    @State private var heroGone = false

    private var d: DealData { deal.data }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    DealHero(deal: deal)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)

                scoopSection
                if let feedback, feedback.verdict != nil {
                    answerSection(feedback)
                }
                if deal.kind == .sale {
                    offersSection
                } else {
                    priceSection
                    tripFitSection
                }
                whySection
                if deal.kind != .sale {
                    cabinSection
                    cabinOptionsSection
                    itinerarySection
                    historySection
                }
                perksSection
                sourcesSection
                Section {
                    AskThread(dealId: deal.id)
                        .id(DetailFocus.ask)
                } header: {
                    Text("Ask about this deal")
                } footer: {
                    Text("Deal Desk looks it up and answers here, usually within a minute or two. You get an alert when it's ready.")
                }
                if let nearby = d.nearby, !nearby.isEmpty {
                    Section("Nearby dates") { TextBlock(text: nearby) }
                }
                if let notes = d.notes, !notes.isEmpty {
                    Section("Notes") { TextBlock(text: notes) }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .modifier(ScrolledPast(threshold: 150, passed: $heroGone))
            .navigationTitle(deal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The hero carries the name; the bar shows it only once the hero has scrolled away.
                ToolbarItem(placement: .principal) {
                    Text(deal.title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(heroGone ? 1 : 0)
                        .accessibilityHidden(!heroGone)
                }
                if store.isV3 && deal.kind != .sale && deal.sailDay != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        trackButton
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $answering) { verdict in
                AnswerSheet(deal: deal, verdict: verdict, existing: feedback)
            }
            .task(id: deal.id) {
                await store.loadHistory(deal.id)
            }
            .onAppear {
                let target = focus ?? (router.askFocus == deal.id ? DetailFocus.ask : nil)
                if router.askFocus == deal.id { router.askFocus = nil }
                if let target { scroll(proxy, to: target) }
            }
            .onChange(of: router.askFocus) { _, id in
                guard id == deal.id else { return }
                router.askFocus = nil
                scroll(proxy, to: .ask)
            }
        }
    }

    /// Track this sailing (v3), or open it when it is already tracked.
    @ViewBuilder
    private var trackButton: some View {
        if let tracked = store.trackedMatch(for: deal) {
            Button {
                router.openTracked(tracked.id)
            } label: {
                Image(systemName: "binoculars.fill")
            }
            .accessibilityLabel(Text("Tracking this sailing"))
            .accessibilityHint(Text("Opens it in Tracking"))
        } else {
            Button {
                router.trackSeed = TrackSeed(pick: TrackPick(deal: deal), text: nil)
            } label: {
                Image(systemName: "binoculars")
            }
            .accessibilityLabel(Text("Track this sailing"))
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to target: DetailFocus) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // MARK: The scoop

    @ViewBuilder
    private var scoopSection: some View {
        if let scoop = d.scoop?.trimmed, !scoop.isEmpty {
            Section {
                Text(scoop)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                    .id(DetailFocus.scoop)
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("The scoop")
                }
            }
        }
    }

    // MARK: Your answer

    private func answerSection(_ feedback: Feedback) -> some View {
        Section("Your answer") {
            if let verdict = feedback.verdict {
                Label(verdict.title, systemImage: verdict.symbol)
                    .foregroundStyle(Palette.verdict(verdict))
                    .font(.body.weight(.semibold))
            }
            let reasons = (feedback.data.reasons ?? []).map { Verdict.reasonTitle($0) }
            if !reasons.isEmpty {
                ChipList(items: reasons)
            }
            if let note = feedback.data.note, !note.isEmpty {
                TextBlock(text: note)
            }
            if pending {
                Label("Waiting to send — it goes out when you're back online.", systemImage: "arrow.up.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let reply = feedback.reply {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    TextBlock(text: reply)
                }
            } else {
                Text("Claude reads this on the next check.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Change answer") {
                answering = feedback.verdict ?? .interested
            }
        }
    }

    // MARK: Money

    private var priceSection: some View {
        Section("Price") {
            if let range = deal.priceRange {
                PriceMeter(range: range, pctUnder: deal.pctUnder, style: .detail)
                    .padding(.vertical, 6)
                    .id(DetailFocus.price)
            } else if let under = UnderTypical.text(pct: deal.pctUnder, typical: deal.typicalPP) {
                Text(under)
                    .font(.subheadline.weight(.semibold))
                    .id(DetailFocus.price)
            }
            if let total = d.totalFor3 {
                InfoRow(label: "For 3", value: Fmt.usd(total), note: d.totalAssumes)
            }
            if let pp = d.pricePP, pp > 0 {
                InfoRow(label: "Per person", value: Fmt.usd(pp), note: taxesNote)
            }
            if let night = d.perNightPP {
                InfoRow(label: "Per night", value: "\(Fmt.usd(night)) pp")
            }
            if let typical = deal.typicalPP {
                InfoRow(label: "Typical", value: "\(Fmt.usd(typical)) pp")
            }
            if let lowest = d.lowestSeenPP {
                InfoRow(label: "Lowest seen", value: "\(Fmt.usd(lowest)) pp")
            }
            if let previous = d.previousPP {
                InfoRow(label: "Was", value: "\(Fmt.usd(previous)) pp",
                        note: deal.dropPP.map { "down \(Fmt.usd($0)) pp" })
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

    /// Fits My Trip, or the reasons it doesn't, worked out live from the trip settings.
    private var tripFitSection: some View {
        let fit = store.fit(deal)
        return Section("Your trip") {
            if fit.fits {
                Label("Fits your trip", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Palette.fits)
                    .font(.body.weight(.semibold))
                if let tradeoff = fit.tradeoff {
                    Text(tradeoff)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Not for this trip", systemImage: "suitcase")
                    .foregroundStyle(Palette.call)
                    .font(.body.weight(.semibold))
                if !fit.reasons.isEmpty {
                    Text(fit.reasons.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var offersSection: some View {
        Section("Offers") {
            ForEach(Array((d.offers ?? []).enumerated()), id: \.offset) { item in
                InfoRow(label: item.element.label, value: item.element.value)
            }
            if let ends = deal.endsDay {
                InfoRow(label: "Ends", value: Fmt.weekday(ends), note: Fmt.countdown(ends))
            }
            if let pp = d.pricePP, pp > 0 {
                InfoRow(label: "From", value: "\(Fmt.usd(pp)) pp", note: taxesNote)
            }
        }
    }

    // MARK: Why

    private var whySection: some View {
        Section("Why it's a deal") {
            if let why = d.why, !why.isEmpty {
                TextBlock(text: why)
            }
            if let score = d.score {
                InfoRow(label: "Score", value: d.scoreLabel.map { "\(score) · \($0)" } ?? String(score))
            }
            if let how = d.scoreHow, !how.isEmpty {
                Text(how)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cabin

    @ViewBuilder
    private var cabinSection: some View {
        if deal.cabinTitle != nil || d.cabinName != nil {
            Section("Cabin") {
                if let type = deal.cabinType {
                    InfoRow(label: "Type", value: type.title)
                }
                if let name = d.cabinName, !name.isEmpty {
                    InfoRow(label: "Category", value: name)
                }
                if deal.cabinType == .balcony {
                    InfoRow(label: "Ocean view",
                            value: d.oceanViewConfirmed == true ? "Confirmed" : "Not confirmed",
                            valueColor: d.oceanViewConfirmed == true ? Palette.fits : Color.secondary)
                }
            }
        }
    }

    /// Every category the sources list, with its price; the one this deal is about is marked.
    @ViewBuilder
    private var cabinOptionsSection: some View {
        let options = (d.cabinOptions ?? []).filter { ($0.category ?? "").isEmpty == false }
        if !options.isEmpty {
            Section("Cabin options") {
                ForEach(Array(options.enumerated()), id: \.offset) { item in
                    if item.offset == 0 {
                        CabinOptionRow(option: item.element, current: isCurrent(item.element))
                            .id(DetailFocus.cabins)
                    } else {
                        CabinOptionRow(option: item.element, current: isCurrent(item.element))
                    }
                }
            }
        }
    }

    private func isCurrent(_ option: CabinOption) -> Bool {
        guard let price = option.pricePP, price == d.pricePP else { return false }
        if let name = d.cabinName, let category = option.category {
            return name.caseInsensitiveCompare(category) == .orderedSame
        }
        return option.type == d.cabin
    }

    // MARK: Itinerary

    private var itinerarySection: some View {
        Section("Itinerary") {
            if let dates = deal.dates {
                InfoRow(label: "Dates", value: dates, note: d.nights.map { Fmt.nights($0) })
                    .id(DetailFocus.itinerary)
            }
            if let port = d.port, !port.isEmpty {
                InfoRow(label: "Leaves from", value: port, note: d.roundTrip == true ? "round trip" : nil)
            }
            let days = (d.itineraryDays ?? []).filter { ($0.port ?? "").isEmpty == false }
            if !days.isEmpty {
                ForEach(Array(days.enumerated()), id: \.offset) { item in
                    ItineraryRow(day: item.element, fallbackDay: item.offset + 1)
                }
            } else if let route = deal.route {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route").foregroundStyle(.secondary)
                    Text(route)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let region = d.region, !region.isEmpty {
                InfoRow(label: "Region", value: region)
            }
            if let flight = d.flight, !flight.isEmpty {
                InfoRow(label: "Flight", value: flight)
            }
            InfoRow(label: "Line", value: deal.line)
            if let size = deal.sizeTier {
                InfoRow(label: "Ship size", value: size.title, note: size.tonnage)
            } else if let size = deal.sizeTitle {
                InfoRow(label: "Ship size", value: size)
            }
            if let classTitle = deal.classTitle, deal.shipClass != .other {
                InfoRow(label: "Ship class", value: classTitle)
            }
        }
    }

    // MARK: Price history

    @ViewBuilder
    private var historySection: some View {
        let points = historyPoints
        if points.count >= 2 {
            Section("Price history") {
                PriceHistoryChart(points: points)
                    .padding(.vertical, 6)
                    .id(DetailFocus.history)
            }
        }
    }

    /// This deal's history, for its own cabin type when the rows say which.
    private var historyPoints: [PricePoint] {
        let all = store.history[deal.id] ?? []
        if let cabin = d.cabin {
            let same = all.filter { $0.cabin == nil || $0.cabin == cabin }
            if same.count >= 2 { return same }
        }
        return all
    }

    // MARK: Perks and deadlines

    @ViewBuilder
    private var perksSection: some View {
        let perks = d.perks ?? []
        if !perks.isEmpty || deal.bookByDay != nil {
            Section("Perks & deadlines") {
                if !perks.isEmpty {
                    ChipList(items: perks)
                }
                if let bookBy = deal.bookByDay {
                    InfoRow(label: "Book by", value: Fmt.weekday(bookBy), note: Fmt.countdown(bookBy),
                            valueColor: Fmt.daysLeft(bookBy) <= 2 ? Palette.call : nil)
                    if let what = d.bookByWhat, !what.isEmpty {
                        InfoRow(label: "For", value: what)
                    }
                }
            }
        }
    }

    // MARK: Sources

    @ViewBuilder
    private var sourcesSection: some View {
        let sources = d.sources ?? []
        if !sources.isEmpty {
            Section("Sources") {
                ForEach(Array(sources.enumerated()), id: \.offset) { item in
                    SourceRow(source: item.element)
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if feedback?.verdict == nil {
                HStack(spacing: 8) {
                    ForEach(Verdict.allCases) { verdict in
                        Button {
                            answering = verdict
                        } label: {
                            Label(verdict.title, systemImage: verdict.symbol)
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Palette.verdict(verdict))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                if let url = deal.link {
                    Link(destination: url) {
                        Label("Open deal", systemImage: "safari")
                            .font(.headline)
                            .foregroundStyle(Palette.onAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityHint(Text(openHint))
                    ShareLink(item: url, subject: Text(deal.title), message: Text(shareText)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel(Text("Share"))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var openHint: String {
        if let label = d.linkLabel, !label.isEmpty { return "Opens \(label)" }
        return "Opens the deal page"
    }

    private var shareText: String {
        var parts = [deal.title]
        if !deal.datesLine.isEmpty { parts.append(deal.datesLine) }
        if let route = deal.route { parts.append(route) }
        if let total = d.totalFor3 {
            parts.append("\(Fmt.usd(total)) for 3")
        } else if let pp = d.pricePP, pp > 0 {
            parts.append("\(Fmt.usd(pp)) pp")
        }
        return parts.joined(separator: " · ")
    }
}

/// One cabin category: name and where it's from on the left, the price per person on the right.
struct CabinOptionRow: View {
    let option: CabinOption
    let current: Bool

    private var detail: String {
        var parts: [String] = []
        if let type = option.type.flatMap({ CabinType(rawValue: $0) }) { parts.append(type.title) }
        if let source = option.source, !source.isEmpty { parts.append(source) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(option.category ?? "")
                        .fontWeight(current ? .semibold : .regular)
                    if current {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.accent)
                            .accessibilityLabel(Text("this deal"))
                    }
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let price = option.pricePP {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Fmt.usd(price)) pp")
                        .monospacedDigit()
                        .fontWeight(current ? .semibold : .regular)
                    if let taxes = option.taxesIncluded {
                        Text(taxes ? "taxes in" : "plus taxes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Day 2 · Mon Sep 6" / "Cozumel" / "8:00 AM – 5:00 PM".
struct ItineraryRow: View {
    let day: ItineraryDay
    let fallbackDay: Int

    private var when: String {
        var parts = ["Day \(day.day ?? fallbackDay)"]
        if let date = Fmt.day(day.date) { parts.append(Fmt.weekday(date)) }
        return parts.joined(separator: " · ")
    }

    private var hours: String? {
        let arrive = day.arrive?.trimmed ?? ""
        let depart = day.depart?.trimmed ?? ""
        switch (arrive.isEmpty, depart.isEmpty) {
        case (false, false): return "\(arrive) – \(depart)"
        case (true, false): return "Departs \(depart)"
        case (false, true): return "Arrives \(arrive)"
        case (true, true): return nil
        }
    }

    var body: some View {
        let port = day.port ?? ""
        let atSea = Deal.isSeaDay(port)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(when)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(port)
                    .foregroundStyle(atSea ? Color.secondary : Color.primary)
            }
            Spacer(minLength: 8)
            if let hours {
                Text(hours)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The price over time as a quiet line, the lowest point marked, with the first, lowest and latest prices below.
struct PriceHistoryChart: View {
    let points: [PricePoint]

    private var prices: [Int] { points.map { $0.pricePP } }

    var body: some View {
        let low = prices.min() ?? 0
        let high = prices.max() ?? 0
        let first = points.first
        let last = points.last
        VStack(alignment: .leading, spacing: 8) {
            Sparkline(values: prices)
                .frame(height: 64)
            HStack(alignment: .firstTextBaseline) {
                if let first {
                    column("First seen", Fmt.usd(first.pricePP), first.seen.map { Fmt.shortDay($0) })
                }
                Spacer(minLength: 8)
                column("Lowest", Fmt.usd(low), nil)
                Spacer(minLength: 8)
                if let last {
                    column("Latest", Fmt.usd(last.pricePP), last.seen.map { Fmt.shortDay($0) })
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(low: low, high: high)))
    }

    private func column(_ label: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func spoken(low: Int, high: Int) -> String {
        let first = points.first.map { Fmt.usd($0.pricePP) } ?? ""
        let last = points.last.map { Fmt.usd($0.pricePP) } ?? ""
        return "Price history, \(points.count) prices: from \(first) to \(last), lowest \(Fmt.usd(low)), highest \(Fmt.usd(high))"
    }
}

/// A line through the values, scaled to fit, with the lowest point and the latest point as dots.
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return }
            let span = Double(max(hi - lo, 1))
            let inset: CGFloat = 6
            let w = max(size.width - inset * 2, 1)
            let h = max(size.height - inset * 2, 1)
            func point(_ i: Int) -> CGPoint {
                let x = inset + w * CGFloat(i) / CGFloat(values.count - 1)
                let y = inset + h * CGFloat(1 - Double(values[i] - lo) / span)
                return CGPoint(x: x, y: y)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            context.stroke(line, with: .color(Palette.accent),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let lowIndex = values.firstIndex(of: lo) {
                let p = point(lowIndex)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                             with: .color(Palette.fits))
            }
            let end = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: end.x - 4.5, y: end.y - 4.5, width: 9, height: 9)),
                         with: .color(Palette.accent))
        }
        .accessibilityHidden(true)
    }
}

struct SourceRow: View {
    let source: DealSource

    var body: some View {
        let label = HStack {
            Text(source.name)
            Spacer(minLength: 8)
            if let pp = source.pricePP {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Fmt.usd(pp)) pp").monospacedDigit()
                    if let taxes = source.includesTaxes {
                        Text(taxes ? "taxes in" : "plus taxes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if Fmt.webURL(source.url) != nil {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
        if let url = Fmt.webURL(source.url) {
            Link(destination: url) { label }
                .foregroundStyle(Color.primary)
        } else {
            label
        }
    }
}

/// The detail view's hero: the kind's deep gradient with slow swells, the ship name large, and the dates, route
/// and money in white. Nothing here that the card does not already say.
struct DealHero: View {
    let deal: Deal

    private var d: DealData { deal.data }

    /// "ROYAL CARIBBEAN · ICON CLASS"
    private var heroEyebrow: String {
        [deal.line, deal.kind == .sale ? nil : deal.classTitle].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let kind = deal.kind, kind == .drop || kind == .sale {
                        KindPill(kind: kind, onColor: true)
                    }
                    Text(heroEyebrow.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let score = d.score {
                    ScoreRing(score: score, label: d.scoreLabel, onColor: true)
                }
            }
            Text(deal.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                if deal.kind == .sale {
                    if let ends = deal.endsDay {
                        Text("Ends \(Fmt.deadline(ends))")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                } else {
                    if !deal.datesLine.isEmpty {
                        Text(deal.datesLine)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    if let route = deal.route {
                        Text(route)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(3)
                    }
                    MoneyLine(deal: deal, onColor: true)
                        .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroBackdrop(kind: deal.kind) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Sets `passed` once the list has scrolled more than `threshold` points (iOS 18+; on iOS 17 it stays true, so
/// the bar always shows the title there).
private struct ScrolledPast: ViewModifier {
    let threshold: CGFloat
    @Binding var passed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, now in
                withAnimation(.easeInOut(duration: 0.2)) { passed = now }
            }
        } else {
            content.onAppear { passed = true }
        }
    }
}

#Preview("Detail") {
    NavigationStack {
        DealDetailView(dealId: "sample-fits")
    }
    .environmentObject(Store.preview())
    .environmentObject(Router())
}

#Preview("Sale detail") {
    NavigationStack {
        DealDetailView(dealId: "sample-sale")
    }
    .environmentObject(Store.preview())
    .environmentObject(Router())
}
