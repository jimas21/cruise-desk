import SwiftUI

/// The small card at the very top of Deals (CONTRACT_V4 section 2.3): "Newsletters · 3 new". It never opens by
/// itself and is hidden while the digest is empty.
struct DigestCard: View {
    let newCount: Int
    let total: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: newCount > 0 ? "envelope.badge" : "envelope.open")
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Newsletters")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if newCount > 0 {
                    Text("\(newCount) new")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.accent, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground())
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(newCount > 0 ? "Newsletters, \(newCount) new" : "Newsletters, \(total) items"))
        .accessibilityHint(Text("Opens the summary of the latest cruise emails"))
        .accessibilityAddTraits(.isButton)
    }

    private var detail: String {
        total == 1 ? "1 item from the latest cruise emails" : "\(total) items from the latest cruise emails"
    }
}

/// The digest: one row per item (headline, one line, who sent it), newest first. A tap opens the email's own link
/// in Safari, or the deal itself when it is already on the board.
struct DigestSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let digest = store.digest, !store.digestItems.isEmpty {
                    Section {
                        ForEach(store.digestItems) { item in
                            DigestRow(item: item, isNew: store.isNew(item), book: store.bookChoice(for: item)) {
                                open(item)
                            }
                        }
                    } footer: {
                        Text(footer(digest))
                    }
                } else {
                    Section {
                        IllustratedEmpty(title: "No newsletters yet",
                                         message: "Cruise emails sent to Deal Desk are folded into one short list here, with their links.")
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Newsletters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func footer(_ digest: DigestDoc) -> String {
        var parts: [String] = []
        if let read = digest.emailsRead, read > 0 { parts.append(read == 1 ? "From 1 email" : "From \(read) emails") }
        if !digest.senders.isEmpty { parts.append(digest.senders.prefix(5).joined(separator: ", ")) }
        parts.append("the same news from several senders shows once")
        return parts.joined(separator: " · ")
    }

    private func open(_ item: DigestItem) {
        if let id = item.dealId, store.deal(id) != nil {
            dismiss()
            router.openDeal(id)
        } else if let url = item.url {
            Safari.open(url)
        }
    }
}

struct DigestRow: View {
    let item: DigestItem
    let isNew: Bool
    let book: BookChoice?
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Label(item.kindValue.title, systemImage: item.kindValue.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        if item.fitsTrip {
                            TagLabel(text: "Fits your trip", color: Palette.fits)
                        }
                        Spacer(minLength: 4)
                        if isNew {
                            Circle()
                                .fill(Palette.accent)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel(Text("New"))
                        }
                    }
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? 6 : 3)
                    if let summary = item.summary?.trimmed, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? 6 : 2)
                    }
                    if !item.factsLine.isEmpty {
                        Text(item.factsLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(2)
                    }
                    if !item.sourceNames.isEmpty {
                        SourceChips(names: item.sourceNames)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(item.dealId != nil ? "Opens the deal" : "Opens the email's link in Safari"))
            if let book {
                BookBar(choice: book)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Small grey chips naming who sent an item.
struct SourceChips: View {
    let names: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(names.prefix(6).enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("From \(names.joined(separator: ", "))"))
    }
}
