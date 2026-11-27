import Foundation

// MARK: - What the server stores

/// Every server document: `{"id", "data", "version", "updatedAt"}` (DESIGN.md "Data model").
struct RawDoc: Codable, Hashable {
    var id: String
    var data: JSONValue
    var version: Int
    var updatedAt: String?
}

// MARK: - Deals

enum DealKind: String, CaseIterable, Identifiable {
    case fits, call, drop, sale

    var id: String { rawValue }

    /// The words on the small pill.
    var pill: String {
        switch self {
        case .fits: return "FITS"
        case .call: return "YOUR CALL"
        case .drop: return "PRICE DROP"
        case .sale: return "SALE"
        }
    }

    /// Full name, for VoiceOver and headings.
    var title: String {
        switch self {
        case .fits: return "Fits your trip"
        case .call: return "Your call"
        case .drop: return "Price drop"
        case .sale: return "New sale"
        }
    }
}

enum CabinType: String {
    case interior, oceanview, balcony, suite

    var title: String {
        switch self {
        case .interior: return "Interior"
        case .oceanview: return "Ocean view"
        case .balcony: return "Balcony"
        case .suite: return "Suite"
        }
    }
}

struct DealSource: Codable, Hashable {
    var name: String
    var url: String
    var pricePP: Int?
    var includesTaxes: Bool?
}

struct OfferRow: Codable, Hashable {
    var label: String
    var value: String
}

enum ShipClass: String, CaseIterable, Identifiable {
    case icon, oasis, quantum, other

    var id: String { rawValue }

    /// "Icon", "Oasis", "Quantum", "Smaller"
    var short: String {
        switch self {
        case .icon: return "Icon"
        case .oasis: return "Oasis"
        case .quantum: return "Quantum"
        case .other: return "Smaller"
        }
    }

    /// "Icon class", or "Smaller ship"
    var title: String { self == .other ? "Smaller ship" : "\(short) class" }
}

/// One cabin category a source lists for the sailing (v2 `cabinOptions`).
struct CabinOption: Codable, Hashable {
    var category: String?
    var type: String?
    var pricePP: Int?
    var taxesIncluded: Bool?
    var source: String?
}

/// One day of the itinerary (v2 `itineraryDays`): arrive/depart are short clock texts like "7:00 AM".
struct ItineraryDay: Codable, Hashable {
    var day: Int?
    var date: String?
    var port: String?
    var arrive: String?
    var depart: String?
}

/// `deals/<id>` data, exactly the fields in DESIGN.md and DESIGN_V2.md. Everything is optional here so one odd
/// document never hides the rest; the server enforces the real schema. v1 fields (`usualPP`, `ports`) are still
/// read, so deals written before v2 render the same way.
struct DealData: Codable, Hashable {
    var kind: String?
    var ship: String?
    var shipClass: String?
    var sailDate: String?
    var nights: Int?
    var port: String?
    var roundTrip: Bool?
    var region: String?
    var cabin: String?
    var cabinName: String?
    var oceanViewConfirmed: Bool?
    var pricePP: Int?
    var priceIncludesTaxes: Bool?
    var usualPP: Int?
    var previousPP: Int?
    var lowestSeenPP: Int?
    var perNightPP: Int?
    var totalFor3: Int?
    var totalAssumes: String?
    var score: Int?
    var scoreLabel: String?
    var why: String?
    var breaks: String?
    var flight: String?
    var perks: [String]?
    var bookBy: String?
    var bookByWhat: String?
    var link: String?
    var linkLabel: String?
    var sources: [DealSource]?
    var ports: [String]?
    var nearby: String?
    var scoreHow: String?
    var notes: String?
    var offers: [OfferRow]?
    var endsAt: String?
    var postedAt: String?
    var changedAt: String?
    // v2: the summary sheet and the scoop
    var returnDate: String?
    var stops: [String]?
    var typicalPP: Int?
    var lowPP: Int?
    var highPP: Int?
    var pctUnderTypical: Int?
    var cabinOptions: [CabinOption]?
    var itineraryDays: [ItineraryDay]?
    var scoop: String?
    var fitsTrip: Bool?
    var failsBecause: [String]?
}

struct Deal: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: DealData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(DealData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
    }

    init(id: String, data: DealData) {
        self.id = id
        self.version = 1
        self.data = data
    }

    var kind: DealKind? { data.kind.flatMap { DealKind(rawValue: $0) } }
    var title: String { (data.ship?.isEmpty == false ? data.ship : nil) ?? "Deal" }
    var posted: Date { Fmt.timestamp(data.postedAt) ?? .distantPast }
    /// Latest of first posted and last material change (price etc.); "Newest" sorts by this.
    var latest: Date { max(posted, Fmt.timestamp(data.changedAt) ?? .distantPast) }
    var sailDay: Date? { Fmt.day(data.sailDate) }
    var bookByDay: Date? { Fmt.day(data.bookBy) }
    var endsDay: Date? { Fmt.day(data.endsAt) }
    var cabinType: CabinType? { data.cabin.flatMap { CabinType(rawValue: $0) } }
    var cabinTitle: String? { cabinType?.title ?? data.cabinName }
    var link: URL? { Fmt.webURL(data.link) }

    var dateRange: String? {
        guard let start = sailDay else { return nil }
        return Fmt.range(from: start, nights: data.nights ?? 0)
    }

    /// "7 nights · Oct 15–22, 2028 · Galveston"
    var tripLine: String {
        var parts: [String] = []
        if let nights = data.nights { parts.append(Fmt.nights(nights)) }
        if let range = dateRange { parts.append(range) }
        if let port = data.port, !port.isEmpty { parts.append(port) }
        return parts.joined(separator: " · ")
    }

    /// Per-person fall in price, when the old price is known and higher.
    var dropPP: Int? {
        guard let previous = data.previousPP, let now = data.pricePP, previous > now else { return nil }
        return previous - now
    }

    // MARK: v2 summary sheet

    var shipClass: ShipClass? { data.shipClass.flatMap { ShipClass(rawValue: $0) } }

    /// The typical price per person: v2 `typicalPP`, or v1 `usualPP` on older deals.
    var typicalPP: Int? { data.typicalPP ?? data.usualPP }

    /// The exact category when the source names it ("Ocean View Balcony"), else the cabin type ("Balcony").
    var cabinLabel: String? {
        if let name = data.cabinName?.trimmed, !name.isEmpty { return name }
        return cabinTitle
    }

    /// Last day of the trip: `returnDate`, else the sail date plus the nights.
    var returnDay: Date? {
        if let day = Fmt.day(data.returnDate) { return day }
        guard let start = sailDay, let nights = data.nights, nights > 0 else { return nil }
        return Fmt.adding(days: nights, to: start)
    }

    /// "Sun Sep 5 – Sat Sep 11, 2027"
    var dates: String? {
        guard let start = sailDay else { return nil }
        return Fmt.tripDates(from: start, to: returnDay)
    }

    /// "Sun Sep 5 – Sat Sep 11, 2027 · 6 nights"
    var datesLine: String {
        [dates, data.nights.map { Fmt.nights($0) }].compactMap { $0 }.joined(separator: " · ")
    }

    /// The ports of call in order: v2 `stops`, else v1 `ports`; sea days and the embark/return port left out.
    var portsOfCall: [String] {
        let raw = (data.stops?.isEmpty == false ? data.stops : nil) ?? data.ports ?? []
        var list = raw.map { $0.trimmed }.filter { !$0.isEmpty && !Deal.isSeaDay($0) }
        if let from = data.port?.trimmed, !from.isEmpty, let first = list.first, Deal.samePlace(first, from) {
            list.removeFirst()
        }
        if let back = returnPort, let last = list.last, Deal.samePlace(last, back) {
            list.removeLast()
        }
        return list
    }

    /// Where the trip ends: the embark port for a round trip, else the last port of the itinerary.
    var returnPort: String? {
        if data.roundTrip == true { return data.port }
        let days = (data.itineraryDays ?? []).compactMap { $0.port?.trimmed }
        if let last = days.last(where: { !$0.isEmpty && !Deal.isSeaDay($0) }) { return last }
        return data.roundTrip == false ? nil : data.port
    }

    /// "Galveston → Cozumel · Roatán · Costa Maya → Galveston": embark port, stops in order, return port.
    var route: String? {
        let stops = portsOfCall
        guard let from = data.port?.trimmed, !from.isEmpty else {
            return stops.isEmpty ? nil : stops.joined(separator: " · ")
        }
        if stops.isEmpty {
            if data.roundTrip == true { return "\(from) round trip" }
            if let back = returnPort, !Deal.samePlace(back, from) { return "\(from) → \(back)" }
            return from
        }
        var line = "\(from) → \(stops.joined(separator: " · "))"
        if let back = returnPort, !back.isEmpty { line += " → \(back)" }
        return line
    }

    /// Percent under the typical price (negative = over): the deal's own figure, else worked out from typical.
    var pctUnder: Int? {
        if let pct = data.pctUnderTypical { return pct }
        guard let typical = typicalPP, typical > 0, let price = data.pricePP, price > 0 else { return nil }
        return Int((Double(typical - price) / Double(typical) * 100).rounded())
    }

    /// The price meter: this price against low / typical / high for that ship and cabin type.
    struct PriceRange: Hashable {
        let price: Int
        let low: Int?
        let typical: Int?
        let high: Int?

        /// The ends of the bar: every known point fits inside.
        var bounds: (lo: Int, hi: Int) {
            let points = [price, low, typical, high].compactMap { $0 }
            let lo = points.min() ?? price
            let hi = points.max() ?? price
            return (lo, max(hi, lo + 1))
        }

        func fraction(_ value: Int) -> Double {
            let b = bounds
            return min(max(Double(value - b.lo) / Double(b.hi - b.lo), 0), 1)
        }
    }

    var priceRange: PriceRange? {
        guard data.kind != DealKind.sale.rawValue, let price = data.pricePP, price > 0 else { return nil }
        let low = data.lowPP ?? data.lowestSeenPP
        let typical = typicalPP
        let high = data.highPP
        if low == nil && typical == nil && high == nil { return nil }
        return PriceRange(price: price, low: low, typical: typical, high: high)
    }

    /// For sorting and the budget check: the family total, else per person x 3 (a screen, not a quote).
    var totalEstimate: Int? {
        if let total = data.totalFor3, total > 0 { return total }
        if let pp = data.pricePP, pp > 0 { return pp * 3 }
        return nil
    }

    static func isSeaDay(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("at sea") || lower.contains("sea day") || lower.hasPrefix("cruising")
    }

    /// "Galveston" and "Galveston, Texas" are the same place.
    static func samePlace(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased().trimmed
        let y = b.lowercased().trimmed
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.hasPrefix(y + ",") || y.hasPrefix(x + ",")
    }
}

// MARK: - Questions (Ask Deal Desk)

struct QuestionSource: Codable, Hashable {
    var name: String?
    var url: String?
}

/// `questions/<id>`: the app writes `dealId?`, `text`, `askedAt`; the answerer writes `answer`, `answeredAt`,
/// `sources`.
struct QuestionData: Codable, Hashable {
    var dealId: String?
    var text: String?
    var askedAt: String?
    var answer: String?
    var answeredAt: String?
    var sources: [QuestionSource]?
}

struct Question: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: QuestionData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(QuestionData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
    }

    var text: String { data.text ?? "" }
    var asked: Date { Fmt.timestamp(data.askedAt) ?? .distantPast }
    var answer: String? { (data.answer?.trimmed.isEmpty == false) ? data.answer : nil }
    var isAnswered: Bool { answer != nil }
    var answered: Date? { Fmt.timestamp(data.answeredAt) }
}

/// One row of `GET /v1/deals/{id}/history`, for the sparkline.
struct PricePoint: Codable, Hashable {
    var pricePP: Int
    var cabin: String?
    var source: String?
    var seenAt: String

    var seen: Date? { Fmt.timestamp(seenAt) }
}

// MARK: - Answers (feedback)

enum Verdict: String, CaseIterable, Identifiable {
    case interested, pass, later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interested: return "Interested"
        case .pass: return "Not for me"
        case .later: return "Later"
        }
    }

    var groupTitle: String {
        switch self {
        case .interested: return "Interested"
        case .pass: return "Passed"
        case .later: return "Later"
        }
    }

    var symbol: String {
        switch self {
        case .interested: return "hand.thumbsup.fill"
        case .pass: return "hand.thumbsdown.fill"
        case .later: return "clock.fill"
        }
    }

    var optionsTitle: String {
        switch self {
        case .interested: return "What next?"
        case .pass: return "Why not?"
        case .later: return ""
        }
    }

    /// Reason chips. Ids are what the server stores; titles are what Jim reads.
    var options: [ReasonOption] {
        switch self {
        case .pass:
            return [
                ReasonOption(id: "price", title: "Price"),
                ReasonOption(id: "cabin", title: "Cabin"),
                ReasonOption(id: "ship", title: "Ship"),
                ReasonOption(id: "route", title: "Route"),
                ReasonOption(id: "port", title: "Port"),
                ReasonOption(id: "length", title: "Length"),
                ReasonOption(id: "dates", title: "Dates"),
                ReasonOption(id: "flight", title: "Flight"),
                ReasonOption(id: "trust", title: "Don't trust it"),
                ReasonOption(id: "other", title: "Other"),
            ]
        case .interested:
            return [
                ReasonOption(id: "watch", title: "Watch the price"),
                ReasonOption(id: "details", title: "More details"),
                ReasonOption(id: "booking", title: "Ready to book"),
                ReasonOption(id: "similar", title: "Find similar"),
            ]
        case .later:
            return []
        }
    }

    static func reasonTitle(_ id: String) -> String {
        for verdict in Verdict.allCases {
            if let match = verdict.options.first(where: { $0.id == id }) { return match.title }
        }
        return id.capitalized
    }
}

struct ReasonOption: Hashable, Identifiable {
    let id: String
    let title: String
}

struct FeedbackData: Codable, Hashable {
    var dealId: String?
    var verdict: String?
    var reasons: [String]?
    var note: String?
    var updatedAt: String?
    var claudeReadAt: String?
    var claudeReply: String?
}

struct Feedback: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: FeedbackData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(FeedbackData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
    }

    var verdict: Verdict? { data.verdict.flatMap { Verdict(rawValue: $0) } }
    var updated: Date { Fmt.timestamp(data.updatedAt) ?? .distantPast }
    /// Claude's reply, shown only while it answers the current answer (Claude read it after the last change).
    var reply: String? {
        guard let text = data.claudeReply, !text.isEmpty else { return nil }
        if let read = Fmt.timestamp(data.claudeReadAt), let changed = Fmt.timestamp(data.updatedAt), read < changed {
            return nil
        }
        return text
    }
}

// MARK: - Rules

enum RuleStatus: String {
    case active, proposed, paused, declined
}

struct RuleData: Codable, Hashable {
    var text: String?
    var unless: String?
    var status: String?
    var origin: String?
    var why: String?
    var question: String?
    var fromDeal: String?
    var createdAt: String?
    var updatedAt: String?
}

struct Rule: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: RuleData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(RuleData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
    }

    var status: RuleStatus? { data.status.flatMap { RuleStatus(rawValue: $0) } }
    var text: String { data.text ?? "" }
    var created: Date { Fmt.timestamp(data.createdAt) ?? .distantPast }
    var fromClaude: Bool { data.origin == "claude" }
}

// MARK: - Plays (ways to save)

struct PlayData: Codable, Hashable {
    var kind: String?
    var title: String?
    var who: String?
    var saves: String?
    var how: String?
    var stacks: String?
    var catchText: String?
    var deadline: String?
    var deadlineWhat: String?
    var fit: String?
    var link: String?
    var linkLabel: String?
    var addedAt: String?

    enum CodingKeys: String, CodingKey {
        case kind, title, who, saves, how, stacks
        case catchText = "catch"
        case deadline, deadlineWhat, fit, link, linkLabel, addedAt
    }
}

struct Play: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: PlayData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(PlayData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
    }

    init(id: String, data: PlayData) {
        self.id = id
        self.version = 1
        self.data = data
    }

    var isLive: Bool { data.kind == "now" }
    var title: String { data.title ?? "Way to save" }
    var deadlineDay: Date? { Fmt.day(data.deadline) }
    var added: Date { Fmt.timestamp(data.addedAt) ?? .distantPast }
    var link: URL? { Fmt.webURL(data.link) }
}

enum PlayNoteStatus: String, CaseIterable, Identifiable {
    case using, question, skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .using: return "Using it"
        case .question: return "Question"
        case .skip: return "Skip"
        }
    }

    var tag: String {
        switch self {
        case .using: return "Using"
        case .question: return "Asked"
        case .skip: return "Skipped"
        }
    }
}

struct PlayNoteData: Codable, Hashable {
    var status: String?
    var note: String?
    var updatedAt: String?
    var claudeReply: String?
}

struct PlayNote: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: PlayNoteData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(PlayNoteData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
    }

    var status: PlayNoteStatus? { data.status.flatMap { PlayNoteStatus(rawValue: $0) } }
    var reply: String? { (data.claudeReply?.isEmpty == false) ? data.claudeReply : nil }
}

// MARK: - Meta and watchlist

/// `meta/status` and `meta/profile` share one decoder; each uses its own fields.
struct MetaData: Codable, Hashable {
    var lastRun: String?
    var ok: Bool?
    var sourcesWorked: [String]?
    var sourcesFailed: [String]?
    var sailingsChecked: Int?
    var newItems: Int?
    var summary: String?
    var error: String?
    var lines: [String]?
}

struct RunStatus: Hashable {
    let data: MetaData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(MetaData.self) else { return nil }
        data = decoded
    }

    init(data: MetaData) {
        self.data = data
    }

    var lastRun: Date? { Fmt.timestamp(data.lastRun) }
    var failed: Bool { data.ok == false }
    var worked: [String] { data.sourcesWorked ?? [] }
    var failedSources: [String] { data.sourcesFailed ?? [] }
}

struct WatchData: Codable, Hashable {
    var ship: String?
    var sailDate: String?
    var nights: Int?
    var port: String?
    var cabin: String?
    var nowPP: Int?
    var lowestSeenPP: Int?
    var lowestSeenAt: String?
    var source: String?
    var why: String?
}

struct WatchItem: Identifiable, Hashable {
    let id: String
    let data: WatchData

    init?(raw: RawDoc) {
        guard let decoded = raw.data.decode(WatchData.self) else { return nil }
        id = raw.id
        data = decoded
    }

    var sailDay: Date? { Fmt.day(data.sailDate) }
}
