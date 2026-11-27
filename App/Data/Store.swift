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

/// A change made on this phone that has not reached the server yet. Kept on disk, sent in order.
struct PendingWrite: Codable, Identifiable {
    enum Op: String, Codable {
        /// PATCH when the document exists (with its version), otherwise PUT to create it.
        case upsert
        case delete
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
}

/// The app's single source of truth: the on-disk cache merged from `/v1/sync`, with queued writes laid on top.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var deals: [Deal] = []
    @Published private(set) var feedback: [String: Feedback] = [:]
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var plays: [Play] = []
    @Published private(set) var playNotes: [String: PlayNote] = [:]
    @Published private(set) var status: RunStatus?
    @Published private(set) var profile: [String] = []
    @Published private(set) var watchlist: [WatchItem] = []
    @Published private(set) var syncing = false
    @Published private(set) var problem: Problem?
    @Published private(set) var lastSync: Date?
    @Published private(set) var pendingKeys: Set<String> = []
    /// A one-off message, such as a change the server refused.
    @Published var notice: String?
    @Published var pushProblem: String?

    private var dealIndex: [String: Deal] = [:]
    private var cache: CacheFile
    private var queue: [PendingWrite]
    private let isPreview: Bool
    private var rerunRequested = false
    private var askedForPush = false
    private var monitor: NWPathMonitor?

    private static let cacheFile = "cache.json"
    private static let queueFile = "queue.json"

    init(previewDocs: [String: [String: RawDoc]]? = nil) {
        if let previewDocs {
            isPreview = true
            cache = CacheFile(serverTime: nil, savedAt: Date(), colls: previewDocs)
            queue = []
        } else {
            isPreview = false
            Connection.bootstrap()
            cache = Disk.load(CacheFile.self, from: Store.cacheFile) ?? CacheFile()
            queue = Disk.load([PendingWrite].self, from: Store.queueFile) ?? []
        }
        lastSync = cache.savedAt
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

    func deal(_ id: String) -> Deal? { dealIndex[id] }

    func reviewed(_ verdict: Verdict) -> [Deal] {
        deals
            .filter { feedback[$0.id]?.verdict == verdict }
            .sorted { (feedback[$0.id]?.updated ?? .distantPast) > (feedback[$1.id]?.updated ?? .distantPast) }
    }

    func isPending(_ coll: String, _ id: String) -> Bool {
        pendingKeys.contains("\(coll)/\(id)")
    }

    // MARK: - Sync

    func kick() {
        Task { await refresh() }
    }

    func foregrounded() {
        if let lastSync, Date().timeIntervalSince(lastSync) < 30, queue.isEmpty, problem == nil { return }
        kick()
    }

    /// Sends queued writes, then pulls everything that changed since the last sync.
    func refresh() async {
        if isPreview { return }
        if syncing {
            rerunRequested = true
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
            if !queue.isEmpty { await refresh() }
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
        do {
            switch write.op {
            case .upsert:
                let saved: RawDoc?
                if let current {
                    saved = try await client.patch(write.coll, write.docId, fields: write.fields,
                                                   ifVersion: current.version)
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
            }
        } catch {
            return .stop(.offline(error.localizedDescription))
        }
    }

    private func enqueue(_ op: PendingWrite.Op, _ coll: String, _ id: String, _ fields: [String: JSONValue] = [:]) {
        queue.append(PendingWrite(op: op, coll: coll, docId: id, fields: fields))
        saveQueue()
        rebuild()
        kick()
    }

    /// Records Jim's answer. Changing an answer clears Claude's old reply so it reads the new one.
    func answer(_ deal: Deal, verdict: Verdict, reasons: [String], note: String) {
        enqueue(.upsert, "feedback", deal.id, [
            "dealId": .string(deal.id),
            "verdict": .string(verdict.rawValue),
            "reasons": .array(reasons.map { JSONValue.string($0) }),
            "note": .string(note.capped(500)),
            "updatedAt": .string(Fmt.stamp()),
            "claudeReadAt": .null,
            "claudeReply": .null,
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
        askedForPush = false
        problem = nil
        rebuild()
        kick()
    }

    func reloadEverything() {
        cache.serverTime = nil
        kick()
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
            .sorted { $0.posted > $1.posted }
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
