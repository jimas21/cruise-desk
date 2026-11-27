import SwiftUI

/// Interested · Not for me · Later, with reason chips, a note, and (for a pass) "make this a rule".
struct AnswerSheet: View {
    let deal: Deal
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var verdict: Verdict
    @State private var reasons: Set<String>
    @State private var note: String
    @State private var makeRule = false
    @State private var ruleText = ""
    @State private var ruleUnless = ""

    init(deal: Deal, verdict: Verdict, existing: Feedback?) {
        self.deal = deal
        _verdict = State(initialValue: verdict)
        let keep = existing?.verdict == verdict
        _reasons = State(initialValue: keep ? Set(existing?.data.reasons ?? []) : [])
        _note = State(initialValue: existing?.data.note ?? "")
    }

    private var canSend: Bool {
        !(makeRule && verdict == .pass && ruleText.trimmed.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Answer", selection: $verdict) {
                        ForEach(Verdict.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deal.title).font(.headline).foregroundStyle(Color.primary)
                        if !deal.tripLine.isEmpty {
                            Text(deal.tripLine).font(.subheadline)
                        }
                    }
                    .textCase(nil)
                    .padding(.bottom, 6)
                }

                if !verdict.options.isEmpty {
                    Section(verdict.optionsTitle) {
                        ChipPicker(options: verdict.options, selection: $reasons)
                    }
                }

                Section {
                    TextField(notePrompt, text: $note, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Note")
                } footer: {
                    if note.count > 400 {
                        Text("\(500 - note.count) characters left").monospacedDigit()
                    }
                }

                if verdict == .pass {
                    Section {
                        Toggle("Make this a rule for future deals", isOn: $makeRule.animation())
                        if makeRule {
                            TextField("Rule, e.g. No sailings under 6 nights", text: $ruleText, axis: .vertical)
                                .lineLimit(1...3)
                            TextField("Unless… (optional)", text: $ruleUnless, axis: .vertical)
                                .lineLimit(1...3)
                        }
                    } footer: {
                        if makeRule {
                            Text("Claude applies your rules to every future deal. You can pause one any time on the Rules tab.")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(verdict.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .fontWeight(.semibold)
                        .disabled(!canSend)
                }
            }
            .onChange(of: verdict) {
                reasons.removeAll()
                if verdict != .pass { makeRule = false }
            }
            .onChange(of: note) {
                if note.count > 500 { note = String(note.prefix(500)) }
            }
            .onChange(of: ruleText) {
                if ruleText.count > 120 { ruleText = String(ruleText.prefix(120)) }
            }
            .onChange(of: ruleUnless) {
                if ruleUnless.count > 120 { ruleUnless = String(ruleUnless.prefix(120)) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var notePrompt: String {
        switch verdict {
        case .interested: return "Anything Claude should check?"
        case .pass: return "What would make it a yes? (optional)"
        case .later: return "Remind yourself why (optional)"
        }
    }

    private func send() {
        let chosen = verdict.options.map { $0.id }.filter { reasons.contains($0) }
        store.answer(deal, verdict: verdict, reasons: chosen, note: note.trimmed)
        if verdict == .pass, makeRule, !ruleText.trimmed.isEmpty {
            store.addRule(text: ruleText.trimmed, unless: ruleUnless.trimmed, fromDeal: deal.id)
        }
        dismiss()
    }
}

#Preview("Answer") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AnswerSheet(deal: Samples.deals[1], verdict: .pass, existing: nil)
                .environmentObject(Store.preview())
        }
}
