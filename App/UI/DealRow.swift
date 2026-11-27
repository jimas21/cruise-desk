import SwiftUI

/// The glance. Exactly DESIGN.md's row and nothing more:
///
///     [FITS]                                   [ 70 ]
///     Icon of the Seas                          Great
///     7 nights · Oct 15–22, 2028 · Galveston
///     Balcony · type not confirmed
///     $2,580 for 3          $1,138 pp · usually $1,520
///     Lowest Icon balcony we've seen — $163/night vs $216
struct DealRow: View {
    let deal: Deal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if deal.kind == .sale {
                SaleLines(deal: deal)
            } else {
                SailingLines(deal: deal)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Speech.deal(deal)))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let kind = deal.kind {
                    KindPill(kind: kind)
                }
                if deal.kind == .call, let breaks = deal.data.breaks, !breaks.isEmpty {
                    Text(breaks)
                        .font(.caption)
                        .foregroundStyle(Palette.call)
                        .lineLimit(1)
                }
                Text(deal.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let score = deal.data.score {
                ScoreChip(score: score, label: deal.data.scoreLabel)
            }
        }
    }
}

/// Trip, cabin, money and why: one line each.
private struct SailingLines: View {
    let deal: Deal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !deal.tripLine.isEmpty {
                Text(deal.tripLine)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            CabinLine(deal: deal)
            MoneyLine(deal: deal)
            if let why = deal.data.why, !why.isEmpty {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// "Balcony · ✓ ocean view" or "Balcony · type not confirmed".
struct CabinLine: View {
    let deal: Deal

    var body: some View {
        if let cabin = deal.cabinTitle {
            HStack(spacing: 4) {
                Text(cabin)
                if deal.data.oceanViewConfirmed == true {
                    Text("·").foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                        Text("ocean view")
                    }
                    .foregroundStyle(Palette.fits)
                } else if deal.cabinType == .balcony {
                    Text("· type not confirmed").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .lineLimit(1)
        }
    }
}

/// The money line: the family's total large (or the per-person price when there is no total), details small.
struct MoneyLine: View {
    let deal: Deal

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
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var details: some View {
        HStack(spacing: 4) {
            if let perPerson {
                Text("\(Fmt.usd(perPerson)) pp")
            }
            if let drop = deal.dropPP {
                if perPerson != nil { Text("·") }
                Text("↓ \(Fmt.usd(drop)) pp")
                    .foregroundStyle(Palette.accent)
                    .fontWeight(.semibold)
            }
            if let usual = deal.data.usualPP {
                if perPerson != nil || deal.dropPP != nil { Text("·") }
                Text("usually \(Fmt.usd(usual))")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// Sale rows: the top two offers as "label value", then when it ends.
private struct SaleLines: View {
    let deal: Deal

    private var offers: [OfferRow] { Array((deal.data.offers ?? []).prefix(2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(offers.enumerated()), id: \.offset) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.element.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(item.element.value)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .lineLimit(1)
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
            DealRow(deal: deal)
        }
    }
}
