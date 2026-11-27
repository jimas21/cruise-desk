import SwiftUI

/// One deal, in short labelled sections. Large title = ship; everything else is a label/value list.
struct DealDetailView: View {
    let dealId: String
    @EnvironmentObject private var store: Store

    var body: some View {
        if let deal = store.deal(dealId) {
            DealDetailContent(deal: deal, feedback: store.feedback[deal.id],
                              pending: store.isPending("feedback", deal.id))
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
    @State private var answering: Verdict?
    @State private var heroGone = false

    private var d: DealData { deal.data }

    var body: some View {
        List {
            Section {
                DealHero(deal: deal)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)

            if let feedback, feedback.verdict != nil {
                answerSection(feedback)
            }
            if deal.kind == .sale {
                offersSection
            } else {
                priceSection
            }
            whySection
            if deal.kind != .sale {
                cabinSection
                tripSection
            }
            perksSection
            sourcesSection
            if let nearby = d.nearby, !nearby.isEmpty {
                Section("Nearby dates") { TextBlock(text: nearby) }
            }
            if let notes = d.notes, !notes.isEmpty {
                Section("Notes") { TextBlock(text: notes) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
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
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $answering) { verdict in
            AnswerSheet(deal: deal, verdict: verdict, existing: feedback)
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
            if let total = d.totalFor3 {
                InfoRow(label: "For 3", value: Fmt.usd(total), note: d.totalAssumes)
            }
            if let pp = d.pricePP, pp > 0 {
                InfoRow(label: "Per person", value: Fmt.usd(pp), note: taxesNote)
            }
            if let night = d.perNightPP {
                InfoRow(label: "Per night", value: "\(Fmt.usd(night)) pp")
            }
            if let usual = d.usualPP {
                InfoRow(label: "Usually", value: "\(Fmt.usd(usual)) pp")
            }
            if let lowest = d.lowestSeenPP {
                InfoRow(label: "Lowest seen", value: "\(Fmt.usd(lowest)) pp")
            }
            if let previous = d.previousPP {
                InfoRow(label: "Was", value: "\(Fmt.usd(previous)) pp",
                        note: deal.dropPP.map { "down \(Fmt.usd($0)) pp" },
                        valueColor: nil)
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

    // MARK: Cabin and trip

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

    private var tripSection: some View {
        Section("Trip") {
            if let range = deal.dateRange {
                InfoRow(label: "Dates", value: range, note: d.nights.map { Fmt.nights($0) })
            }
            if let region = d.region, !region.isEmpty {
                InfoRow(label: "Region", value: region)
            }
            if let port = d.port, !port.isEmpty {
                InfoRow(label: "Leaves from", value: port, note: d.roundTrip == true ? "round trip" : nil)
            }
            if let stops = d.ports, !stops.isEmpty {
                InfoRow(label: "Stops", value: stops.joined(separator: "\n"))
            }
            if let flight = d.flight, !flight.isEmpty {
                InfoRow(label: "Flight", value: flight)
            }
            if let shipClass = d.shipClass, shipClass != "other" {
                InfoRow(label: "Ship class", value: shipClass.capitalized)
            }
        }
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
        if !deal.tripLine.isEmpty { parts.append(deal.tripLine) }
        if let total = d.totalFor3 {
            parts.append("\(Fmt.usd(total)) for 3")
        } else if let pp = d.pricePP, pp > 0 {
            parts.append("\(Fmt.usd(pp)) pp")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SourceRow: View {
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

/// The detail view's hero: the kind's deep gradient with slow swells, the ship name large, and the glance
/// numbers in white. Nothing here that the row does not already say.
struct DealHero: View {
    let deal: Deal

    private var d: DealData { deal.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let kind = deal.kind {
                        KindPill(kind: kind, onColor: true)
                    }
                    if deal.kind == .call, let breaks = d.breaks, !breaks.isEmpty {
                        Text("Breaks: \(breaks)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
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
                    if !deal.tripLine.isEmpty {
                        Text(deal.tripLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.92))
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
}

#Preview("Sale detail") {
    NavigationStack {
        DealDetailView(dealId: "sample-sale")
    }
    .environmentObject(Store.preview())
}
