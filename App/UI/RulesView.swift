import SwiftUI

/// Tab 4: Claude's suggested rules, Jim's own rules, paused/declined ones, and what Claude looks for.
struct RulesView: View {
    @EnvironmentObject private var store: Store
    @State private var adding = false
    @State private var deleting: Rule?

    private func rules(_ statuses: Set<RuleStatus>) -> [Rule] {
        store.rules.filter { rule in rule.status.map { statuses.contains($0) } ?? false }
    }

    var body: some View {
        NavigationStack {
            List {
                let proposed = rules([.proposed])
                if !proposed.isEmpty {
                    Section {
                        ForEach(proposed) { rule in
                            ProposedRuleRow(rule: rule)
                        }
                    } header: {
                        Text("Claude suggests")
                    } footer: {
                        Text("Use turns a suggestion into one of your rules. No tells Claude to drop it.")
                    }
                }

                Section {
                    ForEach(rules([.active])) { rule in
                        ActiveRuleRow(rule: rule)
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("Add rule", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Your rules")
                } footer: {
                    if rules([.active]).isEmpty {
                        Text("No rules yet. Add one here, or when you pass on a deal.")
                    }
                }

                let inactive = rules([.paused, .declined])
                if !inactive.isEmpty {
                    Section("Paused & declined") {
                        ForEach(inactive) { rule in
                            InactiveRuleRow(rule: rule) { deleting = rule }
                        }
                    }
                }

                if !store.profile.isEmpty {
                    Section("What Claude looks for") {
                        ForEach(Array(store.profile.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Rules")
            .refreshable { await store.refresh() }
            .sheet(isPresented: $adding) {
                AddRuleSheet()
            }
            .confirmationDialog("Delete this rule?", isPresented: deletingShown, titleVisibility: .visible,
                                presenting: deleting) { rule in
                Button("Delete", role: .destructive) { store.deleteRule(rule) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("It's removed for good. Pausing keeps it for later.")
            }
        }
    }

    private var deletingShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

private struct RuleText: View {
    let rule: Rule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let unless = rule.data.unless, !unless.isEmpty {
                Text("Unless \(unless)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProposedRuleRow: View {
    let rule: Rule
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RuleText(rule: rule)
            if let why = rule.data.why, !why.isEmpty {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let question = rule.data.question, !question.isEmpty {
                Label(question, systemImage: "questionmark.bubble")
                    .font(.footnote)
                    .foregroundStyle(Palette.accent)
            }
            HStack(spacing: 10) {
                Button("Use") { store.setRule(rule, status: .active) }
                    .buttonStyle(.borderedProminent)
                Button("No") { store.setRule(rule, status: .declined) }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

private struct ActiveRuleRow: View {
    let rule: Rule
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                RuleText(rule: rule)
                if rule.fromClaude {
                    Text("Suggested by Claude").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Pause") { store.setRule(rule, status: .paused) }
                .buttonStyle(.borderless)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button {
                store.setRule(rule, status: .paused)
            } label: {
                Label("Pause", systemImage: "pause.circle")
            }
            .tint(.gray)
        }
    }
}

private struct InactiveRuleRow: View {
    let rule: Rule
    let onDelete: () -> Void
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RuleText(rule: rule)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(rule.status == .declined ? "Declined" : "Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Turn on") { store.setRule(rule, status: .active) }
                    .buttonStyle(.bordered)
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

/// A rule Jim writes himself: what to avoid, and an optional exception.
struct AddRuleSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unless = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. No sailings under 6 nights", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Rule")
                } footer: {
                    Text("\(120 - text.count) characters left").monospacedDigit()
                }
                Section {
                    TextField("e.g. the price is exceptional", text: $unless, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Unless (optional)")
                }
            }
            .navigationTitle("Add rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addRule(text: text.trimmed, unless: unless.trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmed.isEmpty)
                }
            }
            .onChange(of: text) {
                if text.count > 120 { text = String(text.prefix(120)) }
            }
            .onChange(of: unless) {
                if unless.count > 120 { unless = String(unless.prefix(120)) }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Rules") {
    RulesView()
        .environmentObject(Store.preview())
}
