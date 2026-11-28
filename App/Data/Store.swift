import Foundation
import Network
import SwiftUI
import UserNotifications

/// Why the app can't show fresh data right now, in plain words.
enum Problem: Equatable {
    case notConfigured
    case offline(String)
    case unauthorized
    case server(String)

    init(_ error: Error) {
        switch error as? APIError {
        case .notConfigured?: self = .notConfigured
        case .offline(let why)?: self = .offline(why)
        case .unauthorized?: self = .unauthorized
        case .rejected(let why)?: self = .server(why)
        case .server(let why)?: self = .server(why)
        case .notFound?: self = .server("The server doesn't know that address. Check Settings.")
        case .conflict?: self = .server("Something changed at the same time. Pull to refresh.")
        case .unsupported?: self = .server("This deal server doesn't support that yet.")
        case nil: self = .offline(error.localizedDescription)
        }
    }

    var title: String {
        switch self {
        case .notConfigured: return "Not set up yet"
        case .offline: return "Offline"
        case .unauthorized: return "Token not accepted"
        case .server: return "Couldn't refresh"
        }
    }

    var detail: String {
        switch self {
        case .notConfigured: return "Add the deal server's address and app token in Settings."
        case .offline(let why): return why
        case .unauthorized: return "The server turned down this app's token. Paste the current one in Settings."
        case .server(let why): return why
        }
    }

    var symbol: String {
        switch self {
        case .notConfigured: return "gearshape"
        case .offline: return "wifi.slash"
        case .unauthorized: return "key"
        case .server: return "exclamationmark.triangle"
        }
    }
}

/// What the deal server can do. v3 adds lines, tracking, coverage and the refresh nudge (CONTRACT_V3 section 8);
/// until `GET /v1/catalog` says so the app keeps v2 behaviour.
enum ServerLevel: String {
    case unknown, v2, v3
}

/// Why the app asks the server for a light refresh (`POST /v1/refresh`).
enum RefreshReason: String {
    case open, pull, track
}

/// What saving a plan or a past trip did (CONTRACT_V4 sections 3.2 and 4.1).
enum SaveOutcome: Equatable {
    case saved(String)
    case already(String)
    case comingSoon
    case full
    case invalid(String)
}

/// What `Store.track` did with a pick.
enum TrackOutcome: Equatable {
    case added(String)
    case already(String)
    case comingSoon
    case full
    case invalid(String)
}

/// A change made on this phone that has not reached the server yet. Kept on disk, sent in order.
struct PendingWrite: Codable, Identifiable {
    enum Op: String, Codable {
        /// PATCH when the document exists (with its version), otherwise PUT to create it.
        case upsert
        case delete
        /// POST: a new document whose id the server picks (a tracked sailing). `docId` is a stand-in on this phone.
        case create
    }

    var id: UUID
    var op: Op
    var coll: String
    var docId: String
    var fields: [String: JSONValue]
    var attempts: Int

    init(op: Op, coll: String, docId: String, fields: [String: JSONValue]) {
        self.id = UUID()
        self.op = op
        self.coll = coll
        self.docId = docId
        self.fields = fields
        self.attempts = 0
    }
}

struct CacheFile: Codable {
    var serverTime: String?
    var savedAt: Date?
    var colls: [String: [String: RawDoc]] = [:]
    // v3
    var level: String?
    var catalog: Catalog?
    var catalogAt: Date?
    // v4: features the server listed but whose calls answered 404/405 (off until the next catalog check).
    var featuresOff: [String]?
}

/// The app's single source of truth: the on-disk cache merged from `/v1/sync`, with queued writes laid on top.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// The most sailings the server keeps tracked.
    static let trackedLimit = 50
    /// v4 caps (CONTRACT_V4 sections 3.2 and 4.1).
    static let plansLimit = 20
    static let tripsLimit = 100
    /// Collections whose documents are created with POST (the server picks the id).
    static let postedColls: Set<String> = ["tracked", "plans", "trips"]

    @Published private(set) var deals: [Deal] = []
    @Published private(set) var feedback: [String: Feedback] = [:]
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var plays: [Play] = []
    @Published private(set) var playNotes: [String: PlayNote] = [:]
    @Published private(set) var status: RunStatus?
    @Published private(set) var profile: [String] = []
    @Published private(set) var watchlist: [WatchItem] = []
    /// Questions to Deal Desk, oldest first (each deal's thread and the general one).
    @Published private(set) var questions: [Question] = []
    /// `prefs/trip`, or nil until it exists on the server (then the brain's own verdicts are used).
    @Published private(set) var trip: TripPrefs?
    /// Price history per deal, fetched when a deal's detail opens.
    @Published private(set) var history: [String: [PricePoint]] = [:]
    @Published private(set) var syncing = false
    @Published private(set) var problem: Problem?
    @Published private(set) var lastSync: Date?
    @Published private(set) var pendingKeys: Set<String> = []
    /// A one-off message, such as a change the server refused.
    @Published var notice: String?
    @Published var pushProblem: String?
    // v3
    /// Jim's tracked sailings: coming up first, sailed ones last.
    @Published private(set) var tracked: [TrackedSailing] = []
    @Published private(set) var level: ServerLevel = .unknown
    /// The server's catalog in v3, else the built-in copy (line names and the Royal fleet).
    @Published private(set) var catalog: Catalog = .builtIn
    /// The last refresh nudge and when it was sent.
    @Published private(set) var nudge: NudgeResult?
    @Published private(set) var nudgedAt: Date?
    @Published private(set) var refreshState: RefreshState?
    // v4
    /// The newest newsletter digest (CONTRACT_V4 section 2).
    @Published private(set) var digest: DigestDoc?
    /// Digest item ids already shown on this phone.
    @Published private(set) var digestSeen: Set<String> = []
    /// Saved searches, newest first.
    @Published private(set) var plans: [Plan] = []
    /// Cruises Jim took, newest first.
    @Published private(set) var trips: [PastTrip] = []
    /// The server's per-port summary of those trips (ratings, visits, how they nudge picks).
    @Published private(set) var ports: PortsSummary?
    @Published private(set) var featuresOff: Set<String> = []
    // v5
    /// `prefs/collect`: the lines Deal Desk collects prices for (CONTRACT_V5 section 1.2).
    @Published private(set) var collectPrefs = CollectPrefs()
    /// `GET /v1/collect`, loaded when My Lines opens.
    @Published fileprivate(set) var collectState: CollectState?
    /// `GET /v1/ships/photos`, loaded once per session when a screen with a ship on it opens.
    @Published fileprivate(set) var shipManifest: ShipPhotoManifest?
    /// The server answered 422 to `kind=visit` (a v5 server from before 1.6): Visits asks for every port instead.
    fileprivate var visitKindRefused = false

    private var dealIndex: [String: Deal] = [:]
    private var cache: CacheFile
    private var queue: [PendingWrite]
    private let isPreview: Bool
    private var rerunRequested = false
    private var rerunReason: RefreshReason?
    private var askedForPush = false
    private var monitor: NWPathMonitor?
    private var isForeground = true
    private var followUp: Task<Void, Never>?

    private static let cacheFile = "cache.json"
    private static let queueFile = "queue.json"
    private static let nudgeKey = "refresh.lastNudge"

    init(previewDocs: [String: [String: RawDoc]]? = nil, level previewLevel: ServerLevel = .v3,
         catalog previewCatalog: Catalog? = nil) {
        if let previewDocs {
            isPreview = true
            cache = CacheFile(serverTime: nil, savedAt: Date(), colls: previewDocs)
            queue = []
            history = Samples.history
        } else {
            isPreview = false
            Connection.bootstrap()
            cache = Disk.load(CacheFile.self, from: Store.cacheFile) ?? CacheFile()
            queue = Disk.load([PendingWrite].self, from: Store.queueFile) ?? []
        }
        lastSync = cache.savedAt
        if isPreview {
            level = previewLevel
            catalog = previewLevel == .v3 ? (previewCatalog ?? Samples.catalog) : .builtIn
        } else {
            level = cache.level.flatMap { ServerLevel(rawValue: $0) } ?? .unknown
            catalog = (level == .v3 ? cache.catalog : nil) ?? .builtIn
            featuresOff = Set(cache.featuresOff ?? [])
            digestSeen = DigestSeen.load()
        }
        CatalogIndex.current = catalog
        rebuild()
        if !isPreview { startMonitor() }
    }

    static func preview() -> Store {
        Store(previewDocs: Samples.docs)
    }

    /// The preview on a v4 server: booking links, the digest, search and plans, past trips and port ratings.
    static func previewV4() -> Store {
        Store(previewDocs: Samples.docsV4, catalog: Samples.catalogV4)
    }

    // MARK: - What the screens read

    /// Deals with no answer yet, newest first.
    var inbox: [Deal] { deals.filter { feedback[$0.id]?.verdict == nil } }
    var unansweredCount: Int { inbox.count }
    var pendingCount: Int { queue.count }
    var cachedDealCount: Int { cache.colls["deals"]?.count ?? 0 }

    /// The deal server has v3: lines, tracking, coverage, the refresh nudge.
    var isV3: Bool { level == .v3 }

    /// A v4 feature is on: the server says apiVersion 4+ and lists it, and its calls have not answered 404/405.
    func has(_ feature: V4Feature) -> Bool {
        isV3 && catalog.has(feature) && !featuresOff.contains(feature.rawValue)
    }

    var v4Features: Set<V4Feature> { Set(V4Feature.allCases.filter { has($0) }) }

    private func turnOff(_ feature: V4Feature) {
        featuresOff.insert(feature.rawValue)
        cache.featuresOff = Array(featuresOff).sorted()
        saveCache()
    }

    func deal(_ id: String) -> Deal? { dealIndex[id] }

    func reviewed(_ verdict: Verdict) -> [Deal] {
        deals
            .filter { feedback[$0.id]?.verdict == verdict }
            .sorted { (feedback[$0.id]?.updated ?? .distantPast) > (feedback[$1.id]?.updated ?? .distantPast) }
    }

    func isPending(_ coll: String, _ id: String) -> Bool {
        pendingKeys.contains("\(coll)/\(id)")
    }

    // MARK: - Buckets (DESIGN_V2 section 2, CONTRACT_V3 section 2)

    /// Does this deal fit My Trip? Worked out live from `prefs/trip`, so the buckets move as soon as it changes.
    func fit(_ deal: Deal) -> TripFit {
        TripCheck.verdict(for: deal, prefs: trip, softBudget: has(.sheet))
    }

    /// The Deals tab: unanswered deals in one bucket, narrowed by the filters and sorted. Best deals keeps the deal
    /// kinds My Trip asks for (none picked = all) above its minimum score (sales exempt); For my trip keeps the
    /// deals that pass My Trip and the minimum score.
    func bucket(_ bucket: DealBucket, filters: DealFilters, sort: DealSort) -> [Deal] {
        let minPct = trip?.minPctUnder ?? 15
        let floor = trip?.minScore
        var list = inbox.filter { filters.matches($0, fits: fit($0).fits, minPctUnder: minPct) }
        switch bucket {
        case .best:
            let kinds = trip?.dealTypes ?? []
            list = list.filter { deal in
                DealType.matches(deal, picked: kinds, fits: fit(deal).fits, minPctUnder: minPct)
                    && ScoreFloor.passes(deal, floor)
            }
        case .trip:
            list = list.filter { fit($0).fits && ScoreFloor.passes($0, floor) }
        }
        let fitAdj: ((Deal) -> Int)? = fitOrdering ? { self.portFit($0)?.adj ?? 0 } : nil
        return DealOrder.sorted(list, by: sort, preferred: { self.fit($0).preferred }, fitAdj: fitAdj,
                                minPctUnder: minPct)
    }

    // MARK: - v4: booking, fit, digest (CONTRACT_V4 sections 1.6, 1.7, 2 and 4.3)

    /// The Book button for a deal: the line's own page (v4), else the deal's own link as before.
    func bookChoice(for deal: Deal) -> BookChoice {
        BookChoice.make(line: deal.line, ship: deal.data.ship, booking: deal.booking, link: deal.data.link,
                        linkLabel: deal.data.linkLabel, sources: deal.data.sources ?? [], pricePP: deal.data.pricePP,
                        alternatives: deal.alternatives, v4: has(.booking), isSale: deal.kind == .sale, catalog: catalog)
    }

    /// The Book button for a tracked sailing (v4 only; a v3 tracked sailing keeps its own buttons).
    func bookChoice(for item: TrackedSailing) -> BookChoice {
        guard has(.booking), item.state != .sailed else { return BookChoice() }
        return BookChoice.make(line: item.line, ship: item.data.ship, booking: item.booking, link: nil, linkLabel: nil,
                               sources: item.data.sources ?? [], pricePP: item.data.pricePP,
                               alternatives: item.alternatives, v4: true, catalog: catalog)
    }

    /// The Book button for a search result.
    func bookChoice(for row: SearchRow) -> BookChoice {
        BookChoice.make(line: row.lineName, ship: row.shipTitle, booking: row.booking, link: nil, linkLabel: nil,
                        sources: row.sources ?? [], pricePP: row.pricePP, alternatives: row.bookAlternatives ?? [],
                        v4: true, catalog: catalog)
    }

    /// A digest item's Book button, only when it names a sailing the server could build a link for.
    func bookChoice(for item: DigestItem) -> BookChoice? {
        guard has(.booking), let booking = item.booking else { return nil }
        return BookChoice.make(line: CruiseLine.resolved(item.line), ship: item.ship, booking: booking, link: nil,
                               linkLabel: nil, sources: [], pricePP: nil, alternatives: [], v4: true, catalog: catalog)
    }

    /// How Jim's own port history nudges a deal (soft: wording and order only, never a filter).
    func portFit(_ deal: Deal) -> PortFit? {
        guard has(.trips), let ports, deal.kind != .sale else { return nil }
        let stops = deal.data.stops ?? deal.data.ports ?? []
        return PortFit.of(stops: stops, embark: deal.data.port, returnPort: deal.returnPort, summary: ports)
    }

    /// Fit takes part in the board's order once there is something to nudge with.
    var fitOrdering: Bool {
        guard has(.trips), let ports else { return false }
        return ports.ports.contains { ($0.adj ?? 0) != 0 }
    }

    var digestItems: [DigestItem] { has(.digest) ? (digest?.items ?? []) : [] }
    var digestNewCount: Int { DigestSeen.newCount(digestItems, seen: digestSeen) }
    func isNew(_ item: DigestItem) -> Bool { !digestSeen.contains(item.id) }

    /// Everything in the digest now counts as seen (when its sheet closes).
    func markDigestSeen() {
        let ids = digestItems.map { $0.id }
        guard !ids.isEmpty, !Set(ids).isSubset(of: digestSeen) else { return }
        digestSeen.formUnion(ids)
        if !isPreview { DigestSeen.save(digestSeen, newest: ids) }
    }

    // MARK: - Questions

    func question(_ id: String) -> Question? { questions.first { $0.id == id } }

    /// One deal's thread, or the general one when `dealId` is nil.
    func thread(_ dealId: String?) -> [Question] {
        questions.filter { $0.data.dealId == dealId }
    }

    /// True while a question asked in the last 10 minutes has no answer yet.
    func awaitingAnswer(_ dealId: String?) -> Bool {
        thread(dealId).contains { !$0.isAnswered && Date().timeIntervalSince($0.asked) < 600 }
    }

    // MARK: - Tracked sailings (CONTRACT_V3 sections 2 and 4)

    func trackedSailing(_ id: String) -> TrackedSailing? { tracked.first { $0.id == id } }

    func trackedMatch(key: String) -> TrackedSailing? { tracked.first { $0.key == key } }

    /// The tracked sailing for a deal's sailing and cabin, if Jim tracks it.
    func trackedMatch(for deal: Deal) -> TrackedSailing? {
        guard deal.kind != .sale, deal.data.cabin != nil else { return nil }
        let key = TrackKey.make(line: deal.line, ship: deal.data.ship, sailDate: deal.data.sailDate,
                                nights: deal.data.nights, cabin: deal.data.cabin)
        return trackedMatch(key: key)
    }

    /// Tracks a sailing. It shows at once with every price "filling…"; the server fills it from its fare data and
    /// Claude adds the rest. Never queued against an older server.
    @discardableResult
    func track(_ pick: TrackPick) -> TrackOutcome {
        guard isV3 else { return .comingSoon }
        if let problem = pick.problem { return .invalid(problem) }
        if let existing = trackedMatch(key: pick.key) { return .already(existing.id) }
        guard tracked.count < Store.trackedLimit else { return .full }
        let id = Store.newId(prefix: "local")
        enqueue(.create, "tracked", id, pick.fields(), reason: .track)
        Haptics.success()
        return .added(id)
    }

    /// Changes the extras on a tracked sailing (the app may change only these). Changing the line, ship, date,
    /// nights or cabin is stop-and-track-again.
    func editTracked(_ item: TrackedSailing, cabinName: String, port: String, link: String, note: String) {
        guard isV3 else { return }
        var fields: [String: JSONValue] = [:]
        func set(_ key: String, _ value: String, _ cap: Int) {
            let text = value.trimmed.capped(cap)
            fields[key] = text.isEmpty ? .null : .string(text)
        }
        set("cabinName", cabinName, 40)
        set("port", port, 30)
        set("note", note, 120)
        fields["link"] = TrackPick.validLink(link).map { JSONValue.string($0) } ?? .null
        if let index = queue.firstIndex(where: { $0.op == .create && $0.coll == "tracked" && $0.docId == item.id }) {
            // Not on the server yet: change the pick that will be sent.
            for (key, value) in fields {
                if value == .null {
                    queue[index].fields.removeValue(forKey: key)
                } else {
                    queue[index].fields[key] = value
                }
            }
            saveQueue()
            rebuild()
        } else {
            enqueue(.upsert, "tracked", item.id, fields)
        }
        Haptics.success()
    }

    func stopTracking(_ item: TrackedSailing) {
        guard isV3 else { return }
        // While a sync is sending the head of the queue, that write is already on its way.
        let sending = syncing ? queue.first?.id : nil
        queue.removeAll { $0.coll == "tracked" && $0.docId == item.id && $0.id != sending }
        if item.isLocal && queue.contains(where: { $0.coll == "tracked" && $0.docId == item.id }) {
            // Its create is on its way right now; delete the server's copy once it lands.
            stopAfterCreate.insert(item.id)
        }
        if !item.isLocal {
            queue.append(PendingWrite(op: .delete, coll: "tracked", docId: item.id, fields: [:]))
        }
        saveQueue()
        rebuild()
        kick()
        Haptics.tap()
    }

    /// Stand-in ids whose create was already being sent when Jim stopped tracking them.
    private var stopAfterCreate: Set<String> = []

    /// Sailings the fare data knows for a ship, soonest first, for the Track builder's browse-and-pick.
    func knownSailings(line: String, ship: String) async -> [FareSailing] {
        let key = Slug.ship(ship)
        guard !key.isEmpty else { return [] }
        let list: [FareSailing]
        if isPreview {
            list = Samples.sailings
        } else {
            guard let client = Connection.client() else { return [] }
            list = (try? await client.sailings(ship: key, line: line)) ?? []
        }
        // An older server ignores `line`; keep only this line's rows for this exact ship, still to come.
        return list.filter { sailing in
            guard CruiseLine.same(CruiseLine.resolved(sailing.line), line) else { return false }
            let ships = [sailing.ship, sailing.shipName].compactMap { $0 }.map { Slug.ship($0) }
            guard ships.isEmpty || ships.contains(key) else { return false }
            guard let day = sailing.sailDay else { return false }
            return Fmt.daysLeft(day) >= 0
        }
        .sorted { ($0.sailDate ?? "") < ($1.sailDate ?? "") }
    }

    // MARK: - v4: search, link reading, prefill

    /// `GET /v1/search`. A 404 or 405 means this server has no search after all: the feature turns off.
    func search(_ query: SearchQuery, offset: Int = 0) async throws -> SearchResult {
        if isPreview { return Samples.previewSearch(query, catalog: catalog) }
        guard let client = Connection.client() else { throw APIError.notConfigured }
        // `calls` is a v5 parameter; an older server never gets it.
        var query = query
        if !has(.catalog5) { query.calls = [] }
        do {
            return try await client.search(query, offset: offset)
        } catch APIError.notFound {
            turnOff(.search)
            throw APIError.unsupported
        } catch APIError.unsupported {
            turnOff(.search)
            throw APIError.unsupported
        }
    }

    /// The deal server's reading of a cruise line's own link (from its text; nothing is fetched).
    func parseLink(_ url: String) async -> LinkParse? {
        guard has(.booking), !isPreview, let client = Connection.client() else { return nil }
        return try? await client.parseLink(url)
    }

    /// What Deal Desk already knows about a past sailing: its ports and nights, for Jim to confirm.
    func prefill(line: String, ship: String, sailDate: Date) async -> TripPrefill? {
        guard has(.trips), !ship.trimmed.isEmpty else { return nil }
        if isPreview { return Samples.prefill }
        guard let client = Connection.client() else { return nil }
        return try? await client.prefill(line: line, ship: ship.trimmed, sailDate: Fmt.isoDay(sailDate))
    }

    // MARK: - v4: plans (CONTRACT_V4 section 3.2)

    func plan(_ id: String) -> Plan? { plans.first { $0.id == id } }

    /// Saves a new plan (POST) or changes one (PATCH). Shows at once; queued offline like a tracked sailing.
    @discardableResult
    func savePlan(_ draft: PlanDraft, editing: Plan? = nil) -> SaveOutcome {
        guard has(.plans) else { return .comingSoon }
        if let problem = draft.problem { return .invalid(problem) }
        if let clash = plans.first(where: { $0.id != editing?.id && $0.name.lowercased() == draft.key }) {
            return editing == nil ? .already(clash.id) : .invalid("Another plan is called that.")
        }
        if let editing {
            if !replaceQueuedCreate("plans", editing.id, with: draft.fields(isNew: true)) {
                enqueue(.upsert, "plans", editing.id, draft.fields(isNew: false))
            }
            Haptics.success()
            return .saved(editing.id)
        }
        guard plans.count < Store.plansLimit else { return .full }
        let id = Store.newId(prefix: "local")
        enqueue(.create, "plans", id, draft.fields(isNew: true))
        Haptics.success()
        return .saved(id)
    }

    func deletePlan(_ plan: Plan) {
        guard has(.plans) else { return }
        removePosted("plans", plan.id, isLocal: plan.isLocal)
    }

    /// Promote to my trip: My Trip takes the plan's lines, sizes, dates, months, nights, cabin and deal kinds;
    /// ships, ports, regions and the budget per person are not copied.
    func promote(_ plan: Plan) {
        guard has(.plans) else { return }
        saveTrip(PlanPromotion.apply(plan, to: trip ?? TripPrefs()))
        let stamp = JSONValue.string(Fmt.stamp())
        if !replaceQueuedField("plans", plan.id, ["promotedAt": stamp]) {
            enqueue(.upsert, "plans", plan.id, ["promotedAt": stamp, "updatedAt": stamp])
        }
    }

    // MARK: - v4: my past trips (CONTRACT_V4 section 4)

    func pastTrip(_ id: String) -> PastTrip? { trips.first { $0.id == id } }

    private func tripKey(_ trip: PastTrip) -> String {
        [CruiseLine.slug(trip.line), Slug.ship(trip.data.ship ?? ""), String((trip.data.sailDate ?? "").prefix(10))]
            .joined(separator: "|")
    }

    /// Logs a cruise Jim took (POST), or changes one (PATCH). The server works out the port summary from it.
    @discardableResult
    func logTrip(_ draft: TripDraft, editing: PastTrip? = nil) -> SaveOutcome {
        guard has(.trips) else { return .comingSoon }
        if let problem = draft.problem { return .invalid(problem) }
        if let clash = trips.first(where: { $0.id != editing?.id && tripKey($0) == draft.key }) {
            return editing == nil ? .already(clash.id) : .invalid("That sailing is already logged.")
        }
        if let editing {
            if !replaceQueuedCreate("trips", editing.id, with: draft.fields(isNew: true, sendExtras: has(.reference))) {
                enqueue(.upsert, "trips", editing.id, draft.fields(isNew: false, sendExtras: has(.reference)))
            }
            Haptics.success()
            return .saved(editing.id)
        }
        guard trips.count < Store.tripsLimit else { return .full }
        let id = Store.newId(prefix: "local")
        enqueue(.create, "trips", id, draft.fields(isNew: true, sendExtras: has(.reference)))
        Haptics.success()
        return .saved(id)
    }

    func deleteTrip(_ trip: PastTrip) {
        guard has(.trips) else { return }
        removePosted("trips", trip.id, isLocal: trip.isLocal)
    }

    // MARK: - v4: settings that live on the trip settings

    /// Book on the line (default) or best value. Only changes that one field on the trip settings that exist.
    @discardableResult
    func setBookingPreference(_ preference: BookingPreference) -> Bool {
        guard has(.booking) else { return false }
        return patchTrip(["bookingPreference": .string(preference.rawValue)])
    }

    /// How recent visits and ratings nudge picks (CONTRACT_V4 section 4.2).
    @discardableResult
    func savePortKnobs(recencyMonths: Int, fadeMonths: Int, useRatings: Bool) -> Bool {
        guard has(.trips) else { return false }
        let months = min(max(recencyMonths, 0), 24)
        let fade = min(max(fadeMonths, 1, months), 36)
        return patchTrip(["portRecencyMonths": .int(months), "portRecencyFadeMonths": .int(fade),
                          "usePortRatings": .bool(useRatings)])
    }

    /// v5 settings use the same path: a few fields on the trip settings that already exist.
    fileprivate func patchTripFields(_ fields: [String: JSONValue]) -> Bool { patchTrip(fields) }

    /// Changes a few fields on the trip settings that already exist (never creates them).
    private func patchTrip(_ fields: [String: JSONValue]) -> Bool {
        var f = fields
        f["updatedAt"] = .string(Fmt.stamp())
        if let index = queue.lastIndex(where: { $0.op == .upsert && $0.coll == "prefs" && $0.docId == "trip" }) {
            for (key, value) in f { queue[index].fields[key] = value }
            saveQueue()
            rebuild()
            kick()
        } else if cache.colls["prefs"]?["trip"] != nil {
            enqueue(.upsert, "prefs", "trip", f)
        } else {
            return false
        }
        Haptics.tap()
        return true
    }

    // MARK: - POSTed documents (tracked, plans, trips)

    /// A doc not on the server yet: change the create that will be sent instead of queueing a PATCH.
    private func replaceQueuedCreate(_ coll: String, _ id: String, with fields: [String: JSONValue]) -> Bool {
        let sending = syncing ? queue.first?.id : nil
        guard let index = queue.firstIndex(where: { $0.op == .create && $0.coll == coll && $0.docId == id && $0.id != sending })
        else { return false }
        var next = fields
        for key in ["createdAt", "addedAt", "addedVia"] {
            if let kept = queue[index].fields[key] { next[key] = kept }
        }
        queue[index].fields = next
        saveQueue()
        rebuild()
        kick()
        return true
    }

    private func replaceQueuedField(_ coll: String, _ id: String, _ fields: [String: JSONValue]) -> Bool {
        let sending = syncing ? queue.first?.id : nil
        guard let index = queue.firstIndex(where: { $0.op == .create && $0.coll == coll && $0.docId == id && $0.id != sending })
        else { return false }
        for (key, value) in fields { queue[index].fields[key] = value }
        saveQueue()
        rebuild()
        return true
    }

    private func removePosted(_ coll: String, _ id: String, isLocal: Bool) {
        // While a sync is sending the head of the queue, that write is already on its way.
        let sending = syncing ? queue.first?.id : nil
        queue.removeAll { $0.coll == coll && $0.docId == id && $0.id != sending }
        if isLocal && queue.contains(where: { $0.coll == coll && $0.docId == id }) {
            // Its create is on its way right now; delete the server's copy once it lands.
            stopAfterCreate.insert(id)
        }
        if !isLocal {
            queue.append(PendingWrite(op: .delete, coll: coll, docId: id, fields: [:]))
        }
        saveQueue()
        rebuild()
        kick()
        Haptics.tap()
    }

    // MARK: - Sync

    func kick(reason: RefreshReason? = nil) {
        Task { await refresh(reason: reason) }
    }

    func foregrounded() {
        isForeground = true
        if let lastSync, Date().timeIntervalSince(lastSync) < 30, queue.isEmpty, problem == nil { return }
        kick(reason: .open)
    }

    func backgrounded() {
        isForeground = false
        followUp?.cancel()
        followUp = nil
    }

    /// Sends queued writes, pulls everything that changed since the last sync, checks what the server can do
    /// (`GET /v1/catalog`, at most every 6 hours and on every pull), then on a v3 server asks for a light refresh
    /// of the sources that allow it (CONTRACT_V3 section 5).
    func refresh(reason: RefreshReason? = nil) async {
        if isPreview { return }
        if syncing {
            rerunRequested = true
            if let reason { rerunReason = reason }
            return
        }
        guard let client = Connection.client() else {
            problem = .notConfigured
            return
        }
        syncing = true
        await flush(client)
        do {
            try await pull(client)
            problem = nil
            lastSync = Date()
            await checkCatalog(client, force: reason == .pull)
            if let reason { await sendNudge(client, reason) }
            if !askedForPush {
                askedForPush = true
                await Push.requestIfNeeded()
            }
        } catch {
            problem = Problem(error)
        }
        syncing = false
        if rerunRequested {
            rerunRequested = false
            let next = rerunReason
            rerunReason = nil
            if !queue.isEmpty || next != nil { await refresh(reason: next) }
        }
    }

    private func pull(_ client: APIClient) async throws {
        let since = cache.serverTime
        let result = try await client.sync(since: since)
        var colls: [String: [String: RawDoc]] = since == nil ? [:] : cache.colls
        for (coll, docs) in result.docs {
            var bucket = colls[coll] ?? [:]
            for doc in docs { bucket[doc.id] = doc }
            colls[coll] = bucket
        }
        for gone in result.deleted ?? [] {
            colls[gone.coll]?[gone.id] = nil
        }
        cache.colls = colls
        cache.serverTime = result.serverTime
        cache.savedAt = Date()
        saveCache()
        rebuild()
    }

    /// v3 mode is on only when `GET /v1/catalog` answers with apiVersion 3 or more; a 404 or 405 means an older
    /// server. A network blip changes nothing.
    private func checkCatalog(_ client: APIClient, force: Bool) async {
        if !force, level != .unknown, let at = cache.catalogAt, Date().timeIntervalSince(at) < 6 * 3600 { return }
        do {
            let fresh = try await client.catalog()
            cache.catalogAt = Date()
            cache.catalog = fresh.isV3 ? fresh : nil
            // A fresh catalog gives every listed feature another try.
            cache.featuresOff = nil
            featuresOff = []
            setLevel(fresh.isV3 ? .v3 : .v2)
        } catch APIError.notFound {
            cache.catalogAt = Date()
            cache.catalog = nil
            setLevel(.v2)
        } catch APIError.unsupported {
            cache.catalogAt = Date()
            cache.catalog = nil
            setLevel(.v2)
        } catch {
            return
        }
        saveCache()
    }

    private func setLevel(_ new: ServerLevel) {
        level = new
        cache.level = new.rawValue
        catalog = (new == .v3 ? cache.catalog : nil) ?? .builtIn
        CatalogIndex.current = catalog
        rebuild()
    }

    private var lastNudgeAt: Date? {
        get {
            let value = UserDefaults.standard.double(forKey: Store.nudgeKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Store.nudgeKey) }
    }

    /// `POST /v1/refresh` on a v3 server: on open at most every 5 minutes; a pull or a new tracked sailing always
    /// asks (the server itself takes one nudge per 5 minutes). If it was accepted, sync again 90 s later while the
    /// app is still open.
    private func sendNudge(_ client: APIClient, _ reason: RefreshReason) async {
        guard level == .v3 else { return }
        if reason == .open, let last = lastNudgeAt, Date().timeIntervalSince(last) < 300 { return }
        do {
            let result = try await client.nudge(reason: reason.rawValue)
            lastNudgeAt = Date()
            nudge = result
            nudgedAt = Date()
            if result.accepted == true { scheduleFollowUp() }
        } catch APIError.notFound {
            setLevel(.v2)
            saveCache()
        } catch APIError.unsupported {
            setLevel(.v2)
            saveCache()
        } catch {
            // A refresh nudge is a nicety; the sync already happened.
        }
    }

    private func scheduleFollowUp() {
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard let self, !Task.isCancelled, self.isForeground else { return }
            await self.refresh()
        }
    }

    /// For the status sheet: where the last refresh stands on the server.
    func loadRefreshState() async {
        guard !isPreview, isV3, let client = Connection.client() else { return }
        if let state = try? await client.refreshState() { refreshState = state }
    }

    // MARK: - Writes

    private enum Outcome {
        case sent
        /// Offline or not allowed: keep everything queued and stop for now.
        case stop(Problem)
        /// Might work later.
        case failed(String)
        /// Can never work (the server refused the content).
        case dropped(String)
    }

    private func flush(_ client: APIClient) async {
        while let write = queue.first {
            let outcome = await send(write, client, retry: true)
            switch outcome {
            case .sent:
                removeHead(write.id)
            case .stop(let reason):
                problem = reason
                saveQueue()
                rebuild()
                return
            case .failed(let message):
                if write.attempts >= 2 {
                    removeHead(write.id)
                    notice = "A change couldn't be saved and was dropped: \(message)"
                } else {
                    if queue.first?.id == write.id { queue[0].attempts += 1 }
                    saveQueue()
                    rebuild()
                    return
                }
            case .dropped(let message):
                removeHead(write.id)
                notice = message
            }
            saveQueue()
        }
        rebuild()
    }

    private func removeHead(_ id: UUID) {
        if queue.first?.id == id { queue.removeFirst() }
    }

    /// One write. On 409 (or 404) it re-syncs and tries once more with the fresh version.
    private func send(_ write: PendingWrite, _ client: APIClient, retry: Bool) async -> Outcome {
        let current = cache.colls[write.coll]?[write.docId]
        let isPosted = Store.postedColls.contains(write.coll)
        do {
            switch write.op {
            case .create:
                let data = write.fields.compactMapValues { value -> JSONValue? in value == .null ? nil : value }
                if let saved = try await client.create(write.coll, data: data) {
                    cache.colls[write.coll, default: [:]][saved.id] = saved
                    saveCache()
                    if stopAfterCreate.remove(write.docId) != nil {
                        queue.append(PendingWrite(op: .delete, coll: write.coll, docId: saved.id, fields: [:]))
                    }
                }
            case .upsert:
                let saved: RawDoc?
                if let current {
                    saved = try await client.patch(write.coll, write.docId, fields: write.fields,
                                                   ifVersion: current.version)
                } else if isPosted {
                    // Gone from the server: there is nothing to change (these are never made by PUT).
                    return .sent
                } else {
                    let data = write.fields.compactMapValues { value -> JSONValue? in value == .null ? nil : value }
                    saved = try await client.put(write.coll, write.docId, data: data, ifVersion: nil)
                }
                if let saved, saved.id == write.docId {
                    cache.colls[write.coll, default: [:]][saved.id] = saved
                    saveCache()
                }
            case .delete:
                guard let current else { return .sent }
                try await client.delete(write.coll, write.docId, ifVersion: current.version)
                cache.colls[write.coll]?[write.docId] = nil
                saveCache()
            }
            return .sent
        } catch let error as APIError {
            if isPosted, let outcome = postedFailure(write, error) { return outcome }
            switch error {
            case .conflict, .notFound:
                if write.op == .delete, case .notFound = error { return .sent }
                guard retry else { return .failed("it changed on the server at the same time.") }
                do {
                    try await pull(client)
                } catch {
                    return .stop(Problem(error))
                }
                return await send(write, client, retry: false)
            case .offline(let why):
                return .stop(.offline(why))
            case .unauthorized:
                return .stop(.unauthorized)
            case .notConfigured:
                return .stop(.notConfigured)
            case .rejected(let why):
                return .dropped("The server refused a change: \(why)")
            case .server(let why):
                return .failed(why)
            case .unsupported:
                return .dropped("The deal server doesn't support that change yet.")
            }
        } catch {
            return .stop(.offline(error.localizedDescription))
        }
    }

    /// CONTRACT_V3 section 8 and CONTRACT_V4 section 9: a tracked, plan or trip write never waits on a server
    /// without it. A 404 on create, or a 405 on any of them, drops it and turns that part off (tracking: back to v2
    /// behaviour); a 409 on create means it is already there, which counts as done.
    private func postedFailure(_ write: PendingWrite, _ error: APIError) -> Outcome? {
        switch (write.op, error) {
        case (.create, .conflict):
            return .sent
        case (.create, .notFound), (_, .unsupported):
            switch write.coll {
            case "plans":
                turnOff(.plans)
                return .dropped("Plans aren't on the deal server yet, so that change wasn't saved.")
            case "trips":
                turnOff(.trips)
                return .dropped("My trips isn't on the deal server yet, so that change wasn't saved.")
            default:
                setLevel(.v2)
                saveCache()
                return .dropped("Tracking isn't on the deal server yet, so that change wasn't saved.")
            }
        default:
            return nil
        }
    }

    private func enqueue(_ op: PendingWrite.Op, _ coll: String, _ id: String, _ fields: [String: JSONValue] = [:],
                         reason: RefreshReason? = nil) {
        queue.append(PendingWrite(op: op, coll: coll, docId: id, fields: fields))
        saveQueue()
        rebuild()
        kick(reason: reason)
    }

    /// Records Jim's answer. Claude's fields belong to the brain (the server refuses them from the app); a changed
    /// answer is newer than `claudeReadAt`, so the old reply is hidden until Claude reads the new one.
    func answer(_ deal: Deal, verdict: Verdict, reasons: [String], note: String) {
        enqueue(.upsert, "feedback", deal.id, [
            "dealId": .string(deal.id),
            "verdict": .string(verdict.rawValue),
            "reasons": .array(reasons.map { JSONValue.string($0) }),
            "note": .string(note.capped(500)),
            "updatedAt": .string(Fmt.stamp()),
        ])
        Haptics.success()
    }

    func addRule(text: String, unless: String, fromDeal: String? = nil) {
        var fields: [String: JSONValue] = [
            "text": .string(text.capped(120)),
            "status": .string(RuleStatus.active.rawValue),
            "origin": .string("jim"),
            "createdAt": .string(Fmt.stamp()),
        ]
        if !unless.isEmpty { fields["unless"] = .string(unless.capped(120)) }
        if let fromDeal { fields["fromDeal"] = .string(fromDeal) }
        enqueue(.upsert, "rules", Store.newId(prefix: "jim"), fields)
        Haptics.success()
    }

    func setRule(_ rule: Rule, status: RuleStatus) {
        enqueue(.upsert, "rules", rule.id, ["status": .string(status.rawValue), "updatedAt": .string(Fmt.stamp())])
        Haptics.tap()
    }

    func deleteRule(_ rule: Rule) {
        enqueue(.delete, "rules", rule.id)
        Haptics.tap()
    }

    /// Saves My Trip. The buckets re-sort at once from the queued change; the brain reads it on its next run. The
    /// v3 fields go only to a v3 server.
    func saveTrip(_ prefs: TripPrefs) {
        enqueue(.upsert, "prefs", "trip", prefs.cleaned().fields(v3: isV3, v4: v4Features))
        Haptics.success()
    }

    /// My Lines on its own (from Settings): changes only `lines` on the trip settings that already exist.
    func saveLines(_ lines: [String]) {
        guard isV3, var prefs = trip else { return }
        prefs.lines = lines
        let clean = prefs.cleaned().effectiveLines
        let value = JSONValue.array(clean.map { JSONValue.string($0) })
        let stamp = JSONValue.string(Fmt.stamp())
        if let index = queue.lastIndex(where: { $0.op == .upsert && $0.coll == "prefs" && $0.docId == "trip" }) {
            queue[index].fields["lines"] = value
            queue[index].fields["updatedAt"] = stamp
            saveQueue()
            rebuild()
            kick()
        } else if cache.colls["prefs"]?["trip"] != nil {
            enqueue(.upsert, "prefs", "trip", ["lines": value, "updatedAt": stamp])
        }
        Haptics.tap()
    }

    /// Asks Deal Desk about a deal (or in general). The answerer on the server replies within a minute or two
    /// and the phone gets an "Answer ready" push.
    @discardableResult
    func ask(_ text: String, dealId: String?) -> String? {
        let body = text.trimmed.capped(500)
        guard !body.isEmpty else { return nil }
        let id = Store.newId(prefix: "q")
        var fields: [String: JSONValue] = ["text": .string(body), "askedAt": .string(Fmt.stamp())]
        if let dealId { fields["dealId"] = .string(dealId) }
        enqueue(.upsert, "questions", id, fields)
        Haptics.success()
        return id
    }

    /// Fetches a deal's price history for the sparkline (kept for this session).
    func loadHistory(_ dealId: String) async {
        if isPreview || !Router.isValidId(dealId) { return }
        guard let client = Connection.client() else { return }
        if let points = try? await client.history(dealId: dealId) {
            history[dealId] = points
        }
    }

    func savePlayNote(playId: String, status: PlayNoteStatus, note: String) {
        enqueue(.upsert, "playnotes", playId, [
            "status": .string(status.rawValue),
            "note": .string(note.capped(500)),
            "updatedAt": .string(Fmt.stamp()),
        ])
        Haptics.success()
    }

    static func newId(prefix: String) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let tail = String((0..<10).map { _ in letters[Int.random(in: 0..<letters.count)] })
        return "\(prefix)-\(tail)"
    }

    // MARK: - Push

    func registerDevice(token: String) {
        let defaults = UserDefaults.standard
        let lastToken = defaults.string(forKey: "push.lastToken")
        let lastAt = defaults.double(forKey: "push.lastAt")
        if lastToken == token, Date().timeIntervalSince1970 - lastAt < 7 * 86400 { return }
        guard let client = Connection.client() else { return }
        Task {
            do {
                try await client.registerDevice(token: token, environment: Push.environment)
                defaults.set(token, forKey: "push.lastToken")
                defaults.set(Date().timeIntervalSince1970, forKey: "push.lastAt")
                pushProblem = nil
            } catch {
                pushProblem = "This phone couldn't register for alerts yet; it will try again."
            }
        }
    }

    // MARK: - Settings

    /// Tests the address and token without changing anything.
    func testConnection() async -> String {
        guard let client = Connection.client() else { return Problem.notConfigured.detail }
        do {
            try await client.check()
            return "Connected."
        } catch {
            let problem = Problem(error)
            return "\(problem.title): \(problem.detail)"
        }
    }

    /// After the address or token changes: forget the old server's data and load everything again.
    func connectionChanged() {
        cache = CacheFile()
        saveCache()
        UserDefaults.standard.removeObject(forKey: "push.lastToken")
        UserDefaults.standard.removeObject(forKey: Store.nudgeKey)
        askedForPush = false
        problem = nil
        level = .unknown
        featuresOff = []
        catalog = .builtIn
        CatalogIndex.current = catalog
        rebuild()
        kick(reason: .open)
    }

    func reloadEverything() {
        cache.serverTime = nil
        cache.catalogAt = nil
        kick(reason: .pull)
    }

    // MARK: - Internals

    private func startMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                Store.shared.networkAvailable()
            }
        }
        monitor.start(queue: DispatchQueue(label: "dealdesk.network"))
        self.monitor = monitor
    }

    private func networkAvailable() {
        guard !syncing else { return }
        if !queue.isEmpty || problem != nil { kick() }
    }

    private func saveCache() {
        guard !isPreview else { return }
        Disk.save(cache, to: Store.cacheFile)
    }

    private func saveQueue() {
        guard !isPreview else { return }
        Disk.save(queue, to: Store.queueFile)
    }

    /// Cache plus queued writes, as the screens should see them.
    private func effectiveDocs() -> [String: [String: RawDoc]] {
        var colls = cache.colls
        for write in queue {
            switch write.op {
            case .upsert:
                if var doc = colls[write.coll]?[write.docId] {
                    doc.data = doc.data.merging(write.fields)
                    colls[write.coll]?[write.docId] = doc
                } else {
                    let fresh = RawDoc(id: write.docId, data: JSONValue.object([:]).merging(write.fields),
                                       version: 0, updatedAt: nil)
                    colls[write.coll, default: [:]][write.docId] = fresh
                }
            case .create:
                let fresh = RawDoc(id: write.docId, data: JSONValue.object([:]).merging(write.fields),
                                   version: 0, updatedAt: nil)
                colls[write.coll, default: [:]][write.docId] = fresh
            case .delete:
                colls[write.coll]?[write.docId] = nil
            }
        }
        return colls
    }

    private func rebuild() {
        let colls = effectiveDocs()

        let dealList = (colls["deals"] ?? [:]).values
            .compactMap { Deal(raw: $0) }
            .sorted { $0.latest > $1.latest }
        deals = dealList
        dealIndex = Dictionary(dealList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let answers = (colls["feedback"] ?? [:]).values.compactMap { Feedback(raw: $0) }
        feedback = Dictionary(answers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        rules = (colls["rules"] ?? [:]).values
            .compactMap { Rule(raw: $0) }
            .sorted { $0.created > $1.created }

        plays = (colls["plays"] ?? [:]).values
            .compactMap { Play(raw: $0) }
            .sorted { $0.added > $1.added }

        let notes = (colls["playnotes"] ?? [:]).values.compactMap { PlayNote(raw: $0) }
        playNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let meta = colls["meta"] ?? [:]
        status = meta["status"].flatMap { RunStatus(raw: $0) }
        profile = meta["profile"]?.data.decode(MetaData.self)?.lines ?? []

        watchlist = (colls["watchlist"] ?? [:]).values
            .compactMap { WatchItem(raw: $0) }
            .sorted { ($0.sailDay ?? .distantFuture) < ($1.sailDay ?? .distantFuture) }

        questions = (colls["questions"] ?? [:]).values
            .compactMap { Question(raw: $0) }
            .sorted { ($0.asked, $0.id) < ($1.asked, $1.id) }

        trip = colls["prefs"]?["trip"].flatMap { $0.data.decode(TripPrefs.self) }
        collectPrefs = colls["prefs"]?["collect"].flatMap { CollectPrefs(raw: $0) } ?? CollectPrefs()
        PartyText.current = trip.map { (adults: $0.adults, children: $0.children) }

        let localIds = Set(queue.filter { $0.op == .create }.map { $0.docId })
        tracked = (colls["tracked"] ?? [:]).values
            .compactMap { TrackedSailing(raw: $0, isLocal: localIds.contains($0.id)) }
            .sorted(by: TrackedSailing.order)

        // v4
        digest = DigestDoc.latest((colls["digest"] ?? [:]).values.compactMap { DigestDoc(raw: $0) })
        plans = (colls["plans"] ?? [:]).values
            .compactMap { Plan(raw: $0, isLocal: localIds.contains($0.id)) }
            .sorted(by: Plan.order)
        trips = (colls["trips"] ?? [:]).values
            .compactMap { PastTrip(raw: $0, isLocal: localIds.contains($0.id)) }
            .sorted(by: PastTrip.order)
        ports = colls["ports"]?["summary"].flatMap { PortsSummary(raw: $0) }

        pendingKeys = Set(queue.map { "\($0.coll)/\($0.docId)" })
        updateBadge()
    }

    private func updateBadge() {
        guard !isPreview else { return }
        let count = unansweredCount
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}


// MARK: - v5 (CONTRACT_V5): pickers, collection, the sheet, reference data, ship photos

extension Store {
    /// A v5 part is on: the server says apiVersion 5+ and lists it, and its calls have not answered 404/405.
    func has(_ feature: V5Feature) -> Bool {
        isV3 && catalog.has(feature) && !featuresOff.contains(feature.rawValue)
    }

    private func turnOff(_ feature: V5Feature) {
        featuresOff.insert(feature.rawValue)
        cache.featuresOff = Array(featuresOff).sorted()
        saveCache()
    }

    /// The For-my-trip line filter is the never-saved default (Royal Caribbean only), so the screens say so.
    var showsDefaultLinesBanner: Bool {
        guard has(.catalog5) || has(.collect) else { return false }
        if let state = collectState?.linesState ?? catalog.linesState, !state.isLegacyDefault { return false }
        return trip?.lines == nil
    }

    /// The region tree from the catalog (empty before v5).
    var regionTree: [RegionNode] {
        has(.catalog5) ? catalog.regionTree : []
    }

    // MARK: Collection

    /// `GET /v1/collect`: what Deal Desk collects for each line, and why.
    func loadCollect() async {
        guard has(.collect) else { return }
        if isPreview {
            collectState = Samples.collectState
            return
        }
        guard let client = Connection.client() else { return }
        do {
            collectState = try await client.collect()
        } catch APIError.notFound {
            turnOff(.collect)
        } catch APIError.unsupported {
            turnOff(.collect)
        } catch {
            return
        }
    }

    /// Saves `prefs/collect` (Collect prices for) the moment it changes.
    func saveCollect(_ prefs: CollectPrefs) {
        guard has(.collect) else { return }
        let fields = prefs.fields()
        if let index = queue.lastIndex(where: { $0.op == .upsert && $0.coll == "prefs" && $0.docId == "collect" }) {
            for (key, value) in fields { queue[index].fields[key] = value }
            saveQueue()
            rebuild()
            kick()
        } else {
            enqueue(.upsert, "prefs", "collect", fields)
        }
        Haptics.tap()
    }

    /// "Start collecting Disney": adds the line to Collect prices for.
    @discardableResult
    func startCollecting(_ line: String) -> Bool {
        guard has(.collect), !line.trimmed.isEmpty else { return false }
        var prefs = collectPrefs
        guard !prefs.has(line) else { return true }
        guard prefs.lines.count < 12 else { return false }
        prefs.lines.append(CruiseLine.resolved(line))
        saveCollect(prefs)
        Task { await loadCollect() }
        return true
    }

    // MARK: Catalog pickers

    /// `GET /v1/catalog/ports`: search-as-you-type over the catalog's ports. `visit` (ports of call and scenic
    /// cruising) is newer than the first v5 servers: one that refuses it is asked for every port instead, and the
    /// ports that are only ever embark ports are dropped here.
    func catalogPorts(matching text: String, kind: PortKind, region: String? = nil, limit: Int = 50) async -> [CatalogPort] {
        if isPreview { return Samples.ports(matching: text, kind: kind) }
        guard let client = Connection.client() else { return [] }
        guard has(.catalog5) else {
            return (try? await client.catalogPorts(q: text, kind: nil, region: region, limit: limit)) ?? []
        }
        if kind == .visit && !visitKindRefused {
            do {
                return try await client.catalogPorts(q: text, kind: .visit, region: region, limit: limit)
            } catch APIError.rejected {
                visitKindRefused = true
            } catch {
                return []
            }
        }
        if kind == .visit {
            let all = (try? await client.catalogPorts(q: text, kind: .any, region: region, limit: 50)) ?? []
            return all.filter { PortKind.visit.admits($0.kind) || $0.kind == nil }
        }
        return (try? await client.catalogPorts(q: text, kind: kind, region: region, limit: limit)) ?? []
    }

    // MARK: The sheet

    /// `GET /v1/sheet`: the trip cost and verdict for any sailing Deal Desk has seen.
    func sheet(sailingId: String, cabin: String?) async -> DealSheet? {
        guard has(.sheet), !sailingId.isEmpty else { return nil }
        if isPreview { return has(.flights) ? Samples.sheetFly : Samples.sheet }
        guard let client = Connection.client() else { return nil }
        do {
            return try await client.sheet(sailingId: sailingId, cabin: cabin)
        } catch APIError.unsupported {
            turnOff(.sheet)
            return nil
        } catch {
            return nil
        }
    }

    /// Settings > Trip cost: what we usually buy, ports we drive to, the hotel night, what the budget counts.
    @discardableResult
    func saveTripCost(buyKinds: [String], groundPorts: [String], hotelNightBefore: Bool, budgetBasis: String) -> Bool {
        guard has(.sheet) else { return false }
        let kinds = buyKinds.filter { AddonKind.all.contains($0) }
        var ports: [String] = []
        for port in groundPorts {
            let clean = port.trimmed.capped(40)
            if !clean.isEmpty, !ports.contains(clean) { ports.append(clean) }
        }
        return patchTripFields([
            "buyKinds": .array(Array(kinds.prefix(10)).map { JSONValue.string($0) }),
            "groundPorts": .array(Array(ports.prefix(10)).map { JSONValue.string($0) }),
            "hotelNightBefore": .bool(hotelNightBefore),
            "budgetBasis": .string(budgetBasis == "trip" ? "trip" : "cabin"),
        ])
    }

    // MARK: Reference

    /// `GET /v1/reference/addons?line=`: what to buy on a line.
    func addonsGuide(line: String) async -> AddonsGuide? {
        guard has(.reference) else { return nil }
        if isPreview { return Samples.addonsGuide }
        guard let client = Connection.client() else { return nil }
        do {
            return try await client.addonsGuide(line: line)
        } catch APIError.unsupported {
            turnOff(.reference)
            return nil
        } catch {
            return nil
        }
    }

    // MARK: Ship photos

    /// `GET /v1/ships/photos`: the side-on photos the deal server holds (empty when it has none).
    func shipPhotos() async -> ShipPhotoManifest {
        if let manifest = shipManifest { return manifest }
        if isPreview {
            shipManifest = Samples.shipPhotos
            return Samples.shipPhotos
        }
        guard catalog.isV5, let client = Connection.client() else { return ShipPhotoManifest() }
        do {
            let manifest = try await client.shipPhotos()
            shipManifest = manifest
            return manifest
        } catch APIError.notFound {
            shipManifest = ShipPhotoManifest()
            return ShipPhotoManifest()
        } catch {
            return ShipPhotoManifest()
        }
    }

    /// Loads the photo manifest once, so the to-scale strips can show without a wait of their own.
    func loadShipPhotos() async {
        guard shipManifest == nil else { return }
        _ = await shipPhotos()
    }

    /// The bytes of one photo (the app token goes with the request).
    func shipPhotoData(_ photo: ShipPhoto) async -> Data? {
        guard !isPreview, let path = photo.path, let client = Connection.client() else { return nil }
        return try? await client.raw(path)
    }

    /// The ship Jim sailed most recently (from My trips): the yardstick on the ship-size screens.
    var yardstick: ShipRef? {
        guard let trip = trips.first(where: { !$0.ship.isEmpty && $0.data.ship != nil }) else { return nil }
        return ShipRef(line: trip.line, name: trip.ship)
    }
}
