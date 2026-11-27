import SwiftUI
import UIKit

/// Pages open in Safari, never an in-app browser, so Jim's own sign-ins on the line's site apply.
enum Safari {
    @MainActor static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        Haptics.tap()
    }
}

/// On a card (CONTRACT_V4 sections 1.6 and 1.7): the primary "Book on <Line>" (always the sailing's own line), a
/// small "Seen on <source>" link, the line that says what the button opens, then at most 3 compact agency rows,
/// each with its reason. Nothing opens by itself.
struct BookBar: View {
    let choice: BookChoice
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if !choice.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                primary
                if choice.note != nil || choice.seenOn != nil {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            noteText
                            seen
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                noteText
                                Spacer(minLength: 4)
                                seen
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                noteText
                                seen
                            }
                        }
                    }
                }
                ForEach(choice.alternatives, id: \.self) { alternative in
                    AlternativeRow(alternative: alternative)
                }
            }
        }
    }

    @ViewBuilder
    private var noteText: some View {
        if let note = choice.note {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? 5 : 2)
        }
    }

    @ViewBuilder
    private var primary: some View {
        if let target = choice.primary {
            Button {
                Safari.open(target.url)
            } label: {
                Label(target.title, systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onAccent)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityHint(Text(choice.note ?? "Opens the line's own site in Safari"))
        }
    }

    @ViewBuilder
    private var seen: some View {
        if let source = choice.seenOn {
            SeenOnLink(source: source)
        }
    }
}

/// "Seen on Costco": the page the price came from, small and secondary.
struct SeenOnLink: View {
    let source: BookChoice.Source

    var body: some View {
        Button {
            Safari.open(source.url)
        } label: {
            Text("Seen on \(source.name)")
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.borderless)
        .accessibilityHint(Text("Opens the page the price was seen on"))
    }
}

/// "Or Costco Travel · same fare + $250 Costco Shop Card ›": a clearly labelled second option.
struct AlternativeRow: View {
    let alternative: BookAlternative
    var large = false

    var body: some View {
        if let url = alternative.link {
            Button {
                Safari.open(url)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alternative.rowTitle)
                            .font(large ? .subheadline : .footnote)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(large ? 4 : 2)
                        if large, let pp = alternative.pricePP, pp > 0 {
                            Text(alternative.taxesIncluded == true ? "\(Fmt.usd(pp)) pp · taxes in" : "\(Fmt.usd(pp)) pp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHint(Text("Opens \(alternative.name)'s page in Safari"))
        }
    }
}

/// A detail screen's bottom bar: the large "Book on <Line>" button, with what it opens and where the price was
/// seen underneath.
struct BookButtonLarge: View {
    let choice: BookChoice
    var showsNote = true

    var body: some View {
        if let target = choice.primary {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Safari.open(target.url)
                } label: {
                    Label(target.title, systemImage: "arrow.up.right.square")
                        .font(.headline)
                        .foregroundStyle(Palette.onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityHint(Text(choice.note ?? "Opens the line's own site in Safari"))
                if showsNote, choice.note != nil || choice.seenOn != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            noteText
                            Spacer(minLength: 4)
                            if let source = choice.seenOn { SeenOnLink(source: source) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            noteText
                            if let source = choice.seenOn { SeenOnLink(source: source) }
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var noteText: some View {
        if let note = choice.note {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

/// Detail screens: "Other ways to book", one row per clearly better agency, each with its reason.
struct AlternativesSection: View {
    let choice: BookChoice

    var body: some View {
        if !choice.alternatives.isEmpty {
            Section {
                ForEach(choice.alternatives, id: \.self) { alternative in
                    AlternativeRow(alternative: alternative, large: true)
                }
            } header: {
                Text("Other ways to book")
            } footer: {
                Text("Shown only when an agency is clearly better for the same sailing and cabin. The line's own site stays the main button.")
            }
        } else if choice.primary == nil, let note = choice.note {
            Section {
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "you were in Cozumel 4 weeks ago · you rated Costa Maya 3/10": soft, never a reason a deal is hidden.
struct PortFitCaption: View {
    let fit: PortFit

    var body: some View {
        if !fit.caption.isEmpty {
            Label {
                Text(fit.caption)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
    }
}
