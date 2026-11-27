import SwiftUI

/// A thread of questions to Deal Desk (about one deal, or general when `dealId` is nil) with the box to ask the
/// next one. The answerer on the server replies within a minute or two; while an answer is outstanding the
/// thread re-syncs every 15 seconds, and an "Answer ready" push brings Jim straight here.
/// It is one list row, so a push or link can scroll to it as a whole.
struct AskThread: View {
    let dealId: String?
    var prompt = "Ask anything about this deal"
    var suggestions: [String] = ["Is this a good price?", "What's included?", "Which cabin would you pick?"]
    @EnvironmentObject private var store: Store
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        let thread = store.thread(dealId)
        let waiting = store.awaitingAnswer(dealId)
        VStack(alignment: .leading, spacing: 14) {
            if thread.isEmpty && !suggestions.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            typing = true
                        } label: {
                            Text(suggestion)
                                .font(.subheadline)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            ForEach(thread) { question in
                QuestionBubble(question: question, pending: store.isPending("questions", question.id))
            }
            composer
        }
        .padding(.vertical, 6)
        .task(id: waiting) {
            guard waiting else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                await store.refresh()
            }
        }
    }

    private var canSend: Bool { !text.trimmed.isEmpty }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onChange(of: text) {
                    if text.count > 500 { text = String(text.prefix(500)) }
                }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Palette.accent : Color(uiColor: .tertiaryLabel))
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send question"))
        }
    }

    private func send() {
        guard canSend else { return }
        withAnimation(Motion.snappy) {
            _ = store.ask(text, dealId: dealId)
        }
        text = ""
        typing = false
    }
}

/// Jim's question on the right; Deal Desk's answer (or "looking into it") on the left.
struct QuestionBubble: View {
    let question: Question
    let pending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 36)
                Text(question.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(Text("You asked: \(question.text)"))
            }
            if let answer = question.answer {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("Deal Desk")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    Text(answer)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    let links = (question.data.sources ?? []).compactMap { source -> (String, URL)? in
                        guard let url = Fmt.webURL(source.url) else { return nil }
                        return (source.name ?? url.host ?? "Source", url)
                    }
                    if !links.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(links.enumerated()), id: \.offset) { item in
                                Link(destination: item.element.1) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text(item.element.0)
                                    }
                                    .font(.footnote)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.top, 2)
                    }
                    if let when = question.answered {
                        Text(Fmt.when(when))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.trailing, 24)
            } else if pending {
                Label("Waiting to send — it goes out when you're back online.", systemImage: "arrow.up.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(isLate ? "No answer yet. Deal Desk answers as soon as it can; you'll get an alert."
                                : "Looking into it… usually a minute or two.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var isLate: Bool { Date().timeIntervalSince(question.asked) > 600 }
}

/// The general thread: "Ask Deal Desk" from the Deals tab, or from an "Answer ready" push about no deal.
struct AskSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AskThread(dealId: nil, prompt: "Ask Deal Desk anything",
                              suggestions: ["Is now a good time to book?", "Which of my deals is the best value?",
                                            "What usually goes on sale next?"])
                } footer: {
                    Text("Ask about prices, timing, ships or ways to save. Deal Desk looks it up and answers here, usually within a minute or two. Same honesty rules as the deals.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ask Deal Desk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await store.refresh() }
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview("Ask") {
    AskSheet()
        .environmentObject(Store.preview())
}
