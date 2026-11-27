import SwiftUI
import UIKit

/// DESIGN.md colours. One accent (harbor teal); kind colours only ever appear on the small kind pill.
enum Palette {
    static let accent = dynamic(light: 0x0B6E8A, dark: 0x3FB3D1)
    static let fits = dynamic(light: 0x1D7F4E, dark: 0x4CC387)
    static let call = dynamic(light: 0x8A5A0B, dark: 0xE3A94A)
    static let drop = accent
    static let sale = dynamic(light: 0x7A3E8F, dark: 0xC48BD8)
    /// Text on a filled accent shape (white on #0B6E8A; near-black on the brighter dark-mode #3FB3D1).
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x05232D)
    /// Warm gold, only for the gentle highlight on Exceptional deals (ring end and card edge).
    static let highlight = dynamic(light: 0xD99A2B, dark: 0xF2C46B)
    /// Card surface on the grouped background.
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    /// The detail hero's deep gradient for each kind. Fixed in both modes so white text always reads on it.
    static func hero(_ kind: DealKind?) -> [Color] {
        switch kind {
        case .fits?: return [Color(hex: 0x1D7F4E), Color(hex: 0x0B6E8A)]
        case .call?: return [Color(hex: 0x9A6512), Color(hex: 0x6E3F14)]
        case .drop?: return [Color(hex: 0x0E7C99), Color(hex: 0x0A3F5C)]
        case .sale?: return [Color(hex: 0x7A3E8F), Color(hex: 0x3B2C7A)]
        case nil: return [Color(hex: 0x0B6E8A), Color(hex: 0x0A3F5C)]
        }
    }

    static func kind(_ kind: DealKind) -> Color {
        switch kind {
        case .fits: return fits
        case .call: return call
        case .drop: return drop
        case .sale: return sale
        }
    }

    static func verdict(_ verdict: Verdict) -> Color {
        switch verdict {
        case .interested: return fits
        case .pass: return Color(uiColor: .systemRed)
        case .later: return Color(uiColor: .systemGray)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            rgb(traits.userInterfaceStyle == .dark ? dark : light)
        }))
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

extension DealKind {
    var symbol: String {
        switch self {
        case .fits: return "checkmark.seal.fill"
        case .call: return "questionmark.diamond.fill"
        case .drop: return "arrow.down.right"
        case .sale: return "tag.fill"
        }
    }
}

extension Deal {
    var isExceptional: Bool { data.scoreLabel == "Exceptional" }
}

/// [✓ FITS] [? YOUR CALL] [↘ PRICE DROP] [SALE]: the only place kind colours appear on a list.
/// `onColor` is the white version used on the detail hero.
struct KindPill: View {
    let kind: DealKind
    var onColor = false

    var body: some View {
        let tint = onColor ? Color.white : Palette.kind(kind)
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: 9, weight: .heavy))
                .imageScale(.small)
            Text(kind.pill)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(onColor ? 0.2 : 0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(onColor ? 0.35 : 0.22), lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.title))
    }
}

/// The deal score as a ring gauge (the ring fills to the score out of 100), its label below ("70" / "Great").
/// Exceptional deals get a teal-to-gold ring with a soft glow.
struct ScoreRing: View {
    let score: Int
    let label: String?
    var onColor = false
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    private var exceptional: Bool { label == "Exceptional" }
    private var fraction: Double { min(max(Double(score), 0), 100) / 100 }

    private var spoken: String {
        if let label, !label.isEmpty { return "Score \(score), \(label)" }
        return "Score \(score)"
    }

    private var ring: AnyShapeStyle {
        if onColor { return AnyShapeStyle(Color.white) }
        if exceptional {
            return AnyShapeStyle(AngularGradient(colors: [Palette.accent, Palette.highlight, Palette.accent],
                                                 center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
        }
        return AnyShapeStyle(Palette.accent)
    }

    var body: some View {
        let line = max(side * 0.1, 3.5)
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(onColor ? Color.white.opacity(0.25) : Palette.accent.opacity(0.14), lineWidth: line)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ring, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: exceptional && !onColor ? Palette.highlight.opacity(0.45) : .clear, radius: 4)
                Text(String(score))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(onColor ? Color.white : Color.primary)
                    .minimumScaleFactor(0.7)
                    .padding(line)
            }
            .frame(width: side, height: side)
            if let label, !label.isEmpty {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(onColor ? Color.white.opacity(0.85) : (exceptional ? Palette.highlight : Color.secondary))
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }
}

/// A deal card: continuous corners, a soft shadow in light mode, a hairline edge in dark mode, and a gentle
/// teal-to-gold edge when the deal is Exceptional.
struct CardBackground: View {
    var highlight = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape
            .fill(Palette.card)
            .shadow(color: Color.black.opacity(scheme == .dark ? 0 : 0.07), radius: 9, x: 0, y: 3)
            .shadow(color: highlight ? Palette.highlight.opacity(scheme == .dark ? 0.18 : 0.16) : .clear, radius: 10, x: 0, y: 2)
            .overlay {
                if highlight {
                    shape.strokeBorder(LinearGradient(colors: [Palette.accent.opacity(0.7), Palette.highlight],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing),
                                       lineWidth: 1.5)
                } else if scheme == .dark {
                    shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
                }
            }
    }
}

/// Cards sink slightly under a finger (not under Reduce Motion).
struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small rounded tag, e.g. "Using" on a way to save.
struct TagLabel: View {
    let text: String
    var color: Color = Palette.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Read-only chips (perks, chosen reasons).
struct ChipList: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Tappable reason chips.
struct ChipPicker: View {
    let options: [ReasonOption]
    @Binding var selection: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                chip(option)
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ option: ReasonOption) -> some View {
        let on = selection.contains(option.id)
        return Button {
            withAnimation(Motion.snappy) {
                if on {
                    selection.remove(option.id)
                } else {
                    selection.insert(option.id)
                }
            }
            Haptics.tap()
        } label: {
            HStack(spacing: 4) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(option.title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Palette.onAccent : Color.primary)
            .background(Capsule().fill(on ? Palette.accent : Color(uiColor: .tertiarySystemFill)))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A label/value row with tabular digits, used by every detail section.
struct InfoRow: View {
    let label: String
    let value: String
    var note: String? = nil
    var valueColor: Color? = nil

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(valueColor ?? Color.primary)
                    .multilineTextAlignment(.trailing)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        } label: {
            Text(label).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Plain text block inside a detail section.
struct TextBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
