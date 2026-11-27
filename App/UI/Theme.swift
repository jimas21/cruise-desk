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

/// [FITS] [YOUR CALL] [PRICE DROP] [SALE]
struct KindPill: View {
    let kind: DealKind

    var body: some View {
        Text(kind.pill)
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(Palette.kind(kind))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.kind(kind).opacity(0.14), in: Capsule())
            .accessibilityLabel(Text(kind.title))
    }
}

/// The score in a rounded square with its label below ("70" / "Great").
struct ScoreChip: View {
    let score: Int
    let label: String?
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 40

    private var strong: Bool { label == "Exceptional" }

    private var spoken: String {
        if let label, !label.isEmpty { return "Score \(score), \(label)" }
        return "Score \(score)"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(String(score))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(strong ? Palette.onAccent : Palette.accent)
                .frame(minWidth: side, minHeight: side)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(strong ? Palette.accent : Palette.accent.opacity(0.13))
                )
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
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
            if on {
                selection.remove(option.id)
            } else {
                selection.insert(option.id)
            }
            Haptics.tap()
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(on ? Palette.onAccent : Color.primary)
                .background(Capsule().fill(on ? Palette.accent : Color(uiColor: .tertiarySystemFill)))
        }
        .buttonStyle(.plain)
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
