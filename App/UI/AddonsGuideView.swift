import SwiftUI

/// What to buy on a line (CONTRACT_V5 section 3.3): what the fare includes and what it doesn't, the bundles and
/// how they price, each add-on with its range, unit, when to buy and whether it's worth it for a couple or a
/// family, the tips rule, sources and as-of dates, and what we had on our own trips on this line.
struct AddonsGuideView: View {
    let line: String
    @EnvironmentObject private var store: Store
    @State private var guide: AddonsGuide?
    @State private var loaded = false

    private var myTrips: [PastTrip] { store.trips.filter { CruiseLine.same($0.line, line) } }

    var body: some View {
        List {
            if !loaded {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading the guide…").foregroundStyle(.secondary)
                    }
                }
            } else if let guide {
                content(guide)
            } else {
                Section {
                    IllustratedEmpty(title: "Not researched yet",
                                     message: "Deal Desk has no dated add-on prices for \(line) yet. Check the line's own planner after booking.")
                        .listRowBackground(Color.clear)
                }
            }
            tripsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("What to buy on \(line)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: line) {
            guide = await store.addonsGuide(line: line)
            loaded = true
        }
    }

    @ViewBuilder
    private func content(_ guide: AddonsGuide) -> some View {
        if !guide.forParty.isEmpty {
            Section {
                ForEach(guide.forParty) { item in
                    WhatToBuyRow(item: item)
                }
            } header: {
                Text("For your party, a 7-night cruise")
            } footer: {
                Text("Only what you said you usually buy counts in a trip cost (Settings > Trip cost).")
            }
        }
        if !guide.included.isEmpty || !guide.notIncluded.isEmpty {
            Section("In the fare") {
                if !guide.included.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Included").font(.subheadline.weight(.semibold))
                        ChipList(items: guide.included)
                    }
                }
                if !guide.notIncluded.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not included").font(.subheadline.weight(.semibold))
                        ChipList(items: guide.notIncluded)
                    }
                }
            }
        }
        if let tips = guide.gratuity {
            Section("Tips") {
                if let rates = tips.ratesText {
                    Text(rates)
                        .monospacedDigit()
                } else {
                    Text("Rate not researched yet.").foregroundStyle(.secondary)
                }
                if let applies = tips.appliesText {
                    Text(applies).font(.footnote).foregroundStyle(.secondary)
                }
                if let note = tips.note?.trimmed, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                sourceLine(tips.source, asOf: tips.asOf)
            }
        }
        if !guide.bundles.isEmpty {
            Section {
                ForEach(guide.bundles) { bundle in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bundle.name ?? Words.humanize(bundle.key))
                            .font(.headline)
                        if let range = bundle.pricePPPD, let text = AddonPrice.range(range.low, range.high) {
                            Text("\(text) a person a day")
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        if let parts = bundle.includesText, !parts.isEmpty {
                            ChipList(items: parts)
                        } else if let kinds = bundle.includesKinds, !kinds.isEmpty {
                            ChipList(items: kinds.map { AddonKind.title($0) })
                        }
                        if bundle.includesGratuities == true {
                            Text("Tips included").font(.footnote).foregroundStyle(Palette.fits)
                        }
                        if let how = bundle.howItPrices?.trimmed, !how.isEmpty {
                            Text(how).font(.footnote).foregroundStyle(.secondary)
                        }
                        sourceLine(bundle.source, asOf: bundle.asOf)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Bundles")
            }
        }
        if !guide.addons.isEmpty {
            Section {
                ForEach(guide.addons) { addon in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(addon.title).font(.headline)
                            Spacer(minLength: 6)
                            if let when = BuyWhen.text(addon.buyWhen) {
                                TagLabel(text: when)
                            }
                        }
                        Text(addon.priceText)
                            .font(.subheadline)
                            .monospacedDigit()
                        if let rule = addon.cabinRule?.trimmed, !rule.isEmpty {
                            Text(rule).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let couple = addon.worthIt?.couple?.trimmed, !couple.isEmpty {
                            Text("For a couple: \(couple)").font(.footnote)
                        }
                        if let family = addon.worthIt?.family?.trimmed, !family.isEmpty {
                            Text("For a family: \(family)").font(.footnote)
                        }
                        if let notes = addon.notes?.trimmed, !notes.isEmpty {
                            Text(notes).font(.footnote).foregroundStyle(.secondary)
                        }
                        sourceLine(addon.source, asOf: addon.asOf)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Add-ons")
            } footer: {
                Text("Bought after booking, in \(line)'s own planner; usually cheaper before the cruise than on board.")
            }
        }
        if !guide.sources.isEmpty || guide.asOf != nil {
            Section {
                ForEach(guide.sources, id: \.self) { source in
                    if let url = Fmt.webURL(source) {
                        Link(url.host ?? source, destination: url)
                            .font(.footnote)
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                if let asOf = guide.asOf {
                    Text("Prices as of \(asOf). Lines change them often; confirm before you buy.")
                }
            }
        }
    }

    @ViewBuilder
    private func sourceLine(_ source: String?, asOf: String?) -> some View {
        let url = Fmt.webURL(source)
        if url != nil || asOf != nil {
            HStack(spacing: 6) {
                if let asOf { Text("as of \(asOf)") }
                if let url {
                    Link(url.host ?? "source", destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tripsSection: some View {
        if store.has(.trips) {
            Section {
                if myTrips.isEmpty {
                    Text("No \(line) trips logged yet. Log one in My trips and note what you had.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(myTrips) { trip in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.ship).font(.headline)
                        if !trip.datesLine.isEmpty {
                            Text(trip.datesLine).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if trip.extras.isEmpty {
                            Text("No extras noted.").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(trip.extras) { extra in
                                HStack(spacing: 6) {
                                    Text(extra.name)
                                    Text("· \(TripExtra.howTitle(extra.how).lowercased())")
                                        .foregroundStyle(.secondary)
                                    if let liked = extra.liked {
                                        Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsdown")
                                            .foregroundStyle(liked ? Palette.fits : Color.secondary)
                                            .accessibilityLabel(Text(liked ? "liked" : "not liked"))
                                    }
                                }
                                .font(.footnote)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Your trips on this line")
            }
        }
    }
}

/// Settings > Trip cost (CONTRACT_V5 section 2.8): what we usually buy, ports we drive to, the hotel the night
/// before, and what the budget counts. Each change saves at once.
struct TripCostSettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var buyKinds: Set<String> = []
    @State private var groundPorts: [String] = []
    @State private var hotel = true
    @State private var basis = "cabin"
    @State private var ready = false

    var body: some View {
        Form {
            if store.trip == nil {
                Section {
                    Text("Save My Trip once; these settings live on it.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ChipPicker(options: AddonKind.all.filter { $0 != "other" }.map { ReasonOption(id: $0, title: AddonKind.title($0)) },
                           selection: $buyKinds)
            } header: {
                Text("What we usually buy")
            } footer: {
                Text("Only these count in a trip cost; everything else is listed as optional with its price range.")
            }
            Section {
                PickerLink(label: "Ports we drive to",
                           value: groundPorts.isEmpty ? "None: the ports at your home airport count as home" : ListText.join(groundPorts)) {
                    PortPickerScreen(title: "Ports we drive to", kind: .embark, selection: $groundPorts,
                                     footer: "Sailings from these count as drive or train: no flight and no hotel in the total.")
                }
            } footer: {
                Text("For example Vancouver, if you'd rather drive than fly.")
            }
            Section {
                Toggle("Hotel the night before", isOn: $hotel)
            } footer: {
                Text("When you fly to the ship, one room for one night before sailing is added (a dated estimate per port, or listed as not priced).")
            }
            Section {
                Picker("Budget counts", selection: $basis) {
                    Text("Cabin only").tag("cabin")
                    Text("Whole trip").tag("trip")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Budget counts")
            } footer: {
                Text(basis == "cabin" ? "Your budget is the cabin: fare and taxes for the party, before tips and flights."
                                      : "Your budget is the whole trip: fare, taxes, tips, what you buy, flights and the hotel night.")
            }
        }
        .navigationTitle("Trip cost")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(store.trip == nil)
        .onAppear {
            let trip = store.trip
            buyKinds = Set(trip?.buyKinds ?? [])
            groundPorts = trip?.groundPorts ?? []
            hotel = trip?.hotelNightBefore ?? true
            basis = trip?.budgetBasis == "trip" ? "trip" : "cabin"
            ready = true
        }
        .onChange(of: buyKinds) { save() }
        .onChange(of: groundPorts) { save() }
        .onChange(of: hotel) { save() }
        .onChange(of: basis) { save() }
    }

    private func save() {
        guard ready, let trip = store.trip else { return }
        let kinds = AddonKind.all.filter { buyKinds.contains($0) }
        // Opening the screen fills the controls; only a real change is sent.
        let same = kinds == AddonKind.all.filter { (trip.buyKinds ?? []).contains($0) }
            && groundPorts == (trip.groundPorts ?? [])
            && hotel == (trip.hotelNightBefore ?? true)
            && basis == (trip.budgetBasis == "trip" ? "trip" : "cabin")
        guard !same else { return }
        store.saveTripCost(buyKinds: kinds, groundPorts: groundPorts, hotelNightBefore: hotel, budgetBasis: basis)
    }
}
