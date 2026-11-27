import SwiftUI

/// Tab 3: every way to save in one place. "Live now" first, soonest deadline first; then standing tricks.
struct SaveView: View {
    @EnvironmentObject private var store: Store

    private var live: [Play] {
        store.plays
            .filter { $0.isLive }
            .sorted { ($0.deadlineDay ?? .distantFuture) < ($1.deadlineDay ?? .distantFuture) }
    }

    private var standing: [Play] {
        store.plays.filter { !$0.isLive }
    }

    var body: some View {
        NavigationStack {
            List {
                if !live.isEmpty {
                    Section("Live now") {
                        ForEach(live) { play in
                            NavigationLink(value: play.id) {
                                PlayRow(play: play, note: store.playNotes[play.id])
                            }
                        }
                    }
                }
                if !standing.isEmpty {
                    Section("Standing tricks") {
                        ForEach(standing) { play in
                            NavigationLink(value: play.id) {
                                PlayRow(play: play, note: store.playNotes[play.id])
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if store.plays.isEmpty {
                    ContentUnavailableView {
                        Label("No ways to save yet", systemImage: "tag")
                    } description: {
                        Text("Sales, promo codes and tricks Claude finds land here, with their deadlines.")
                    }
                }
            }
            .navigationTitle("Save")
            .refreshable { await store.refresh() }
            .navigationDestination(for: String.self) { id in
                PlayDetailView(playId: id)
            }
        }
    }
}

/// Title, how much it saves, the deadline, who offers it. One line each.
private struct PlayRow: View {
    let play: Play
    let note: PlayNote?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(play.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let status = note?.status {
                    TagLabel(text: status.tag, color: status == .skip ? Color.secondary : Palette.accent)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let saves = play.data.saves, !saves.isEmpty {
                    Text(saves)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.accent)
                }
                Spacer(minLength: 8)
                if let deadline = play.deadlineDay {
                    Text(Fmt.deadline(deadline))
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Fmt.daysLeft(deadline) <= 2 ? Palette.call : Color.secondary)
                }
            }
            if let who = play.data.who, !who.isEmpty {
                Text(who)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// One way to save, in labelled sections, plus Jim's own take on it.
struct PlayDetailView: View {
    let playId: String
    @EnvironmentObject private var store: Store
    @State private var status: PlayNoteStatus?
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        if let play = store.plays.first(where: { $0.id == playId }) {
            content(play)
        } else {
            ContentUnavailableView("Not found", systemImage: "tag",
                                   description: Text("This way to save is no longer listed."))
        }
    }

    private func content(_ play: Play) -> some View {
        let d = play.data
        let saved = store.playNotes[play.id]
        return List {
            Section {
                if let saves = d.saves, !saves.isEmpty {
                    InfoRow(label: "Saves", value: saves, valueColor: Palette.accent)
                }
                if let who = d.who, !who.isEmpty {
                    InfoRow(label: "Who", value: who)
                }
                if let deadline = play.deadlineDay {
                    InfoRow(label: "Deadline", value: Fmt.weekday(deadline), note: Fmt.countdown(deadline),
                            valueColor: Fmt.daysLeft(deadline) <= 2 ? Palette.call : nil)
                    if let what = d.deadlineWhat, !what.isEmpty {
                        InfoRow(label: "For", value: what)
                    }
                }
                if let fit = d.fit, !fit.isEmpty {
                    InfoRow(label: "Fits your trip", value: fit)
                }
            }
            if let how = d.how, !how.isEmpty {
                Section("How") { TextBlock(text: how) }
            }
            if let stacks = d.stacks, !stacks.isEmpty {
                Section("Stacks with") { TextBlock(text: stacks) }
            }
            if let catchText = d.catchText, !catchText.isEmpty {
                Section("The catch") { TextBlock(text: catchText) }
            }
            if let url = play.link {
                Section {
                    Link(destination: url) {
                        Label(PlayDetailView.openTitle(d.linkLabel), systemImage: "safari")
                    }
                }
            }
            Section {
                Picker("Your take", selection: $status) {
                    Text("Not set").tag(PlayNoteStatus?.none)
                    ForEach(PlayNoteStatus.allCases) { option in
                        Text(option.title).tag(Optional(option))
                    }
                }
                .pickerStyle(.segmented)
                TextField(status == .question ? "Your question for Claude" : "Note (optional)",
                          text: $note, axis: .vertical)
                    .lineLimit(2...6)
                Button("Save") {
                    if let status { store.savePlayNote(playId: play.id, status: status, note: note.trimmed) }
                }
                .disabled(status == nil || !changed(from: saved))
                if store.isPending("playnotes", play.id) {
                    Label("Waiting to send", systemImage: "arrow.up.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let reply = saved?.reply {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Claude").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                        TextBlock(text: reply)
                    }
                }
            } header: {
                Text("Your take")
            } footer: {
                Text("Using it, a question, or skip: Claude reads this on the next check.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(play.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            status = saved?.status
            note = saved?.data.note ?? ""
        }
        .onChange(of: note) {
            if note.count > 500 { note = String(note.prefix(500)) }
        }
    }

    static func openTitle(_ label: String?) -> String {
        if let label, !label.isEmpty { return "Open \(label)" }
        return "Open the offer"
    }

    private func changed(from saved: PlayNote?) -> Bool {
        saved?.status != status || (saved?.data.note ?? "") != note.trimmed
    }
}

#Preview("Save") {
    SaveView()
        .environmentObject(Store.preview())
}
