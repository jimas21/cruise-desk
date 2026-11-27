import SwiftUI

/// Tab 2: answered deals, grouped by answer, each with Claude's reply when it has one.
struct ReviewedView: View {
    @EnvironmentObject private var store: Store
    @State private var path: [String] = []
    private let groups: [Verdict] = [.interested, .later, .pass]

    private var isEmpty: Bool {
        groups.allSatisfy { store.reviewed($0).isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(groups) { verdict in
                    let items = store.reviewed(verdict)
                    if !items.isEmpty {
                        Section {
                            // The group's name as a plain row, so it scrolls with its cards instead of pinning.
                            Label("\(verdict.groupTitle) · \(items.count)", systemImage: verdict.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.verdict(verdict))
                                .monospacedDigit()
                                .accessibilityAddTraits(.isHeader)
                                .listRowInsets(EdgeInsets(top: 16, leading: CardList.gutter + 4, bottom: 2,
                                                          trailing: CardList.gutter))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            ForEach(items) { deal in
                                Button {
                                    path.append(deal.id)
                                } label: {
                                    ReviewedCard(deal: deal, feedback: store.feedback[deal.id],
                                                 pending: store.isPending("feedback", deal.id))
                                }
                                .buttonStyle(CardPressStyle())
                                .cardRow()
                                .accessibilityHint(Text("Opens the details"))
                            }
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
            }
            .cardList()
            .overlay {
                if isEmpty {
                    IllustratedEmpty(title: "Nothing answered yet",
                                     message: "Swipe a deal right for Interested or left for Not for me. Your answers and Claude's replies show up here.")
                }
            }
            .navigationTitle("Reviewed")
            .refreshable { await store.refresh() }
            .navigationDestination(for: String.self) { id in
                DealDetailView(dealId: id)
            }
        }
    }
}

/// The deal's glance card with Claude's reply (or "Waiting to send") inside it.
private struct ReviewedCard: View {
    let deal: Deal
    let feedback: Feedback?
    let pending: Bool

    var body: some View {
        DealCard(deal: deal) {
            if pending {
                Label("Waiting to send", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let reply = feedback?.reply {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(Palette.accent)
                        .font(.footnote)
                    Text(reply)
                        .font(.footnote)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Claude replied: \(reply)"))
            }
        }
    }
}

#Preview("Reviewed") {
    ReviewedView()
        .environmentObject(Store.preview())
}
