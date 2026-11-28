import Foundation

// MARK: - My past trips (CONTRACT_V4 section 4.1)

struct TripPort: Codable, Hashable {
    var name: String?
    var rating: Int?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case name, rating, note
    }
}

extension TripPort {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, .name)
        rating = c.lenient(Int.self, .rating)
        note = c.lenient(String.self, .note)
    }
}

struct PastTripData: Codable, Hashable {
    var line: String?
    var ship: String?
    var sailDate: String?
    var nights: Int?
    var embarkPort: String?
    var ports: [TripPort]?
    var rating: Int?
    var cabin: String?
    var cabinName: String?
    var pricePaidPP: Int?
    var notes: String?
    var addedVia: String?
    var addedAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case line, ship, sailDate, nights, embarkPort, ports, rating, cabin, cabinName, pricePaidPP, notes
        case addedVia, addedAt, updatedAt
    }
}

extension PastTripData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = c.lenient(String.self, .line)
        ship = c.lenient(String.self, .ship)
        sailDate = c.lenient(String.self, .sailDate)
        nights = c.lenient(Int.self, .nights)
        embarkPort = c.lenient(String.self, .embarkPort)
        ports = c.lenient([TripPort].self, .ports)
        rating = c.lenient(Int.self, .rating)
        cabin = c.lenient(String.self, .cabin)
        cabinName = c.lenient(String.self, .cabinName)
        pricePaidPP = c.lenient(Int.self, .pricePaidPP)
        notes = c.lenient(String.self, .notes)
        addedVia = c.lenient(String.self, .addedVia)
        addedAt = c.lenient(String.self, .addedAt)
        updatedAt = c.lenient(String.self, .updatedAt)
    }
}

/// A cruise Jim took, with each port's rating and the trip's own.
struct PastTrip: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: PastTripData
    /// Saved on this phone and not on the deal server yet.
    var isLocal = false
    /// v5: what we had on board (drinks package, Wi-Fi, a promo), read on its own (CONTRACT_V5 section 3.5).
    var extras: [TripExtra] = []

    init?(raw: RawDoc, isLocal: Bool = false) {
        guard let decoded = raw.data.decode(PastTripData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
        self.isLocal = isLocal
        extras = TripExtra.from(raw.data)
    }

    init(id: String, data: PastTripData) {
        self.id = id
        self.version = 1
        self.data = data
    }

    var line: String { CruiseLine.resolved(data.line) }
    var ship: String {
        let name = data.ship?.trimmed ?? ""
        return name.isEmpty ? "Cruise" : name
    }
    var sailDay: Date? { Fmt.day(data.sailDate) }
    var ports: [TripPort] { (data.ports ?? []).filter { !($0.name?.trimmed.isEmpty ?? true) } }
    var ratedCount: Int { ports.filter { $0.rating != nil }.count }

    /// "Sun Nov 1 – Sun Nov 8, 2026 · 7 nights"
    var datesLine: String {
        var parts: [String] = []
        if let start = sailDay {
            let end = data.nights.flatMap { Fmt.adding(days: $0, to: start) }
            parts.append(Fmt.tripDates(from: start, to: end))
        }
        if let nights = data.nights { parts.append(Fmt.nights(nights)) }
        return parts.joined(separator: " · ")
    }

    /// "Miami → Roatan · Harvest Caye · Costa Maya · Cozumel"
    var route: String? {
        let names = ports.compactMap { $0.name?.trimmed }
        guard !names.isEmpty else { return data.embarkPort }
        if let from = data.embarkPort?.trimmed, !from.isEmpty { return "\(from) → \(names.joined(separator: " · "))" }
        return names.joined(separator: " · ")
    }

    static func order(_ a: PastTrip, _ b: PastTrip) -> Bool {
        let x = a.data.sailDate ?? ""
        let y = b.data.sailDate ?? ""
        if x != y { return x > y }
        return a.id < b.id
    }
}

/// What the trip editor works on; the server takes it as a POST (new) or PATCH (every field but addedVia/addedAt).
struct TripDraft: Equatable {
    struct Port: Equatable, Identifiable {
        var id = UUID()
        var name: String
        var rating: Int?
        var note: String = ""
    }

    var line: String = CruiseLine.royal
    var ship: String = ""
    var sailDate: Date? = nil
    var nights: Int = 7
    var embarkPort: String = ""
    var ports: [Port] = []
    var rating: Int? = nil
    var cabin: CabinType? = nil
    var pricePaidPP: Int? = nil
    var notes: String = ""
    /// manual | catalog (the ports came from Deal Desk's fare data)
    var via: String = "manual"
    /// v5: what we had on board; sent only when the server lists `reference`.
    var extras: [TripExtra] = []

    init() {}

    init(trip: PastTrip) {
        line = trip.line
        ship = trip.data.ship ?? ""
        sailDate = trip.sailDay
        nights = trip.data.nights ?? 7
        embarkPort = trip.data.embarkPort ?? ""
        ports = trip.ports.map { Port(name: $0.name ?? "", rating: $0.rating, note: $0.note ?? "") }
        rating = trip.data.rating
        cabin = trip.data.cabin.flatMap { CabinType(rawValue: $0) }
        pricePaidPP = trip.data.pricePaidPP
        notes = trip.data.notes ?? ""
        via = trip.data.addedVia ?? "manual"
        extras = trip.extras
    }

    /// Why it can't be saved yet, in plain words; nil when it can.
    var problem: String? {
        let name = ship.trimmed
        if name.isEmpty { return "Pick the ship." }
        if name.count > 40 { return "The ship's name is longer than 40 letters." }
        guard let day = sailDate else { return "Pick the sail date." }
        if Fmt.daysLeft(day) > 1 { return "A future sailing belongs in Tracking." }
        if !(1...30).contains(nights) { return "Nights must be between 1 and 30." }
        if cleanPorts.count > 14 { return "At most 14 ports (sea days aren't listed)." }
        return nil
    }

    var cleanPorts: [Port] {
        ports.filter { !$0.name.trimmed.isEmpty }
    }

    static func clampRating(_ value: Int?) -> Int? {
        value.map { min(max($0, 1), 10) }
    }

    /// Fields for `POST /v1/trips` (`isNew`) or `PATCH /v1/trips/{id}`: a PATCH never sends addedVia/addedAt.
    func fields(isNew: Bool, stamp: String = Fmt.stamp(), sendExtras: Bool = false) -> [String: JSONValue] {
        func text(_ value: String, _ cap: Int) -> JSONValue {
            let clean = value.trimmed.capped(cap)
            return clean.isEmpty ? .null : .string(clean)
        }
        var f: [String: JSONValue] = [
            "line": .string(CruiseLine.resolved(line)),
            "ship": .string(ship.trimmed.capped(40)),
            "nights": .int(min(max(nights, 1), 30)),
            "embarkPort": text(embarkPort, 30),
            "ports": .array(Array(cleanPorts.prefix(14)).map { port -> JSONValue in
                var item: [String: JSONValue] = ["name": .string(port.name.trimmed.capped(40))]
                item["rating"] = TripDraft.clampRating(port.rating).map { JSONValue.int($0) } ?? .null
                let note = port.note.trimmed.capped(140)
                item["note"] = note.isEmpty ? .null : .string(note)
                return .object(item)
            }),
            "rating": TripDraft.clampRating(rating).map { JSONValue.int($0) } ?? .null,
            "cabin": cabin.map { JSONValue.string($0.rawValue) } ?? .null,
            "pricePaidPP": pricePaidPP.map { JSONValue.int(max($0, 0)) } ?? .null,
            "notes": text(notes, 500),
        ]
        if let day = sailDate { f["sailDate"] = .string(Fmt.isoDay(day)) }
        if sendExtras {
            let kept = extras.filter { !$0.name.trimmed.isEmpty }.prefix(8)
            f["extras"] = .array(kept.map { $0.json })
        }
        if isNew {
            f["addedVia"] = .string(via == "catalog" ? "catalog" : "manual")
            f["addedAt"] = .string(stamp)
            // A create leaves out what is empty; nulls are only for clearing on a PATCH.
            f = f.filter { $0.value != .null }
        } else {
            f["updatedAt"] = .string(stamp)
        }
        return f
    }

    var key: String {
        [CruiseLine.slug(CruiseLine.resolved(line)), Slug.ship(ship), sailDate.map { Fmt.isoDay($0) } ?? ""]
            .joined(separator: "|")
    }
}

/// `GET /v1/trips/prefill`: what Deal Desk already knows about a past sailing (nothing is fetched).
struct TripPrefill: Decodable, Equatable {
    var embarkPort: String?
    var nights: Int?
    var stops: [String]
    var source: String?

    enum CodingKeys: String, CodingKey {
        case embarkPort, nights, stops, source
    }

    init(embarkPort: String?, nights: Int?, stops: [String], source: String?) {
        self.embarkPort = embarkPort
        self.nights = nights
        self.stops = stops
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        embarkPort = c.lenient(String.self, .embarkPort)
        nights = c.lenient(Int.self, .nights)
        stops = c.lenient([String].self, .stops) ?? []
        source = c.lenient(String.self, .source)
    }

    var found: Bool { source != nil && (nights != nil || !stops.isEmpty || embarkPort != nil) }

    /// Port stops only: sea days are not listed on a trip.
    var ports: [String] {
        stops.map { $0.trimmed }.filter { !$0.isEmpty && !Deal.isSeaDay($0) }
    }
}

// MARK: - Ports summary (CONTRACT_V4 section 4.2; the server works it out from the trips)

struct PortVisit: Codable, Hashable {
    var tripId: String?
    var sailDate: String?
    var rating: Int?
}

struct PortSummary: Codable, Hashable, Identifiable {
    var key: String
    var name: String?
    var region: String?
    var rating: Int?
    var ratedAt: String?
    var visits: Int?
    var lastVisited: String?
    var daysSince: Int?
    var history: [PortVisit]?
    var ratingAdj: Int?
    var recencyAdj: Int?
    var adj: Int?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, region, rating, ratedAt, visits, lastVisited, daysSince, history, ratingAdj, recencyAdj, adj
    }

    var title: String {
        let text = name?.trimmed ?? ""
        return text.isEmpty ? Words.title(fromSlug: key) : text
    }

    /// The name before any "(" or ",": "Roatan (Coxen Hole)" -> "Roatan".
    var shortName: String {
        let head = title.split(whereSeparator: { $0 == "(" || $0 == "," }).first.map(String.init)?.trimmed ?? ""
        return head.isEmpty ? title : head
    }
}

extension PortSummary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(String.self, .key) ?? ""
        name = c.lenient(String.self, .name)
        region = c.lenient(String.self, .region)
        rating = c.lenient(Int.self, .rating)
        ratedAt = c.lenient(String.self, .ratedAt)
        visits = c.lenient(Int.self, .visits)
        lastVisited = c.lenient(String.self, .lastVisited)
        daysSince = c.lenient(Int.self, .daysSince)
        history = c.lenient([PortVisit].self, .history)
        ratingAdj = c.lenient(Int.self, .ratingAdj)
        recencyAdj = c.lenient(Int.self, .recencyAdj)
        adj = c.lenient(Int.self, .adj)
    }
}

struct PortsSummary: Hashable {
    var asOf: String?
    var ports: [PortSummary]
    var computedAt: String?

    init?(raw: RawDoc) {
        let data = raw.data
        guard case .object = data else { return nil }
        asOf = data.field("asOf")?.stringValue
        computedAt = data.field("computedAt")?.stringValue
        var list: [PortSummary] = []
        if case .array(let entries)? = data.field("ports") {
            for entry in entries {
                if let port = entry.decode(PortSummary.self), !port.key.isEmpty { list.append(port) }
            }
        }
        ports = list
    }

    init(asOf: String?, ports: [PortSummary], computedAt: String?) {
        self.asOf = asOf
        self.ports = ports
        self.computedAt = computedAt
    }

    func port(_ key: String) -> PortSummary? { ports.first { $0.key == key } }

    /// Visited or rated ports, most recently visited first.
    var visited: [PortSummary] {
        ports.sorted { a, b in
            let x = a.lastVisited ?? ""
            let y = b.lastVisited ?? ""
            if x != y { return x > y }
            return a.title < b.title
        }
    }
}

// MARK: - Port keys (CONTRACT_V4 section 5.1)

enum PortKey {
    /// The text before the first "(" or ",", accents folded, lower-case, runs of anything else turned into "-".
    static func fold(_ text: String) -> String {
        let head = text.split(maxSplits: 1, omittingEmptySubsequences: false,
                              whereSeparator: { $0 == "(" || $0 == "," }).first.map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        for scalar in head.decomposedStringWithCompatibilityMapping.unicodeScalars
        where scalar.properties.canonicalCombiningClass.rawValue == 0 {
            scalars.append(scalar)
        }
        let folded = String(scalars).replacingOccurrences(of: "\u{2019}", with: "'")
        return Slug.plain(folded)
    }

    /// The reference ports' other names, as the deal server's catalog lists them.
    private static let table: [String: [String]] = [
        "costa-maya": ["Mahahual"], "roatan": ["Coxen Hole", "Mahogany Bay", "Isla Roatan"], "belize": ["Belize City", "Belize"],
        "grand-cayman": ["George Town"], "puerto-limon": ["Limon"], "colon": ["Cristobal"], "amber-cove": ["Puerto Plata"],
        "la-romana": ["Casa de Campo"], "st-thomas": ["Saint Thomas", "Charlotte Amalie", "St Thomas", "St. Thomas"],
        "st-maarten": ["Saint Maarten", "St Maarten", "Philipsburg", "Sint Maarten", "St. Maarten"],
        "st-kitts": ["Saint Kitts", "Basseterre", "St Kitts", "St. Kitts"], "tortola": ["Road Town"],
        "st-croix": ["Saint Croix", "Frederiksted", "St Croix", "St. Croix"], "grand-turk": ["Cockburn Town"],
        "barbados": ["Bridgetown"], "st-lucia": ["Saint Lucia", "Castries", "St Lucia", "St. Lucia"], "aruba": ["Oranjestad"],
        "curacao": ["Willemstad"], "bonaire": ["Kralendijk"], "martinique": ["Fort-de-France", "Fort de France"],
        "dominica": ["Roseau"], "cococay": ["Perfect Day at CocoCay", "Coco Cay", "CocoCay"], "freeport": ["Grand Bahama"],
        "half-moon-cay": ["Little San Salvador", "RelaxAway Half Moon Cay"], "cabo-san-lucas": ["Cabo"],
        "catalina-island": ["Avalon"], "miami": ["PortMiami", "Port of Miami"],
        "fort-lauderdale": ["Port Everglades", "Ft. Lauderdale", "Ft Lauderdale"],
        "port-canaveral": ["Cape Canaveral", "Orlando"], "cape-liberty": ["Bayonne"], "new-york": ["Manhattan"],
        "los-angeles": ["San Pedro", "Long Beach"],
    ]

    private static let aliases: [String: String] = {
        var out: [String: String] = [:]
        for (key, names) in PortKey.table {
            for name in names { out[PortKey.fold(name)] = key }
        }
        return out
    }()

    /// The port's key; a summary's own spelling of a name maps to its key too.
    static func key(_ text: String, summary: PortsSummary? = nil) -> String? {
        let folded = fold(text)
        guard !folded.isEmpty else { return nil }
        if let alias = aliases[folded] { return alias }
        if let summary, let match = summary.ports.first(where: { fold($0.title) == folded }) { return match.key }
        return folded
    }
}

// MARK: - Fit (CONTRACT_V4 section 4.3: soft only, never a filter)

/// How Jim's own port history nudges a sailing: at most 15 points either way, with up to 3 plain reasons
/// ("Cozumel 3 wk ago", "Roatan 9/10"). It changes ranking and wording only; it never hides a deal.
struct PortFit: Codable, Hashable {
    var adj: Int
    var reasons: [String]

    /// One soft sentence for a card: "you were in Cozumel 3 weeks ago · you rated Roatan 9/10".
    var phrases: [String] = []

    enum CodingKeys: String, CodingKey {
        case adj, reasons
    }

    init(adj: Int, reasons: [String], phrases: [String] = []) {
        self.adj = adj
        self.reasons = reasons
        self.phrases = phrases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adj = c.lenient(Int.self, .adj) ?? 0
        reasons = c.lenient([String].self, .reasons) ?? []
        phrases = []
    }

    var caption: String { (phrases.isEmpty ? reasons : phrases).joined(separator: " · ") }

    static let maxAbs = 15

    /// Sums the summary's per-port adjustments over the distinct ports a sailing stops at (not where it leaves from or
    /// returns to). nil when the stops are unknown or nothing applies.
    static func of(stops: [String], embark: String?, returnPort: String?, summary: PortsSummary?) -> PortFit? {
        guard let summary, !stops.isEmpty else { return nil }
        let skip = Set([embark, returnPort].compactMap { $0 }.compactMap { PortKey.key($0, summary: summary) })
        var keys: [String] = []
        for stop in stops where !Deal.isSeaDay(stop) {
            guard let key = PortKey.key(stop, summary: summary), !skip.contains(key), !keys.contains(key) else { continue }
            keys.append(key)
        }
        var total = 0
        var chips: [(mag: Int, name: String, chip: String, phrase: String)] = []
        for key in keys {
            guard let port = summary.port(key), let adj = port.adj, adj != 0 else { continue }
            total += adj
            let rating = port.ratingAdj ?? 0
            let recency = port.recencyAdj ?? 0
            let name = port.shortName
            if rating != 0, abs(rating) >= abs(recency), let stars = port.rating {
                chips.append((abs(rating), name, "\(name) \(stars)/10".capped(40), "you rated \(name) \(stars)/10"))
            } else if let days = port.daysSince {
                chips.append((abs(recency), name, "\(name) \(ago(days))".capped(40), "you were in \(name) \(agoWords(days))"))
            }
        }
        guard !chips.isEmpty else { return nil }
        chips.sort { ($0.mag, $1.name) > ($1.mag, $0.name) }
        let top = Array(chips.prefix(3))
        return PortFit(adj: max(-maxAbs, min(maxAbs, total)), reasons: top.map { $0.chip }, phrases: top.map { $0.phrase })
    }

    /// "5 d ago", "3 wk ago", "4 mo ago" (the server's own chip wording).
    static func ago(_ days: Int) -> String {
        if days < 14 { return "\(max(days, 0)) d ago" }
        if days < 60 { return "\(Int((Double(days) / 7).rounded())) wk ago" }
        return "\(Int((Double(days) / 30.4).rounded())) mo ago"
    }

    /// "5 days ago", "3 weeks ago", "4 months ago"
    static func agoWords(_ days: Int) -> String {
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s") ago" }
        if days <= 0 { return "today" }
        if days < 14 { return unit(days, "day") }
        if days < 60 { return unit(Int((Double(days) / 7).rounded()), "week") }
        return unit(Int((Double(days) / 30.4).rounded()), "month")
    }
}
