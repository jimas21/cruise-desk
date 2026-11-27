import SwiftUI

/// The summary sheet (DESIGN_V2 section 3): everything needed to judge a deal at a glance, calm and in order.
///
///     Icon of the Seas · Icon class                         ( 78 ) Great
///     Sun Sep 5 – Sat Sep 11, 2027 · 6 nights
///     Galveston → Cozumel · Roatán · Costa Maya → Galveston
///     Ocean View Balcony ✓
///     $2,650 for 3                          $1,276 pp · taxes in
///     [low ——●——|—— high]                   18% under typical ($1,560)
///     Why: lowest Icon balcony we've seen this year
struct DealRow: View {
    let deal: Deal
    var note: FitNote? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if deal.kind == .sale {
                SaleLines(deal: deal)
            } else {
                // At accessibility sizes the dates leave the header (it stacks) and lead the lines below.
                SummaryLines(deal: deal, showDates: typeSize.isAccessibilitySize)
            }
            if let note {
                FitCaption(note: note)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Speech.deal(deal, fails: note?.reasons ?? [])))
    }

    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    pill
                    Spacer(minLength: 8)
                    chip
                }
                name
            }
        } else {
            // The dates sit beside the score ring, so the sheet reads top-down without a gap.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    pill
                    name
                    if deal.kind != .sale, !deal.datesLine.isEmpty {
                        Text(deal.datesLine)
                            .font(.subheadline)
                            .monospacedDigit()
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                chip
            }
        }
    }

    /// "Icon of the Seas · Icon class" on one line when it fits, else the class on its own line below.
    @ViewBuilder
    private var name: some View {
        let lines = typeSize.isAccessibilitySize ? 4 : 2
        if deal.kind != .sale, let shipClass = deal.shipClass {
            ViewThatFits(in: .horizontal) {
                (Text(deal.title).font(.headline)
                    + Text("  ·  \(shipClass.title)").font(.subheadline).foregroundStyle(.secondary))
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(deal.title)
                        .font(.headline)
                        .lineLimit(lines)
                    Text(shipClass.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(deal.title)
                .font(.headline)
                .lineLimit(lines)
        }
    }

    /// Only a price drop or a sale carries a pill now; whether a deal fits the trip is the bucket's job.
    @ViewBuilder
    private var pill: some View {
        if let kind = deal.kind, kind == .drop || kind == .sale {
            KindPill(kind: kind)
        }
    }

    @ViewBuilder
    private var chip: some View {
        if let score = deal.data.score {
            ScoreRing(score: score, label: deal.data.scoreLabel)
        }
    }
}

/// Why a deal is (or isn't) in For my trip, as one small caption under the card.
enum FitNote: Equatable {
    /// Best deals: the reasons it misses the trip settings ("4 nights · Florida").
    case fails([String])
    /// For my trip: it fits, in the trade-off price zone.
    case tradeoff(String)

    var reasons: [String] {
        if case .fails(let reasons) = self { return reasons }
        return []
    }

    static func best(_ fit: TripFit) -> FitNote? {
        if fit.fits || fit.reasons.isEmpty { return nil }
        return FitNote.fails(fit.reasons)
    }

    static func trip(_ fit: TripFit) -> FitNote? {
        guard let text = fit.tradeoff else { return nil }
        return FitNote.tradeoff(text)
    }
}

struct FitCaption: View {
    let note: FitNote

    var body: some View {
        switch note {
        case .fails(let reasons):
            Label {
                Text(reasons.joined(separator: " · "))
            } icon: {
                Image(systemName: "suitcase")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.call)
            .lineLimit(2)
        case .tradeoff(let text):
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Dates, route, cabin, money, the price meter and why: one line each.
private struct SummaryLines: View {
    let deal: Deal
    var showDates = true
    @Environment(\.dynamicTypeSize) private var typeSize

    private var lines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showDates && !deal.datesLine.isEmpty {
                Text(deal.datesLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(lines)
                    .minimumScaleFactor(0.85)
            }
            if let route = deal.route {
                Text(route)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
            CabinLine(deal: deal)
            MoneyLine(deal: deal)
                .padding(.top, 2)
            if let range = deal.priceRange {
                PriceMeter(range: range, pctUnder: deal.pctUnder, style: .card)
            } else if let under = UnderTypical.text(pct: deal.pctUnder, typical: deal.typicalPP) {
                Text(under)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let why = deal.data.why, !why.isEmpty {
                (Text("Why: ").foregroundStyle(.secondary) + Text(why))
                    .font(.footnote)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
        }
    }
}

/// "Ocean View Balcony ✓" or "Balcony · type not confirmed".
struct CabinLine: View {
    let deal: Deal
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let cabin = deal.cabinLabel {
            HStack(spacing: 4) {
                Text(cabin)
                if deal.data.oceanViewConfirmed == true {
                    if !cabin.lowercased().contains("ocean") {
                        Text("· ocean view")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.fits)
                } else if deal.cabinType == .balcony {
                    Text("· type not confirmed")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        }
    }
}

/// The money line: the family's total large (or the per-person price when there is no total), then
/// "$1,276 pp · taxes in" small. `onColor` is the white version for the detail hero.
struct MoneyLine: View {
    let deal: Deal
    var onColor = false

    private var quiet: Color { onColor ? Color.white.opacity(0.8) : Color.secondary }

    private var big: (amount: Int, unit: String)? {
        if let total = deal.data.totalFor3 { return (total, "for 3") }
        if let pp = deal.data.pricePP, pp > 0 { return (pp, "pp") }
        return nil
    }

    /// Per-person price, shown small only when the big number is the total.
    private var perPerson: Int? {
        guard deal.data.totalFor3 != nil, let pp = deal.data.pricePP, pp > 0 else { return nil }
        return pp
    }

    private var smallText: String {
        var parts: [String] = []
        if let perPerson { parts.append("\(Fmt.usd(perPerson)) pp") }
        switch deal.data.priceIncludesTaxes {
        case true?: parts.append("taxes in")
        case false?: parts.append("+ taxes")
        case nil: break
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if let big {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    bigText(big.amount, big.unit)
                    Spacer(minLength: 8)
                    details
                }
                VStack(alignment: .leading, spacing: 2) {
                    bigText(big.amount, big.unit)
                    details
                }
            }
        }
    }

    private func bigText(_ amount: Int, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Fmt.usd(amount))
                .font(.system(onColor ? Font.TextStyle.title : Font.TextStyle.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(onColor ? Color.white : Color.primary)
            Text(unit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(quiet)
        }
    }

    private var details: some View {
        HStack(spacing: 4) {
            if !smallText.isEmpty {
                Text(smallText)
            }
            if let drop = deal.dropPP {
                if !smallText.isEmpty { Text("·") }
                Text("↓ \(Fmt.usd(drop)) pp")
                    .foregroundStyle(onColor ? Color.white : Palette.accent)
                    .fontWeight(.semibold)
            }
        }
        .font(.footnote)
        .foregroundStyle(quiet)
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// "18% under typical ($1,560)", "6% over typical ($1,560)" or "At the typical price ($1,560)".
enum UnderTypical {
    static func text(pct: Int?, typical: Int?) -> String? {
        guard let pct else { return nil }
        let money = typical.map { " (\(Fmt.usd($0)))" } ?? ""
        if pct > 0 { return "\(pct)% under typical\(money)" }
        if pct < 0 { return "\(-pct)% over typical\(money)" }
        return "At the typical price\(money)"
    }
}

/// The one graphic on the summary sheet: this price (the dot) against the low and high fares seen for this ship
/// and cabin type, with a tick at the typical price and the stretch from low to typical tinted.
struct PriceMeter: View {
    enum Style { case card, detail }

    let range: Deal.PriceRange
    let pctUnder: Int?
    var style: Style = .card

    private var verdict: String? { UnderTypical.text(pct: pctUnder, typical: range.typical) }

    private var verdictColor: Color {
        guard let pct = pctUnder else { return Color.secondary }
        if pct > 0 { return Palette.fits }
        if pct < 0 { return Palette.call }
        return Color.secondary
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken))
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .card:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    bar.frame(width: 150)
                    verdictText
                }
                VStack(alignment: .leading, spacing: 4) {
                    bar.frame(maxWidth: 260)
                    verdictText
                }
            }
        case .detail:
            VStack(alignment: .leading, spacing: 8) {
                verdictText
                bar
            }
        }
    }

    @ViewBuilder
    private var verdictText: some View {
        if let verdict {
            Text(verdict)
                .font(style == .card ? Font.footnote.weight(.semibold) : Font.subheadline.weight(.semibold))
                .foregroundStyle(verdictColor)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bar: some View {
        VStack(spacing: 3) {
            MeterTrack(range: range)
                .frame(height: 16)
            labels
        }
    }

    private var labels: some View {
        HStack(spacing: 4) {
            if let low = range.low {
                Text(style == .detail ? "Low \(Fmt.usd(low))" : Fmt.usd(low))
            }
            Spacer(minLength: 4)
            if style == .detail, let typical = range.typical {
                Text("Typical \(Fmt.usd(typical))")
                Spacer(minLength: 4)
            }
            if let high = range.high {
                Text(style == .detail ? "High \(Fmt.usd(high))" : Fmt.usd(high))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var spoken: String {
        var parts: [String] = []
        if let pct = pctUnder {
            if pct > 0 {
                parts.append("Price \(pct) percent under typical")
            } else if pct < 0 {
                parts.append("Price \(-pct) percent over typical")
            } else {
                parts.append("Price at the typical price")
            }
        }
        if let typical = range.typical { parts.append("typical \(Fmt.usd(typical))") }
        if let low = range.low { parts.append("low \(Fmt.usd(low))") }
        if let high = range.high { parts.append("high \(Fmt.usd(high))") }
        return parts.joined(separator: ", ")
    }
}

/// The bar itself, drawn in one Canvas: track, the tinted stretch below typical, the typical tick, the price dot.
private struct MeterTrack: View {
    let range: Deal.PriceRange

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 7
            let width = max(size.width - inset * 2, 1)
            let mid = size.height / 2
            func x(_ value: Int) -> CGFloat { inset + width * CGFloat(range.fraction(value)) }

            let track = CGRect(x: 0, y: mid - 3, width: size.width, height: 6)
            context.fill(Path(roundedRect: track, cornerRadius: 3), with: .color(Color(uiColor: .tertiarySystemFill)))
            if let typical = range.typical {
                let start = range.low.map { x($0) } ?? inset
                let end = x(typical)
                if end > start {
                    let good = CGRect(x: start, y: mid - 3, width: end - start, height: 6)
                    context.fill(Path(roundedRect: good, cornerRadius: 3), with: .color(Palette.fits.opacity(0.4)))
                }
                let tick = CGRect(x: end - 1, y: mid - 7, width: 2, height: 14)
                context.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(Color.secondary))
            }
            let dot = CGRect(x: x(range.price) - 6.5, y: mid - 6.5, width: 13, height: 13)
            context.fill(Path(ellipseIn: dot), with: .color(Palette.card))
            context.fill(Path(ellipseIn: dot.insetBy(dx: 2, dy: 2)), with: .color(Palette.accent))
        }
        .accessibilityHidden(true)
    }
}

/// A deal drawn as a card, the way the Deals and Reviewed lists show it. The footer (Claude's reply on
/// Reviewed) sits inside the same card.
struct DealCard<Footer: View>: View {
    let deal: Deal
    var note: FitNote? = nil
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DealRow(deal: deal, note: note)
            footer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(highlight: deal.isExceptional))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension DealCard where Footer == EmptyView {
    init(deal: Deal, note: FitNote? = nil) {
        self.init(deal: deal, note: note, footer: { EmptyView() })
    }
}

/// Lists of cards (Deals, Reviewed) use the plain list style on the grouped background, so each card's soft
/// shadow is not clipped by an inset-grouped section.
enum CardList {
    static let gutter: CGFloat = 16
}

extension View {
    /// A list row that is only its own card: side gutters, no cell background, no separator.
    func cardRow() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: CardList.gutter, bottom: 7, trailing: CardList.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The list around those cards.
    func cardList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

/// Sale rows: the top two offers as "label value", then when it ends.
private struct SaleLines: View {
    let deal: Deal

    private var offers: [OfferRow] { Array((deal.data.offers ?? []).prefix(2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(offers.enumerated()), id: \.offset) { item in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.element.label)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(item.element.value)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.element.label)
                            .foregroundStyle(.secondary)
                        Text(item.element.value)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }
            if offers.isEmpty, let why = deal.data.why, !why.isEmpty {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let ends = deal.endsDay {
                Text("Ends \(Fmt.deadline(ends))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Fmt.daysLeft(ends) <= 2 ? Palette.call : Color.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview("Rows") {
    List {
        ForEach(Samples.deals) { deal in
            DealCard(deal: deal).cardRow()
        }
    }
    .cardList()
}
