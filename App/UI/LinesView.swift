import SwiftUI

/// "● Tracking live" / "● Limited data" / "● News only": what Deal Desk can honestly see. Never claims more than
/// the server says; an unknown state is shown as it is.
struct CoverageBadge: View {
    let coverage: Coverage?
    var comingSoon = false
    var onColor = false

    private var title: String {
        if comingSoon { return "Coming soon" }
        return coverage?.title ?? "Not known yet"
    }

    private var tint: Color {
        if onColor { return .white }
        if comingSoon { return .secondary }
        switch coverage {
        case .live?: return Palette.fits
        case .limited?: return Palette.call
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(onColor ? 0.2 : 0.12), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Coverage: \(title)"))
    }
}

/// My Lines (DESIGN_V3 section 1): the cruise lines Deal Desk watches for Jim, each with what it can see today.
/// With a `selection` binding it edits My Trip's draft; without one (from Settings) it saves `lines` straight to the
/// trip settings on the server, on every change. v5 adds Collect prices for (prefs/collect) with each line's state,
/// and the per-line add-ons guide.
struct LinesView: View {
    var selection: Binding<[String]>? = nil
    @EnvironmentObject private var store: Store

    private var names: [String] { CruiseLine.choosable(store.catalog) }

    /// What is picked now: the draft's, else the saved trip's (absent = Royal Caribbean only).
    private var chosen: [String] {
        if let selection { return selection.wrappedValue }
        return store.trip?.effectiveLines ?? [CruiseLine.royal]
    }

    private var everyLine: Bool { chosen.isEmpty }

    /// Standalone with no trip settings yet: the list is read-only.
    private var canEdit: Bool { store.isV3 && (selection != nil || store.trip != nil) }

    var body: some View {
        List {
            if !store.isV3 {
                Section {
                    IllustratedEmpty(title: "Lines are coming soon",
                                     message: "Pick any cruise line once the deal server's next update lands. Until then Deal Desk covers Royal Caribbean.")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Toggle("Every line", isOn: everyBinding)
                        .disabled(!canEdit)
                } footer: {
                    Text("Every line means For my trip and Claude's checks take any cruise line. Royal Caribbean is fully covered; the others fill in as their sources come online.")
                }
                Section {
                    ForEach(names, id: \.self) { name in
                        Button {
                            toggle(name)
                        } label: {
                            LineRow(name: name, line: store.catalog.line(name), picked: everyLine || isPicked(name),
                                    dimmed: everyLine,
                                    countText: store.has(.catalog5) ? LineRow.catalogCount(store.catalog.line(name)) : nil)
                        }
                        .disabled(!canEdit || everyLine)
                        .accessibilityAddTraits(isPicked(name) ? .isSelected : [])
                    }
                } header: {
                    Text("Lines")
                } footer: {
                    if !canEdit {
                        Text("Save My Trip once to choose lines.")
                    } else if selection == nil && store.showsDefaultLinesBanner {
                        Text("Not saved yet, so only Royal Caribbean counts (the default). Any change here saves at once.")
                    } else if !everyLine && chosen.count == 1 {
                        Text("Keep at least one line, or turn on Every line.")
                    } else if selection == nil {
                        Text("Changes save at once.")
                    }
                }
                if store.has(.collect) {
                    CollectSection()
                }
                if store.has(.reference) {
                    Section {
                        ForEach(names, id: \.self) { name in
                            NavigationLink {
                                AddonsGuideView(line: name)
                            } label: {
                                Text("What to buy on \(name)")
                            }
                        }
                    } header: {
                        Text("What to buy, per line")
                    } footer: {
                        Text("What each line includes, its bundles and add-ons with dated prices and sources.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Lines")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadCollect() }
    }

    private func isPicked(_ name: String) -> Bool {
        chosen.contains { CruiseLine.same($0, name) }
    }

    private var everyBinding: Binding<Bool> {
        Binding(get: { everyLine }, set: { on in
            save(on ? [] : [CruiseLine.royal])
        })
    }

    private func toggle(_ name: String) {
        var next = chosen
        if isPicked(name) {
            guard next.count > 1 else { return }
            next.removeAll { CruiseLine.same($0, name) }
        } else {
            next.append(name)
        }
        // Keep the server's order.
        save(names.filter { line in next.contains { CruiseLine.same($0, line) } })
        Haptics.tap()
    }

    private func save(_ lines: [String]) {
        if let selection {
            selection.wrappedValue = lines
        } else {
            store.saveLines(lines)
        }
    }
}

/// One line: its name, what Deal Desk can see for it and how much, and a check when picked.
struct LineRow: View {
    let name: String
    let line: CatalogLine?
    var picked = false
    var dimmed = false
    /// v5: "412 sailings we can see" or "0 we can see", in place of the coverage note.
    var countText: String? = nil

    private var detail: String? {
        var parts: [String] = []
        if let countText {
            parts.append(countText)
        } else if let note = line?.coverageNote?.trimmed, !note.isEmpty {
            parts.append(note)
        } else if let sailings = line?.sailings, sailings > 0 {
            parts.append("\(sailings) sailings")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .foregroundStyle(Color.primary)
                HStack(spacing: 8) {
                    CoverageBadge(coverage: line?.coverageState)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 8)
            if picked {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(dimmed ? Color.secondary : Palette.accent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Collect prices for (prefs/collect, CONTRACT_V5 section 1.2): which lines Deal Desk gathers prices for, apart
/// from what For my trip shows. Each line says where it stands: "collecting · 412 sailings", "queued · first
/// results in about 1 day", "no source we read lists this line". Saves on every change.
struct CollectSection: View {
    @EnvironmentObject private var store: Store

    private var names: [String] { CruiseLine.choosable(store.catalog) }
    private var prefs: CollectPrefs { store.collectPrefs }

    var body: some View {
        Section {
            Toggle("Every line", isOn: everyBinding)
            ForEach(names, id: \.self) { name in
                let always = CruiseLine.isRoyal(name)
                let on = always || prefs.every || prefs.has(name)
                Button {
                    toggle(name)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).foregroundStyle(Color.primary)
                            Text(stateText(name))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        if on {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(always || prefs.every ? Color.secondary : Palette.accent)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .disabled(always || prefs.every)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        } header: {
            Text("Collect prices for")
        } footer: {
            Text("Deal Desk always collects Royal Caribbean and the lines above. Lines added here start on the next pass; Every line runs on a slower cycle so the daily budgets hold.")
        }
    }

    private func stateText(_ name: String) -> String {
        if let line = store.collectState?.line(name) {
            var text = line.stateText
            if let note = line.note?.trimmed, !note.isEmpty, line.state != "no_source" { text += " · \(note)" }
            return text
        }
        if CruiseLine.isRoyal(name) { return "always collected" }
        return prefs.every || prefs.has(name) ? "added · first results on the next pass" : "not collected"
    }

    private var everyBinding: Binding<Bool> {
        Binding(get: { prefs.every }, set: { on in
            var next = prefs
            next.every = on
            store.saveCollect(next)
            Task { await store.loadCollect() }
        })
    }

    private func toggle(_ name: String) {
        var next = prefs
        if next.has(name) {
            next.lines.removeAll { CruiseLine.same($0, name) }
        } else {
            guard next.lines.count < 12 else { return }
            next.lines.append(name)
        }
        store.saveCollect(next)
        Task { await store.loadCollect() }
    }
}

#Preview("My Lines") {
    NavigationStack {
        LinesView(selection: .constant(["Royal Caribbean", "Celebrity"]))
    }
    .environmentObject(Store.preview())
}
