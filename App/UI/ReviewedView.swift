import SwiftUI

/// Tab 2: answered deals, grouped by answer, each with Claude's reply when it has one.
struct ReviewedView: View {
    @EnvironmentObject private var store: Store
    private let groups: [Verdict] = [.interested, .later, .pass]

    private var isEmpty: Bool {
        groups.allSatisfy { store.reviewed($0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { verdict in
                    let items = store.reviewed(verdict)
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { deal in
                                NavigationLink(value: deal.id) {
                                    ReviewedRow(deal: deal, feedback: store.feedback[deal.id],
                                                pending: store.isPending("feedback", deal.id))
                                }
                            }
                        } header: {
                            Label("\(verdict.groupTitle) · \(items.count)", systemImage: verdict.symbol)
                                .foregroundStyle(Palette.verdict(verdict))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if isEmpty {
                    ContentUnavailableView {
                        Label("Nothing answered yet", systemImage: "checkmark.circle")
                    } description: {
                        Text("Swipe a deal right for Interested or left for Not for me. Your answers and Claude's replies show up here.")
                    }
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

private struct ReviewedRow: View {
    let deal: Deal
    let feedback: Feedback?
    let pending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DealRow(deal: deal)
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
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
