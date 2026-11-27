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
}

/// The app's single source of truth: the on-disk cache merged from `/v1/sync`, with queued writes laid on top.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// The most sailings the server keeps tracked.
    static let trackedLimit = 50

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

    init(previewDocs: [String: [String: RawDoc]]? = nil, level previewLevel: ServerLevel = .v3) {
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
            catalog = previewLevel == .v3 ? Samples.catalog : .builtIn
        } else {
            level = cache.level.flatMap { ServerLevel(rawValue: $0) } ?? .unknown
            catalog = (level == .v3 ? cache.catalog : nil) ?? .builtIn
        }
        CatalogIndex.current = catalog
        rebuild()
        if !isPreview { startMonitor() }
    }

    static func preview() -> Store {
        Store(previewDocs: Samples.docs)
    }

    // MARK: - What the screens read

    /// Deals with no answer yet, newest first.
    var inbox: [Deal] { deals.filter { feedback[$0.id]?.verdict == nil } }
    var unansweredCount: Int { inbox.count }
    var pendingCount: Int { queue.count }
    var cachedDealCount: Int { cache.colls["deals"]?.count ?? 0 }

    /// The deal server has v3: lines, tracking, coverage, the refresh nudge.
    var isV3: Bool { level == .v3 }

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
        TripCheck.verdict(for: deal, prefs: trip)
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
        return DealOrder.sorted(list, by: sort, preferred: { self.fit($0).preferred })
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
        let isTracked = write.coll == "tracked"
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
                } else if isTracked {
                    // Gone from the server: there is nothing to change (tracked sailings are never made by PUT).
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
            if isTracked, let outcome = trackedFailure(write, error) { return outcome }
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

    /// CONTRACT_V3 section 8: a tracked write never waits on an older server. A 404 on create, or a 405 on any of
    /// them, drops it and the app goes back to v2 behaviour; a 409 on create means it is already tracked.
    private func trackedFailure(_ write: PendingWrite, _ error: APIError) -> Outcome? {
        switch (write.op, error) {
        case (.create, .conflict):
            return .sent
        case (.create, .notFound), (_, .unsupported):
            setLevel(.v2)
            saveCache()
            return .dropped("Tracking isn't on the deal server yet, so that change wasn't saved.")
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
        enqueue(.upsert, "prefs", "trip", prefs.cleaned().fields(v3: isV3))
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

        let localIds = Set(queue.filter { $0.op == .create }.map { $0.docId })
        tracked = (colls["tracked"] ?? [:]).values
            .compactMap { TrackedSailing(raw: $0, isLocal: localIds.contains($0.id)) }
            .sorted(by: TrackedSailing.order)

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
