import Foundation

// MARK: - Tracked sailings (`tracked/<id>`, CONTRACT_V3 section 2)

/// One day of the sparkline: the day's lowest comparable price.
struct DailyPrice: Codable, Hashable {
    var date: String?
    var pp: Int?
}

/// A price an alert email gave for this sailing.
struct AlertPrice: Codable, Hashable {
    var source: String?
    var category: String?
    var pricePP: Int?
    var taxesIncluded: Bool?
    var seenAt: String?
}

/// Where a per-sailing price alert stands on one site.
struct SiteAlert: Codable, Hashable {
    var site: String?
    var state: String?
    var note: String?
    var at: String?

    var stateTitle: String {
        switch state ?? "" {
        case "set": return "Alert set"
        case "pending": return "Setting up"
        case "needs_jim": return "Needs you"
        case "not_offered": return "Not offered"
        case "blocked": return "Blocked"
        case "": return "Not shown"
        default: return Words.humanize(state ?? "")
        }
    }
}

/// Jim's pick (the app writes), then what the server fills from fare data, then what Claude adds. Every field is
/// optional and read leniently, so one odd field never hides a sailing Jim chose.
struct TrackedData: Codable, Hashable {
    // A. Pick (the app writes)
    var line: String?
    var ship: String?
    var sailDate: String?
    var nights: Int?
    var cabin: String?
    var cabinName: String?
    var port: String?
    var link: String?
    var note: String?
    var addedVia: String?
    var addedAt: String?
    // B. Fill (the deal server computes these from its fare data)
    var fareState: String?
    var coverage: String?
    var sailingId: String?
    var pricePP: Int?
    var perNightPP: Int?
    var priceIncludesTaxes: Bool?
    var priceCategory: String?
    var priceSource: String?
    var priceSeenAt: String?
    var typicalPP: Int?
    var typicalN: Int?
    var lowPP: Int?
    var highPP: Int?
    var pctUnderTypical: Int?
    var lowestSeenPP: Int?
    var lowestSeenAt: String?
    var history: [DailyPrice]?
    var embarkPort: String?
    var returnDate: String?
    var stops: [String]?
    var sources: [DealSource]?
    var cabinOptions: [CabinOption]?
    var filledAt: String?
    // C. Enrich (only Claude writes these)
    var itineraryDays: [ItineraryDay]?
    var region: String?
    var alertPrices: [AlertPrice]?
    var alerts: [SiteAlert]?
    var dealId: String?
    var brainNote: String?
    var enrichedAt: String?

    enum CodingKeys: String, CodingKey {
        case line, ship, sailDate, nights, cabin, cabinName, port, link, note, addedVia, addedAt
        case fareState, coverage, sailingId, pricePP, perNightPP, priceIncludesTaxes, priceCategory, priceSource
        case priceSeenAt, typicalPP, typicalN, lowPP, highPP, pctUnderTypical, lowestSeenPP, lowestSeenAt, history
        case embarkPort, returnDate, stops, sources, cabinOptions, filledAt
        case itineraryDays, region, alertPrices, alerts, dealId, brainNote, enrichedAt
    }
}

extension TrackedData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = c.lenient(String.self, .line)
        ship = c.lenient(String.self, .ship)
        sailDate = c.lenient(String.self, .sailDate)
        nights = c.lenient(Int.self, .nights)
        cabin = c.lenient(String.self, .cabin)
        cabinName = c.lenient(String.self, .cabinName)
        port = c.lenient(String.self, .port)
        link = c.lenient(String.self, .link)
        note = c.lenient(String.self, .note)
        addedVia = c.lenient(String.self, .addedVia)
        addedAt = c.lenient(String.self, .addedAt)
        fareState = c.lenient(String.self, .fareState)
        coverage = c.lenient(String.self, .coverage)
        sailingId = c.lenient(String.self, .sailingId)
        pricePP = c.lenient(Int.self, .pricePP)
        perNightPP = c.lenient(Int.self, .perNightPP)
        priceIncludesTaxes = c.lenient(Bool.self, .priceIncludesTaxes)
        priceCategory = c.lenient(String.self, .priceCategory)
        priceSource = c.lenient(String.self, .priceSource)
        priceSeenAt = c.lenient(String.self, .priceSeenAt)
        typicalPP = c.lenient(Int.self, .typicalPP)
        typicalN = c.lenient(Int.self, .typicalN)
        lowPP = c.lenient(Int.self, .lowPP)
        highPP = c.lenient(Int.self, .highPP)
        pctUnderTypical = c.lenient(Int.self, .pctUnderTypical)
        lowestSeenPP = c.lenient(Int.self, .lowestSeenPP)
        lowestSeenAt = c.lenient(String.self, .lowestSeenAt)
        history = c.lenient([DailyPrice].self, .history)
        embarkPort = c.lenient(String.self, .embarkPort)
        returnDate = c.lenient(String.self, .returnDate)
        stops = c.lenient([String].self, .stops)
        sources = c.lenient([DealSource].self, .sources)
        cabinOptions = c.lenient([CabinOption].self, .cabinOptions)
        filledAt = c.lenient(String.self, .filledAt)
        itineraryDays = c.lenient([ItineraryDay].self, .itineraryDays)
        region = c.lenient(String.self, .region)
        alertPrices = c.lenient([AlertPrice].self, .alertPrices)
        alerts = c.lenient([SiteAlert].self, .alerts)
        dealId = c.lenient(String.self, .dealId)
        brainNote = c.lenient(String.self, .brainNote)
        enrichedAt = c.lenient(String.self, .enrichedAt)
    }
}

/// `fareState`: how far the server has got filling a tracked sailing. A value this version does not know is shown
/// plainly, never dropped.
enum FareState: Equatable {
    case pending, searching, matched, noCoverage, sailed
    case unknown(String)

    init(_ raw: String?) {
        switch raw?.trimmed ?? "" {
        case "", "pending": self = .pending
        case "searching": self = .searching
        case "matched": self = .matched
        case "no_coverage": self = .noCoverage
        case "sailed": self = .sailed
        default: self = .unknown(raw ?? "")
        }
    }

    var title: String {
        switch self {
        case .pending: return "Waiting for the first fill"
        case .searching: return "Looking for this sailing"
        case .matched: return "Price found"
        case .noCoverage: return "No price source yet"
        case .sailed: return "Sailed"
        case .unknown(let raw): return Words.humanize(raw)
        }
    }
}

/// What a field shows while it has no value (CONTRACT_V3 section 4). Never a made-up number.
enum Fill {
    static let filling = "filling…"
    static let notShown = "not shown"
    static let notFound = "not found yet"
    static let thinHistory = "not enough history"
    static let sailed = "sailed"

    enum Kind {
        /// A field the server fills from fare data.
        case fill
        /// typicalPP, which says when the history is too thin.
        case typical
        /// A field only Claude writes.
        case enrich
    }
}

struct TrackedSailing: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: TrackedData
    /// Saved on this phone and not on the deal server yet.
    var isLocal = false
    /// v4 fill: the line's own page for this sailing and any agency that is clearly better.
    var booking: BookingInfo? = nil
    var alternatives: [BookAlternative] = []

    init?(raw: RawDoc, isLocal: Bool = false) {
        guard let decoded = raw.data.decode(TrackedData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
        self.isLocal = isLocal
        booking = BookingInfo.from(raw.data)
        alternatives = BookAlternative.from(raw.data)
    }

    init(id: String, data: TrackedData, booking: BookingInfo? = nil, alternatives: [BookAlternative] = []) {
        self.id = id
        self.version = 1
        self.data = data
        self.booking = booking
        self.alternatives = alternatives
    }

    var line: String { CruiseLine.resolved(data.line) }
    var ship: String {
        let name = data.ship?.trimmed ?? ""
        return name.isEmpty ? "Sailing" : name
    }
    var sailDay: Date? { Fmt.day(data.sailDate) }
    var added: Date? { Fmt.timestamp(data.addedAt) }
    var cabinType: CabinType? { data.cabin.flatMap { CabinType(rawValue: $0) } }
    var size: ShipSize? { CatalogIndex.current.size(line: line, ship: data.ship) }
    var coverage: Coverage? { Coverage(data.coverage) }
    var link: URL? { Fmt.webURL(data.link) }

    /// The server's fill state; a sailing whose date has passed reads as sailed even before the server says so.
    var state: FareState {
        if let day = sailDay, Fmt.daysLeft(day) < 0 { return .sailed }
        return FareState(data.fareState)
    }

    var returnDay: Date? {
        if let day = Fmt.day(data.returnDate) { return day }
        guard let start = sailDay, let nights = data.nights, nights > 0 else { return nil }
        return Fmt.adding(days: nights, to: start)
    }

    /// "Sun Aug 16 – Sat Aug 22, 2027 · 6 nights"
    var datesLine: String {
        var parts: [String] = []
        if let start = sailDay { parts.append(Fmt.tripDates(from: start, to: returnDay)) }
        if let nights = data.nights { parts.append(Fmt.nights(nights)) }
        return parts.joined(separator: " · ")
    }

    /// "Royal Caribbean · Mega ship"
    var eyebrow: String {
        [line, size?.shipTitle].compactMap { $0 }.joined(separator: " · ")
    }

    /// Where it leaves from: the fare data's port, else the one Jim gave.
    var portName: String? {
        for value in [data.embarkPort, data.port] {
            if let text = value?.trimmed, !text.isEmpty { return text }
        }
        return nil
    }

    /// "Balcony · Ocean View Balcony · Galveston"
    var pickLine: String {
        var parts: [String] = []
        if let cabin = cabinType?.title { parts.append(cabin) }
        if let name = data.cabinName?.trimmed, !name.isEmpty,
           name.caseInsensitiveCompare(cabinType?.title ?? "") != .orderedSame {
            parts.append(name)
        }
        if let port = portName { parts.append(port) }
        return parts.joined(separator: " · ")
    }

    /// "Galveston → Cozumel · Roatán → Galveston"
    var route: String? {
        let stops = (data.stops ?? []).map { $0.trimmed }.filter { !$0.isEmpty && !Deal.isSeaDay($0) }
        guard let from = portName else { return stops.isEmpty ? nil : stops.joined(separator: " · ") }
        if stops.isEmpty { return nil }
        return "\(from) → \(stops.joined(separator: " · ")) → \(from)"
    }

    var priceRange: Deal.PriceRange? {
        guard let price = data.pricePP, price > 0 else { return nil }
        if data.lowPP == nil && data.typicalPP == nil && data.highPP == nil { return nil }
        return Deal.PriceRange(price: price, low: data.lowPP, typical: data.typicalPP, high: data.highPP)
    }

    /// The daily lows, oldest first, for the sparkline.
    var historyValues: [Int] {
        (data.history ?? []).compactMap { $0.pp }.filter { $0 > 0 }
    }

    var historyPoints: [PricePoint] {
        (data.history ?? []).compactMap { day -> PricePoint? in
            guard let pp = day.pp, pp > 0 else { return nil }
            let stamp = day.date.map { String($0.prefix(10)) + "T12:00:00Z" } ?? ""
            return PricePoint(pricePP: pp, cabin: data.cabin, source: nil, seenAt: stamp)
        }
    }

    /// Same sailing, same cabin: the server refuses a second one (CONTRACT_V3 "Dedup").
    var key: String { TrackKey.make(line: line, ship: data.ship, sailDate: data.sailDate, nights: data.nights, cabin: data.cabin) }

    private var daysSinceAdded: Int {
        guard let added else { return 0 }
        return Int(Date().timeIntervalSince(added) / 86400)
    }

    /// What a field shows while it has no value.
    func missing(_ kind: Fill.Kind = .fill) -> String {
        if state == .sailed { return Fill.sailed }
        switch kind {
        case .enrich:
            return data.enrichedAt == nil ? Fill.filling : Fill.notShown
        case .typical:
            if let n = data.typicalN, n < 5 { return Fill.thinHistory }
        case .fill:
            break
        }
        switch state {
        case .pending: return Fill.filling
        case .searching: return daysSinceAdded >= 7 ? Fill.notFound : Fill.filling
        case .noCoverage: return "no price source for \(line) yet"
        case .matched, .unknown: return Fill.notShown
        case .sailed: return Fill.sailed
        }
    }

    /// Coming up first (soonest), sailed ones last.
    static func order(_ a: TrackedSailing, _ b: TrackedSailing) -> Bool {
        let aSailed = a.state == .sailed
        let bSailed = b.state == .sailed
        if aSailed != bSailed { return !aSailed }
        let x = a.sailDay ?? .distantFuture
        let y = b.sailDay ?? .distantFuture
        if x != y { return aSailed ? x > y : x < y }
        return a.id < b.id
    }
}

enum TrackKey {
    static func make(line: String?, ship: String?, sailDate: String?, nights: Int?, cabin: String?) -> String {
        [CruiseLine.slug(CruiseLine.resolved(line)), Slug.ship(ship ?? ""), String((sailDate ?? "").prefix(10)),
         String(nights ?? 0), cabin ?? ""].joined(separator: "|")
    }
}

// MARK: - The Track builder's pick

/// What the Track builder hands the Store: line -> ship -> date -> nights -> cabin, plus the optional extras.
struct TrackPick: Equatable {
    var line: String = CruiseLine.royal
    var ship: String = ""
    var sailDate: Date? = nil
    var nights: Int = 7
    var cabin: CabinType = .balcony
    var cabinName: String = ""
    var port: String = ""
    var link: String = ""
    var note: String = ""
    /// pick | link
    var via: String = "pick"

    init() {}

    /// A deal's sailing, ready to track.
    init(deal: Deal) {
        line = deal.line
        ship = deal.data.ship ?? ""
        sailDate = deal.sailDay
        nights = deal.data.nights ?? 7
        cabin = deal.cabinType ?? .balcony
        cabinName = deal.data.cabinName ?? ""
        port = deal.data.port ?? ""
        link = TrackPick.validLink(deal.data.link ?? "") ?? ""
    }

    var key: String {
        TrackKey.make(line: line, ship: ship, sailDate: sailDate.map { Fmt.isoDay($0) }, nights: nights,
                      cabin: cabin.rawValue)
    }

    /// Why it can't be tracked yet, in plain words; nil when it can.
    var problem: String? {
        let name = ship.trimmed
        if name.isEmpty { return "Pick a ship." }
        if name.count > 40 { return "The ship's name is longer than 40 letters." }
        guard let day = sailDate else { return "Pick the sail date." }
        if Fmt.daysLeft(day) < 0 { return "That sail date has passed." }
        if !(1...30).contains(nights) { return "Nights must be between 1 and 30." }
        if !link.trimmed.isEmpty && TrackPick.validLink(link) == nil {
            return "The link must start with https:// and be 500 characters at most."
        }
        return nil
    }

    static func validLink(_ text: String) -> String? {
        let value = text.trimmed
        guard !value.isEmpty, value.count <= 500, let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return value
    }

    /// The pick fields exactly as the server takes them (`POST /v1/tracked`).
    func fields(stamp: String = Fmt.stamp()) -> [String: JSONValue] {
        var f: [String: JSONValue] = [
            "line": .string(CruiseLine.resolved(line)),
            "ship": .string(ship.trimmed.capped(40)),
            "nights": .int(min(max(nights, 1), 30)),
            "cabin": .string(cabin.rawValue),
            "addedVia": .string(via == "link" ? "link" : "pick"),
            "addedAt": .string(stamp),
        ]
        if let day = sailDate { f["sailDate"] = .string(Fmt.isoDay(day)) }
        func optional(_ key: String, _ value: String, _ cap: Int) {
            let text = value.trimmed.capped(cap)
            if !text.isEmpty { f[key] = .string(text) }
        }
        optional("cabinName", cabinName, 40)
        optional("port", port, 30)
        optional("note", note, 120)
        if let url = TrackPick.validLink(link) { f["link"] = .string(url) }
        return f
    }
}

/// Opens the Track builder: empty, from a deal, or from a shared link or text.
struct TrackSeed: Identifiable, Equatable {
    let id = UUID()
    var pick: TrackPick? = nil
    var text: String? = nil
}

// MARK: - Known sailings (`GET /v1/fares/sailings`), for browse-and-pick

struct FareRow: Decodable, Hashable {
    var pricePP: Int?
    var taxesIncluded: Bool?
    var category: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case pricePP, taxesIncluded, category, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pricePP = c.lenient(Int.self, .pricePP)
        taxesIncluded = c.lenient(Bool.self, .taxesIncluded)
        category = c.lenient(String.self, .category)
        source = c.lenient(String.self, .source)
    }

    init(pricePP: Int?, taxesIncluded: Bool?, category: String?, source: String?) {
        self.pricePP = pricePP
        self.taxesIncluded = taxesIncluded
        self.category = category
        self.source = source
    }
}

struct FareSailing: Decodable, Hashable, Identifiable {
    var id: String
    var ship: String?
    var shipName: String?
    var line: String?
    var sailDate: String?
    var nights: Int?
    var embarkPort: String?
    var bestByClass: [String: FareRow]?

    enum CodingKeys: String, CodingKey {
        case id, ship, shipName, line, sailDate, nights, embarkPort, bestByClass
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, .id) ?? UUID().uuidString
        ship = c.lenient(String.self, .ship)
        shipName = c.lenient(String.self, .shipName)
        line = c.lenient(String.self, .line)
        sailDate = c.lenient(String.self, .sailDate)
        nights = c.lenient(Int.self, .nights)
        embarkPort = c.lenient(String.self, .embarkPort)
        bestByClass = c.lenient([String: FareRow].self, .bestByClass)
    }

    init(id: String, ship: String?, line: String?, sailDate: String?, nights: Int?, embarkPort: String?,
         bestByClass: [String: FareRow]?) {
        self.id = id
        self.ship = ship
        self.shipName = nil
        self.line = line
        self.sailDate = sailDate
        self.nights = nights
        self.embarkPort = embarkPort
        self.bestByClass = bestByClass
    }

    var sailDay: Date? { Fmt.day(sailDate) }
}

struct SailingsResult: Decodable {
    var sailings: [FareSailing]
}

// MARK: - The refresh nudge (`POST` / `GET /v1/refresh`)

struct NudgeResult: Decodable, Hashable {
    var accepted: Bool?
    var requestedAt: String?
    var nextAllowedAt: String?

    enum CodingKeys: String, CodingKey {
        case accepted, requestedAt, nextAllowedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accepted = c.lenient(Bool.self, .accepted)
        requestedAt = c.lenient(String.self, .requestedAt)
        nextAllowedAt = c.lenient(String.self, .nextAllowedAt)
    }

    init(accepted: Bool?, requestedAt: String?, nextAllowedAt: String?) {
        self.accepted = accepted
        self.requestedAt = requestedAt
        self.nextAllowedAt = nextAllowedAt
    }
}

struct RefreshState: Decodable, Hashable {
    var requestedAt: String?
    var reason: String?
    var collectorSeenAt: String?
    var collectorDoneAt: String?
    var refilledAt: String?

    enum CodingKeys: String, CodingKey {
        case requestedAt, reason, collectorSeenAt, collectorDoneAt, refilledAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestedAt = c.lenient(String.self, .requestedAt)
        reason = c.lenient(String.self, .reason)
        collectorSeenAt = c.lenient(String.self, .collectorSeenAt)
        collectorDoneAt = c.lenient(String.self, .collectorDoneAt)
        refilledAt = c.lenient(String.self, .refilledAt)
    }
}
