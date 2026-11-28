import SwiftUI

/// The Tracking tab (DESIGN_V3 section 2): the exact sailings Jim picked, each at a glance as now vs typical vs the
/// lowest seen, with a price sparkline. Swipe left to stop tracking. Until the deal server has v3 it says
/// "coming soon" and offers nothing it can't keep.
struct TrackingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    /// v4: the tab also holds My trips (the cruises already taken), one tap away.
    @State private var side: TrackingSide
    @State private var tripEditor: TripEditorTarget?
    @State private var portShown: PortSummary?

    private static let sideKey = "trackingSide"

    /// Opens on the side last shown, or the one given (previews and screenshots).
    init(side: TrackingSide? = nil) {
        let saved = TrackingSide(rawValue: UserDefaults.standard.string(forKey: TrackingView.sideKey) ?? "")
        _side = State(initialValue: side ?? saved ?? .tracking)
    }

    private var showsTrips: Bool { store.isV3 && side == .trips }

    var body: some View {
        NavigationStack(path: $router.trackingPath) {
            List {
                if store.isV3 {
                    Section {
                        Picker("Show", selection: $side.animation(Motion.snappy)) {
                            Text("Tracking  \(store.tracked.count)").tag(TrackingSide.tracking)
                            Text("My trips  \(store.trips.count)").tag(TrackingSide.trips)
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 6, leading: CardList.gutter, bottom: 4, trailing: CardList.gutter))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                }
                if showsTrips {
                    MyTripsSections(editor: $tripEditor, port: $portShown)
                } else if !store.isV3 {
                    Section {
                        comingSoon
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                } else if store.tracked.isEmpty {
                    Section {
                        empty
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                } else {
                    Section {
                        ForEach(store.tracked) { item in
                            card(item)
                        }
                        Text(footer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .listRowInsets(EdgeInsets(top: 6, leading: CardList.gutter + 4, bottom: 16,
                                                      trailing: CardList.gutter))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .cardList()
            .navigationTitle(showsTrips ? "My trips" : "Tracking")
            .toolbar {
                if showsTrips && store.has(.trips) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            tripEditor = .new
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("Add a trip"))
                        .disabled(store.trips.count >= Store.tripsLimit)
                    }
                } else if store.isV3 && !showsTrips {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                router.trackSeed = TrackSeed()
                            } label: {
                                Label("Pick a sailing", systemImage: "list.bullet")
                            }
                            Button {
                                router.trackSeed = TrackSeed(pick: nil, text: "")
                            } label: {
                                Label("Add from a link", systemImage: "link")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("Track a cruise"))
                        .disabled(store.tracked.count >= Store.trackedLimit)
                    }
                }
            }
            .refreshable {
                await store.refresh(reason: .pull)
            }
            .navigationDestination(for: String.self) { id in
                TrackedDetailView(trackedId: id)
            }
            .onChange(of: side) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: TrackingView.sideKey)
            }
            .sheet(item: $tripEditor) { target in
                PastTripEditor(target: target)
            }
            .sheet(item: $portShown) { port in
                PortDetailView(port: port)
            }
        }
    }

    private var footer: String {
        let count = store.tracked.count
        return "\(count) of \(Store.trackedLimit) · prices fill in from Deal Desk's fare data, never guessed · swipe left to stop tracking"
    }

    @ViewBuilder
    private func cardBody(_ item: TrackedSailing) -> some View {
        let book = store.bookChoice(for: item)
        if book.isEmpty {
            Button {
                router.trackingPath.append(item.id)
            } label: {
                TrackedCard(item: item)
            }
            .buttonStyle(CardPressStyle())
        } else {
            // v4: the card opens the details; the Book bar under it opens the line's own site.
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    router.trackingPath.append(item.id)
                } label: {
                    TrackedCard(item: item, framed: false)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                BookBar(choice: book)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground())
        }
    }

    private func card(_ item: TrackedSailing) -> some View {
        cardBody(item)
        .cardRow()
        .accessibilityHint(Text("Opens the details"))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(Motion.spring) { store.stopTracking(item) }
            } label: {
                Label("Stop", systemImage: "binoculars")
            }
        }
        .accessibilityAction(named: Text("Stop tracking")) {
            withAnimation(Motion.spring) { store.stopTracking(item) }
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            IllustratedEmpty(title: "Nothing tracked yet",
                             message: "Pick a line, ship, date and cabin, or paste a sailing link. Deal Desk fills in the price, the typical price and the lowest it has seen.")
            HStack(spacing: 10) {
                Button("Track a cruise") { router.trackSeed = TrackSeed() }
                    .buttonStyle(.borderedProminent)
                Button("Add from a link") { router.trackSeed = TrackSeed(pick: nil, text: "") }
                    .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
    }

    private var comingSoon: some View {
        IllustratedEmpty(title: "Tracking is coming soon",
                         message: "Pick the exact sailings you want and Deal Desk fills in every price. This switches on by itself once the deal server's next update lands; nothing is lost until then.")
    }
}

/// One tracked sailing at a glance:
///
///     Royal Caribbean · Mega ship                       ● Tracking live
///     Star of the Seas
///     Sat Jun 12 – Sat Jun 19, 2027 · 7 nights
///     Balcony · Ocean View Balcony · Port Canaveral
///     $1,312 pp now                   typical $1,480 · lowest $1,248
///     ~~~~~~~~~~~~~~~~                11% under typical
struct TrackedCard: View {
    let item: TrackedSailing
    /// false when the caller draws the card around it (with the Book bar inside).
    var framed = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.eyebrow)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Text(item.ship)
                        .font(.headline)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                }
                Spacer(minLength: 8)
                TrackedStateBadge(item: item)
            }
            if !item.datesLine.isEmpty {
                Text(item.datesLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.85)
            }
            if !item.pickLine.isEmpty {
                Text(item.pickLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
            TrackedPriceLine(item: item)
                .padding(.top, 2)
            if CatalogIndex.current.has(.sheet), let cost = item.sheet?.tripCost {
                TripCostLine(cost: cost)
            }
            trend
        }
        .modifier(CardFrame(on: framed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Speech.tracked(item)))
    }

    @ViewBuilder
    private var trend: some View {
        let values = item.historyValues
        let under = UnderTypical.text(pct: item.data.pctUnderTypical, typical: nil)
        if values.count >= 2 || under != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    if values.count >= 2 {
                        Sparkline(values: values)
                            .frame(width: 150, height: 30)
                    }
                    underText(under)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if values.count >= 2 {
                        Sparkline(values: values)
                            .frame(maxWidth: 260)
                            .frame(height: 30)
                    }
                    underText(under)
                }
            }
        }
    }

    @ViewBuilder
    private func underText(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle((item.data.pctUnderTypical ?? 0) > 0 ? Palette.fits : Color.secondary)
                .monospacedDigit()
        }
    }
}

/// The card's own padding and background, unless the caller frames it.
struct CardFrame: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CardBackground())
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Which side of the Tracking tab shows: sailings to come, or the cruises already taken.
enum TrackingSide: String {
    case tracking, trips
}

/// "$1,312 pp now" large, then "typical $1,480 · lowest $1,248" small; "filling…" wherever a value isn't in.
struct TrackedPriceLine: View {
    let item: TrackedSailing
    var onColor = false

    private var quiet: Color { onColor ? Color.white.opacity(0.8) : Color.secondary }

    /// typical and lowest repeat the price's own "filling…" (or "no price source…"): then they're left out.
    private var showsCompare: Bool {
        let d = item.data
        if d.pricePP != nil || d.typicalPP != nil || d.lowestSeenPP != nil { return true }
        return item.missing(.typical) != item.missing()
    }

    var body: some View {
        if showsCompare {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    now
                    Spacer(minLength: 8)
                    compare
                }
                VStack(alignment: .leading, spacing: 2) {
                    now
                    compare
                }
            }
        } else {
            now
        }
    }

    @ViewBuilder
    private var now: some View {
        if let price = item.data.pricePP, price > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.usd(price))
                    .font(.system(onColor ? Font.TextStyle.title : Font.TextStyle.title2, design: .rounded,
                                  weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(onColor ? Color.white : Color.primary)
                Text(item.state == .sailed ? "pp last seen"
                                           : (item.data.priceIncludesTaxes == true ? "pp now · taxes in" : "pp now"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(quiet)
            }
        } else {
            let missing = item.missing()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Price")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(quiet)
                // "filling…" reads large and calm; a longer reason stays the size of the text around it.
                Text(missing)
                    .font(missing.count <= 12 ? Font.system(.title3, design: .rounded, weight: .medium)
                                              : Font.subheadline.weight(.medium))
                    .foregroundStyle(quiet)
            }
        }
    }

    private var compare: some View {
        let typical = item.data.typicalPP.map { Fmt.usd($0) } ?? item.missing(.typical)
        let lowest = item.data.lowestSeenPP.map { Fmt.usd($0) } ?? item.missing()
        // Once it has sailed, only the lowest it reached still means something.
        let text = item.state == .sailed ? "lowest \(lowest)" : "typical \(typical) · lowest \(lowest)"
        return Text(text)
            .font(.footnote)
            .foregroundStyle(quiet)
            .monospacedDigit()
            .lineLimit(2)
    }
}

/// Top-right of a tracked card: waiting to send, sailed, or what Deal Desk can see for this sailing.
struct TrackedStateBadge: View {
    let item: TrackedSailing
    var onColor = false

    var body: some View {
        if item.isLocal {
            Label("Saving", systemImage: "arrow.up.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(onColor ? Color.white : Color.secondary)
                .labelStyle(.titleAndIcon)
        } else if item.state == .sailed {
            TagLabel(text: "Sailed", color: onColor ? Color.white : Color.secondary)
        } else if let coverage = item.coverage {
            CoverageBadge(coverage: coverage, onColor: onColor)
        }
    }
}

#Preview("Tracking") {
    TrackingView()
        .environmentObject(Store.preview())
        .environmentObject(Router())
}
