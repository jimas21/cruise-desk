import Foundation

// MARK: - v5 feature flags (CONTRACT_V5 rule 0.8)

/// A v5 part turns on only when `GET /v1/catalog` says apiVersion 5 or more and lists its name. Otherwise the v4
/// behaviour stays.
enum V5Feature: String, CaseIterable, Hashable {
    case catalog5, explain, collect, reference, sheet, flights
}

extension Catalog {
    var isV5: Bool { (apiVersion ?? 0) >= 5 }

    func has(_ feature: V5Feature) -> Bool {
        isV5 && (features ?? []).contains(feature.rawValue)
    }
}

/// Any key, for reading a field that has more than one spelling ("lengthFt" or "length_ft").
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer {
    /// A number at `key`, whole or not; nil when missing, null or not a number.
    func number(_ key: Key) -> Double? {
        if let value = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return value }
        if let value = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return Double(value) }
        return nil
    }

    /// A whole number at `key`, also from a number sent with a decimal point.
    func whole(_ key: Key) -> Int? {
        if let value = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return value }
        if let value = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil, value.isFinite, abs(value) < 1e12 {
            return Int(value.rounded())
        }
        return nil
    }

    /// A list where one odd entry is skipped instead of hiding the rest.
    func list<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        lenient(LenientList<T>.self, key)?.items
    }
}

extension KeyedDecodingContainer where Key == AnyKey {
    /// The first of several spellings that holds a number.
    func number(_ names: [String]) -> Double? {
        for name in names {
            if let value = number(AnyKey(name)) { return value }
        }
        return nil
    }
}

/// Decodes a JSON array, skipping the entries that do not decode.
struct LenientList<T: Decodable>: Decodable {
    var items: [T]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [T] = []
        while !container.isAtEnd {
            if let value = try? container.decode(T.self) {
                out.append(value)
            } else if (try? container.decode(JSONValue.self)) == nil {
                break
            }
        }
        items = out
    }
}

// MARK: - Catalog v3 additions (CONTRACT_V5 section 1.3)

/// One region of the closed list, matched by key, name or alias. A filter on a parent matches its children.
struct CatalogRegion: Codable, Hashable, Identifiable {
    var key: String
    var name: String
    var parent: String?
    var aliases: [String]?
    var sailings: Int?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, parent, aliases, sailings
    }

    init(key: String, name: String, parent: String? = nil, aliases: [String]? = nil, sailings: Int? = nil) {
        self.key = key
        self.name = name
        self.parent = parent
        self.aliases = aliases
        self.sailings = sailings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = c.lenient(String.self, .key)?.trimmed ?? ""
        let name = c.lenient(String.self, .name)?.trimmed ?? ""
        guard !key.isEmpty || !name.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: c, debugDescription: "A region needs a key or name")
        }
        self.key = key.isEmpty ? Slug.plain(name) : key
        self.name = name.isEmpty ? Words.title(fromSlug: key) : name
        parent = c.lenient(String.self, .parent).flatMap { $0.trimmed.isEmpty ? nil : $0.trimmed }
        aliases = c.lenient([String].self, .aliases)
        sailings = c.whole(.sailings)
    }

    /// Does `text` name this region (key, name or alias, ignoring case and accents)?
    func named(_ text: String) -> Bool {
        let wanted = Slug.plain(text)
        guard !wanted.isEmpty else { return false }
        if wanted == key || wanted == Slug.plain(name) { return true }
        return (aliases ?? []).contains { Slug.plain($0) == wanted }
    }
}

/// Where the For-my-trip line filter comes from: never saved (Royal only), saved, or every line.
struct LinesState: Codable, Hashable {
    var trip: String?
    var effective: [String]?

    enum CodingKeys: String, CodingKey {
        case trip, effective
    }

    init(trip: String?, effective: [String]?) {
        self.trip = trip
        self.effective = effective
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trip = c.lenient(String.self, .trip)
        effective = c.lenient([String].self, .effective)
    }

    /// Jim never saved his lines, so only Royal Caribbean shows (the v3 default made visible).
    var isLegacyDefault: Bool { trip == "legacy_default" }
}

/// What one source lists for a line (`lines[].sources` in the catalog).
struct CatalogLineSource: Codable, Hashable {
    var source: String?
    var listed: Int?
    var ships: [String]?

    enum CodingKeys: String, CodingKey {
        case source, listed, ships
    }

    init(source: String?, listed: Int?, ships: [String]?) {
        self.source = source
        self.listed = listed
        self.ships = ships
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.lenient(String.self, .source)
        listed = c.whole(.listed)
        ships = c.lenient([String].self, .ships)
    }
}

/// A top region and its children ("Caribbean" > Western, Eastern, Southern).
struct RegionNode: Hashable, Identifiable {
    let region: CatalogRegion
    let children: [CatalogRegion]
    var id: String { region.key }
}

extension Catalog {
    /// The region tree, parents first then their children, in the server's order.
    var regionTree: [RegionNode] {
        let all = regions ?? []
        let keys = Set(all.map { $0.key })
        let tops = all.filter { $0.parent == nil || !keys.contains($0.parent ?? "") }
        return tops.map { top in RegionNode(region: top, children: all.filter { $0.parent == top.key }) }
    }

    /// The region `text` names, if any.
    func region(named text: String?) -> CatalogRegion? {
        guard let text = text?.trimmed, !text.isEmpty else { return nil }
        return (regions ?? []).first { $0.named(text) }
    }

    /// Does a filter on `place` (a region) take a sailing in `region`? A parent takes its children.
    func region(_ place: String, contains region: String?) -> Bool {
        guard let region = region?.trimmed, !region.isEmpty else { return false }
        if Slug.plain(place) == Slug.plain(region) { return true }
        guard let wanted = self.region(named: place) else { return false }
        if wanted.named(region) { return true }
        guard let actual = self.region(named: region) else { return false }
        return actual.parent == wanted.key
    }
}

/// Does a Deals filter `place` (a port or a region) take this deal?
enum PlaceMatch {
    static func matches(_ place: String, port: String?, region: String?, catalog: Catalog = CatalogIndex.current) -> Bool {
        if let port = port?.trimmed, !port.isEmpty, Deal.samePlace(place, port) { return true }
        if let region = region?.trimmed, !region.isEmpty {
            if Deal.samePlace(place, region) { return true }
            if catalog.region(place, contains: region) { return true }
        }
        return false
    }
}

// MARK: - Catalog ports (`GET /v1/catalog/ports`)

/// The kind of place a port picker asks for: embark (= embark or both), call (= call or both), visit (= call, both
/// or scenic: every place a sailing stops at or cruises past, so Glacier Bay can be picked), or any.
enum PortKind: String {
    case embark, call, scenic, visit, any

    /// Does a catalog port of `kind` belong in this picker? (The same rule the server applies.)
    func admits(_ kind: String?) -> Bool {
        switch self {
        case .embark: return kind == "embark" || kind == "both"
        case .call: return kind == "call" || kind == "both"
        case .scenic: return kind == "scenic"
        case .visit: return kind == "call" || kind == "both" || kind == "scenic"
        case .any: return true
        }
    }
}

struct CatalogPort: Decodable, Hashable, Identifiable {
    var key: String
    var name: String
    var country: String?
    var region: String?
    var kind: String?
    var airports: [String]?
    var sailings: Int?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, country, region, kind, airports, sailings
    }

    init(key: String, name: String, country: String? = nil, region: String? = nil, kind: String? = nil,
         airports: [String]? = nil, sailings: Int? = nil) {
        self.key = key
        self.name = name
        self.country = country
        self.region = region
        self.kind = kind
        self.airports = airports
        self.sailings = sailings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = c.lenient(String.self, .name)?.trimmed ?? ""
        guard !name.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "A port needs a name")
        }
        self.name = name
        key = c.lenient(String.self, .key)?.trimmed ?? Slug.plain(name)
        country = c.lenient(String.self, .country)
        region = c.lenient(String.self, .region)
        kind = c.lenient(String.self, .kind)
        airports = c.lenient([String].self, .airports)
        sailings = c.whole(.sailings)
    }

    /// "United States · Alaska · 18 sailings"
    var detail: String {
        var parts: [String] = []
        if let country = country?.trimmed, !country.isEmpty { parts.append(country) }
        if let region = region?.trimmed, !region.isEmpty {
            parts.append(CatalogIndex.current.region(named: region)?.name ?? region)
        }
        if kind == "scenic" { parts.append("scenic cruising") }
        if let sailings {
            parts.append(sailings == 1 ? "1 sailing" : "\(sailings) sailings")
        }
        return parts.joined(separator: " · ")
    }

    /// The array the server sends, or `{ports: [...]}`.
    static func list(from data: Data) -> [CatalogPort] {
        if let rows = try? JSONDecoder().decode(LenientList<CatalogPort>.self, from: data) { return rows.items }
        struct Wrapped: Decodable {
            var ports: LenientList<CatalogPort>?
        }
        return (try? JSONDecoder().decode(Wrapped.self, from: data))?.ports?.items ?? []
    }
}

// MARK: - What is collected (`GET /v1/collect`, `prefs/collect`; CONTRACT_V5 section 1.2)

/// `prefs/collect`: the lines Deal Desk gathers prices for, on top of Royal Caribbean and My Lines.
struct CollectPrefs: Equatable {
    var lines: [String] = []
    var every = false
    var updatedAt: String? = nil

    init(lines: [String] = [], every: Bool = false, updatedAt: String? = nil) {
        self.lines = lines
        self.every = every
        self.updatedAt = updatedAt
    }

    init?(raw: RawDoc) {
        guard case .object = raw.data else { return nil }
        lines = raw.data.field("lines")?.stringList ?? []
        if case .bool(let on)? = raw.data.field("every") { every = on }
        updatedAt = raw.data.field("updatedAt")?.stringValue
    }

    /// Unique, at most 12, never "Other".
    func cleaned() -> CollectPrefs {
        var out: [String] = []
        for name in lines {
            guard let line = CruiseLine.canonical(name), !CruiseLine.same(line, CruiseLine.other),
                  !out.contains(where: { CruiseLine.same($0, line) }) else { continue }
            out.append(line.capped(30))
        }
        return CollectPrefs(lines: Array(out.prefix(12)), every: every, updatedAt: updatedAt)
    }

    func fields(stamp: String = Fmt.stamp()) -> [String: JSONValue] {
        let clean = cleaned()
        return ["lines": .array(clean.lines.map { JSONValue.string($0) }), "every": .bool(clean.every),
                "updatedAt": .string(stamp)]
    }

    func has(_ line: String) -> Bool { lines.contains { CruiseLine.same($0, line) } }
}

struct CollectSource: Decodable, Hashable {
    var source: String?
    var listed: Int?
    var collected: Int?
    var ships: [String]?
    var passDays: Int?

    enum CodingKeys: String, CodingKey {
        case source, listed, collected, ships, passDays
    }

    init(source: String?, listed: Int?, collected: Int?, ships: [String]? = nil, passDays: Int? = nil) {
        self.source = source
        self.listed = listed
        self.collected = collected
        self.ships = ships
        self.passDays = passDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.lenient(String.self, .source)
        listed = c.whole(.listed)
        collected = c.whole(.collected)
        ships = c.lenient([String].self, .ships)
        passDays = c.whole(.passDays)
    }
}

/// One line's collection state: collecting, queued, not collected, or no source we read lists it.
struct CollectLine: Decodable, Hashable {
    var line: String?
    var state: String?
    var why: [String]?
    var tier: String?
    var sources: [CollectSource]?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case line, state, why, tier, sources, note
    }

    init(line: String?, state: String?, why: [String]? = nil, tier: String? = nil, sources: [CollectSource]? = nil,
         note: String? = nil) {
        self.line = line
        self.state = state
        self.why = why
        self.tier = tier
        self.sources = sources
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = c.lenient(String.self, .line)
        state = c.lenient(String.self, .state)
        why = c.lenient([String].self, .why)
        tier = c.lenient(String.self, .tier)
        sources = c.list(CollectSource.self, .sources)
        note = c.lenient(String.self, .note)
    }

    var collected: Int { (sources ?? []).compactMap { $0.collected }.reduce(0, +) }

    var passDays: Int? { (sources ?? []).compactMap { $0.passDays }.filter { $0 > 0 }.min() }

    /// "collecting · 412 sailings", "queued · first results in about 1 day", "no source we read lists this line".
    var stateText: String {
        switch state ?? "" {
        case "collecting":
            return collected == 1 ? "collecting · 1 sailing" : "collecting · \(collected) sailings"
        case "queued":
            if let days = passDays { return "queued · first results in about \(days == 1 ? "1 day" : "\(days) days")" }
            return "queued · first results soon"
        case "not_collected":
            return "not collected"
        case "no_source":
            return "no source we read lists this line"
        case "":
            return "not known yet"
        default:
            return Words.humanize(state ?? "").lowercased()
        }
    }

    /// Why Deal Desk collects it: "always", "My Lines", "Collect prices for", "a plan", "a tracked sailing".
    var whyText: String? {
        let words = (why ?? []).map { reason -> String in
            switch reason {
            case "always": return "always"
            case "trip": return "My Lines"
            case "collect": return "Collect prices for"
            case "plan": return "a watched plan"
            case "tracked": return "a tracked sailing"
            case "every": return "every line"
            default: return Words.humanize(reason).lowercased()
            }
        }
        return words.isEmpty ? nil : words.joined(separator: ", ")
    }
}

struct CollectState: Decodable, Hashable {
    var linesState: LinesState?
    var lines: [CollectLine]
    var generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case linesState, lines, generatedAt
    }

    init(linesState: LinesState?, lines: [CollectLine], generatedAt: String? = nil) {
        self.linesState = linesState
        self.lines = lines
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        linesState = c.lenient(LinesState.self, .linesState)
        lines = c.list(CollectLine.self, .lines) ?? []
        generatedAt = c.lenient(String.self, .generatedAt)
    }

    func line(_ name: String) -> CollectLine? {
        lines.first { CruiseLine.same(CruiseLine.resolved($0.line), name) }
    }
}

// MARK: - Search explanations (CONTRACT_V5 section 1.6)

/// One step of the funnel: how many sailings were left after it ("Disney 289", "Alaska 0").
struct FunnelStep: Decodable, Hashable {
    var step: String?
    var label: String?
    var remaining: Int?

    enum CodingKeys: String, CodingKey {
        case step, label, remaining
    }

    init(step: String?, label: String?, remaining: Int?) {
        self.step = step
        self.label = label
        self.remaining = remaining
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        step = c.lenient(String.self, .step)
        label = c.lenient(String.self, .label)
        remaining = c.whole(.remaining)
    }

    /// "Disney 289", or the step and its count when the server sent no label.
    var text: String {
        if let label = label?.trimmed, !label.isEmpty { return label }
        let name = Words.humanize(step ?? "step")
        return remaining.map { "\(name) \($0)" } ?? name
    }
}

/// Why a requested line came back with no (or few) rows, with the one thing to do about it.
struct CoverageGap: Decodable, Hashable {
    var line: String?
    var reason: String?
    var ships: [String]?
    var region: String?
    var note: String?
    var action: String?

    enum CodingKeys: String, CodingKey {
        case line, reason, ships, region, note, action
    }

    init(line: String?, reason: String?, ships: [String]? = nil, region: String? = nil, note: String? = nil,
         action: String? = nil) {
        self.line = line
        self.reason = reason
        self.ships = ships
        self.region = region
        self.note = note
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = c.lenient(String.self, .line)
        reason = c.lenient(String.self, .reason)
        ships = c.lenient([String].self, .ships)
        region = c.lenient(String.self, .region)
        note = c.lenient(String.self, .note)
        action = c.lenient(String.self, .action)
    }

    var lineName: String { CruiseLine.resolved(line) }

    /// The words for the reason, when the server sent no note.
    var reasonText: String {
        switch reason ?? "" {
        case "not_collected": return "Deal Desk doesn't collect \(lineName) prices yet."
        case "collecting": return "Deal Desk started collecting \(lineName); the first results are on their way."
        case "no_source_for_ships":
            let names = (ships ?? []).joined(separator: " or ")
            return names.isEmpty ? "No source we read lists these \(lineName) ships."
                                 : "No source we read lists \(names)."
        case "no_source": return "No source we read lists \(lineName)."
        case "stale": return "No source has shown these \(lineName) sailings in 45 days."
        case "filtered": return "\(lineName) has sailings, but the filters left none."
        default: return Words.humanize(reason ?? "")
        }
    }
}

/// The trip cost on a search row (from the sheet): "$5,980–7,240" and the verdict word.
struct TripCost: Codable, Hashable {
    var low: Int?
    var high: Int?
    var complete: Bool?
    var verdict: String?

    enum CodingKeys: String, CodingKey {
        case low, high, complete, verdict
    }

    init(low: Int?, high: Int?, complete: Bool?, verdict: String?) {
        self.low = low
        self.high = high
        self.complete = complete
        self.verdict = verdict
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        low = c.whole(.low)
        high = c.whole(.high)
        complete = c.lenient(Bool.self, .complete)
        // `verdict` is the label; a server may send the whole verdict object instead.
        if let label = c.lenient(String.self, .verdict) {
            verdict = label
        } else {
            verdict = c.lenient(SheetVerdict.self, .verdict)?.label
        }
    }

    var range: String? { Money.range(low, high, compact: true) }
}

// MARK: - Money and party wording

enum Money {
    /// "$5,980 – $7,240", one figure when the ends match, "up to $1,650" with no low end. `compact` drops the
    /// second dollar sign: "$5,980–7,240".
    static func range(_ low: Int?, _ high: Int?, compact: Bool = false) -> String? {
        switch (low, high) {
        case let (low?, high?) where low == high: return Fmt.usd(low)
        case let (low?, high?):
            let a = min(low, high), b = max(low, high)
            if compact { return "\(Fmt.usd(a))–\(Fmt.usd(b).replacingOccurrences(of: "$", with: ""))" }
            return "\(Fmt.usd(a)) – \(Fmt.usd(b))"
        case let (low?, nil): return Fmt.usd(low)
        case let (nil, high?): return "up to \(Fmt.usd(high))"
        case (nil, nil): return nil
        }
    }
}

enum PartyText {
    /// The party the screens talk about, set from the trip settings by the Store. nil when unknown.
    static var current: (adults: Int, children: Int)? = nil

    /// "2 adults + 1 child", "1 adult", "2 adults + 2 children".
    static func words(adults: Int, children: Int) -> String {
        let a = max(adults, 0), c = max(children, 0)
        var text = a == 1 ? "1 adult" : "\(a) adults"
        if c > 0 { text += c == 1 ? " + 1 child" : " + \(c) children" }
        return text
    }

    /// "for 3" when the party is known (adults plus children), else "for the party". Never a fixed number.
    static var unit: String {
        guard let party = current else { return "for the party" }
        return "for \(max(party.adults + party.children, 1))"
    }

    /// The guests in the party, 3 when nothing is known (the brain's long-standing assumption, only as a screen).
    static var guests: Int {
        guard let party = current else { return 3 }
        return max(party.adults + party.children, 1)
    }
}

// MARK: - The deal sheet (CONTRACT_V5 section 2)

/// Where a money figure came from. A basis this version does not know is shown as it is, neutrally.
enum MoneyBasis: Equatable {
    case read, rule, estimate, included, notShown
    case unknown(String)

    init(_ raw: String?) {
        switch raw?.trimmed ?? "" {
        case "read": self = .read
        case "rule": self = .rule
        case "estimate": self = .estimate
        case "included": self = .included
        case "not_shown", "notShown": self = .notShown
        default: self = .unknown(raw ?? "")
        }
    }

    var title: String {
        switch self {
        case .read: return "read"
        case .rule: return "rule"
        case .estimate: return "estimate"
        case .included: return "included"
        case .notShown: return "not shown"
        case .unknown(let raw): return raw.isEmpty ? "source not stated" : Words.humanize(raw).lowercased()
        }
    }
}

/// BOOK, WAIT, SKIP or YOUR CALL. An unknown label is shown as it is.
enum VerdictWord: Equatable {
    case book, wait, skip, yourCall
    case unknown(String)

    init(_ raw: String?) {
        switch (raw ?? "").trimmed.uppercased() {
        case "BOOK": self = .book
        case "WAIT": self = .wait
        case "SKIP": self = .skip
        case "YOUR_CALL", "YOUR CALL": self = .yourCall
        default: self = .unknown(raw ?? "")
        }
    }

    var title: String {
        switch self {
        case .book: return "BOOK"
        case .wait: return "WAIT"
        case .skip: return "SKIP"
        case .yourCall: return "YOUR CALL"
        case .unknown(let raw): return raw.isEmpty ? "NO VERDICT" : Words.humanize(raw).uppercased()
        }
    }

    var spoken: String {
        switch self {
        case .book: return "Book"
        case .wait: return "Wait"
        case .skip: return "Skip"
        case .yourCall: return "Your call"
        case .unknown(let raw): return raw.isEmpty ? "No verdict" : Words.humanize(raw)
        }
    }
}

struct SheetParty: Decodable, Hashable {
    var adults: Int?
    var children: Int?
    var childAges: [Int]?
    /// The children's ages on the sailing date, worked out by the server from their birth months. The only age to
    /// show for a future sailing (the stored `childAges` is today's).
    var agesOnSailing: [Int]?
    var guests: Int?
    var childAgesKnown: Bool?

    enum CodingKeys: String, CodingKey {
        case adults, children, childAges, agesOnSailing, guests, childAgesKnown
    }

    init(adults: Int?, children: Int?, childAges: [Int]? = nil, agesOnSailing: [Int]? = nil, guests: Int? = nil,
         childAgesKnown: Bool? = nil) {
        self.adults = adults
        self.children = children
        self.childAges = childAges
        self.agesOnSailing = agesOnSailing
        self.guests = guests
        self.childAgesKnown = childAgesKnown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adults = c.whole(.adults)
        children = c.whole(.children)
        childAges = c.lenient([Int].self, .childAges)
        agesOnSailing = c.lenient([Int].self, .agesOnSailing)
        guests = c.whole(.guests)
        childAgesKnown = c.lenient(Bool.self, .childAgesKnown)
    }

    /// "2 adults + 1 child"
    var words: String? {
        guard let adults else { return guests.map { $0 == 1 ? "1 guest" : "\($0) guests" } }
        return PartyText.words(adults: adults, children: children ?? 0)
    }

    /// "age 10 on the sailing", "ages 10 and 7 on the sailing": only from `agesOnSailing`, never today's ages.
    var agesText: String? {
        let ages = (agesOnSailing ?? []).filter { (0...17).contains($0) }
        guard !ages.isEmpty, ages.count == (agesOnSailing ?? []).count else { return nil }
        let list = ListText.join(ages.map { String($0) })
        return ages.count == 1 ? "age \(list) on the sailing" : "ages \(list) on the sailing"
    }
}

/// One money line of the trip cost.
struct SheetLine: Decodable, Hashable, Identifiable {
    var key: String
    var label: String?
    var amount: Int?
    var low: Int?
    var high: Int?
    var basis: String?
    var detail: String?
    var source: String?
    var asOf: String?
    var counted: Bool?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, amount, low, high, basis, detail, source, asOf, counted
    }

    init(key: String, label: String?, amount: Int? = nil, low: Int? = nil, high: Int? = nil, basis: String?,
         detail: String? = nil, source: String? = nil, asOf: String? = nil, counted: Bool? = true) {
        self.key = key
        self.label = label
        self.amount = amount
        self.low = low
        self.high = high
        self.basis = basis
        self.detail = detail
        self.source = source
        self.asOf = asOf
        self.counted = counted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(String.self, .key) ?? UUID().uuidString
        label = c.lenient(String.self, .label)
        amount = c.whole(.amount)
        low = c.whole(.low)
        high = c.whole(.high)
        basis = c.lenient(String.self, .basis)
        detail = c.lenient(String.self, .detail)
        source = c.lenient(String.self, .source)
        asOf = c.lenient(String.self, .asOf)
        counted = c.lenient(Bool.self, .counted)
    }

    var basisValue: MoneyBasis { MoneyBasis(basis) }

    var title: String {
        if let label = label?.trimmed, !label.isEmpty { return label }
        return Words.humanize(key.replacingOccurrences(of: "addon:", with: ""))
    }

    /// "$3,300", "$210 – $343", "in fare", "not shown".
    var amountText: String {
        switch basisValue {
        case .notShown:
            return high.map { "up to \(Fmt.usd($0))" } ?? "not shown"
        case .included:
            if (amount ?? 0) == 0 && (high ?? 0) == 0 { return "included" }
        default:
            break
        }
        if let amount, low == nil || low == amount, high == nil || high == amount { return Fmt.usd(amount) }
        return Money.range(low ?? amount, high ?? amount) ?? "not shown"
    }

    /// "read · Costco", "rule · Disney 2026", "estimate · 3 days old", "not shown".
    var tag: String {
        var parts = [basisValue.title]
        if let source = source?.trimmed, !source.isEmpty {
            parts.append(source)
        } else if basisValue == .estimate, let age = SheetLine.age(asOf) {
            parts.append(age)
        }
        return parts.joined(separator: " · ")
    }

    /// "3 days old" from a date or timestamp.
    static func age(_ text: String?) -> String? {
        guard let date = Fmt.timestamp(text) ?? Fmt.day(text) else { return nil }
        let days = max(Int(Date().timeIntervalSince(date) / 86_400), 0)
        if days == 0 { return "today" }
        return days == 1 ? "1 day old" : "\(days) days old"
    }
}

struct SheetTotal: Decodable, Hashable {
    var firm: Int?
    var low: Int?
    var high: Int?
    var cabinLow: Int?
    var cabinHigh: Int?
    var complete: Bool?
    var notShown: [String]?

    enum CodingKeys: String, CodingKey {
        case firm, low, high, cabinLow, cabinHigh, complete, notShown
    }

    init(firm: Int?, low: Int?, high: Int?, cabinLow: Int? = nil, cabinHigh: Int? = nil, complete: Bool?,
         notShown: [String]? = nil) {
        self.firm = firm
        self.low = low
        self.high = high
        self.cabinLow = cabinLow
        self.cabinHigh = cabinHigh
        self.complete = complete
        self.notShown = notShown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firm = c.whole(.firm)
        low = c.whole(.low)
        high = c.whole(.high)
        cabinLow = c.whole(.cabinLow)
        cabinHigh = c.whole(.cabinHigh)
        complete = c.lenient(Bool.self, .complete)
        notShown = c.lenient([String].self, .notShown)
    }

    /// The headline: "$5,980 – $7,240", or one figure when they match.
    var headline: String? { Money.range(low ?? firm, high ?? low ?? firm) }

    var missing: [String] { (notShown ?? []).map { $0.trimmed }.filter { !$0.isEmpty } }

    /// A partial sum is never shown as complete.
    var isComplete: Bool { complete == true && missing.isEmpty }
}

/// The trip cost against Jim's budget. The budget is a SOFT target (Jim: "flexible but less is better"): it never
/// filters or hides a sailing; the sheet only says how far over it is.
struct SheetBudget: Decodable, Hashable {
    var budgetTotal: Int?
    var basis: String?
    var low: Int?
    var high: Int?
    var state: String?
    /// How far the low end is over the target (the server's figure).
    var overBy: Int?
    /// False when a part the target counts is not shown yet, so "under" is only "under so far".
    var complete: Bool?

    enum CodingKeys: String, CodingKey {
        case budgetTotal, basis, low, high, state, overBy, complete
    }

    init(budgetTotal: Int?, basis: String?, low: Int?, high: Int?, state: String?, overBy: Int? = nil,
         complete: Bool? = nil) {
        self.budgetTotal = budgetTotal
        self.basis = basis
        self.low = low
        self.high = high
        self.state = state
        self.overBy = overBy
        self.complete = complete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        budgetTotal = c.whole(.budgetTotal)
        basis = c.lenient(String.self, .basis)
        low = c.whole(.low)
        high = c.whole(.high)
        state = c.lenient(String.self, .state)
        overBy = c.whole(.overBy)
        complete = c.lenient(Bool.self, .complete)
    }

    /// "whole trip" or "cabin only": what the target is compared with.
    var whatText: String { basis == "trip" ? "whole trip" : "cabin only" }

    /// The low end's distance over the target: the server's `overBy`, else worked out from the low end.
    var over: Int? {
        if let overBy, overBy > 0 { return overBy }
        guard let total = budgetTotal, let low, low > total else { return nil }
        return low - total
    }

    /// How far the high end could go over while the low end is still under (the range straddles the target).
    var upTo: Int? {
        guard over == nil, state != "under", state != "under_so_far", let total = budgetTotal, let high, high > total
        else { return nil }
        return high - total
    }

    /// Under the target only for what is known; something it counts is not shown yet.
    var underSoFar: Bool {
        state == "under_so_far" || (state == "under" && complete == false)
    }

    var isOver: Bool { over != nil }

    /// The short words for a card or the trip check: "$640 over your $3,000 target". nil when under or unknown.
    var shortNote: String? {
        guard let total = budgetTotal else { return nil }
        let target = "your \(Fmt.usd(total)) target"
        if let over { return "\(Fmt.usd(over)) over \(target)" }
        if let upTo { return "Up to \(Fmt.usd(upTo)) over \(target)" }
        return nil
    }

    /// "$640 over your $3,000 target · whole trip $3,640 – $4,950", "Within your $3,000 target · cabin only $2,900",
    /// "Under your $3,000 target so far · whole trip $2,100 – $2,800, before what isn't shown".
    var line: String? {
        guard let total = budgetTotal else { return nil }
        let target = "your \(Fmt.usd(total)) target"
        let figure = Money.range(low, high).map { "\(whatText) \($0)" }
        let lead: String
        if let note = shortNote {
            lead = note
        } else if underSoFar {
            lead = "Under \(target) so far"
            return figure.map { "\(lead) · \($0), before what isn't shown" } ?? lead
        } else if state == "under" {
            lead = "Within \(target)"
        } else if let figure, state != "unknown" {
            return "Your \(Fmt.usd(total)) target · \(figure)"
        } else {
            let cost = basis == "trip" ? "the whole-trip cost" : "the cabin cost"
            return "Your \(Fmt.usd(total)) target · \(cost) isn't known yet"
        }
        return figure.map { "\(lead) · \($0)" } ?? lead
    }
}

struct SheetVerdict: Decodable, Hashable {
    var label: String?
    var reasons: [String]?
    var line: String?
    var lineBy: String?

    enum CodingKeys: String, CodingKey {
        case label, reasons, line, lineBy
    }

    init(label: String?, reasons: [String]? = nil, line: String? = nil, lineBy: String? = nil) {
        self.label = label
        self.reasons = reasons
        self.line = line
        self.lineBy = lineBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = c.lenient(String.self, .label)
        reasons = c.lenient([String].self, .reasons)
        line = c.lenient(String.self, .line)
        lineBy = c.lenient(String.self, .lineBy)
    }

    var word: VerdictWord { VerdictWord(label) }
}

struct SheetBundle: Decodable, Hashable {
    var key: String?
    var name: String?
    var includesKinds: [String]?
    var valueLow: Int?
    var valueHigh: Int?
    var toYouLow: Int?
    var toYouHigh: Int?
    var barePP: Int?
    var bareSource: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case key, name, includesKinds, valueLow, valueHigh, toYouLow, toYouHigh, barePP, bareSource, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(String.self, .key)
        name = c.lenient(String.self, .name)
        includesKinds = c.lenient([String].self, .includesKinds)
        valueLow = c.whole(.valueLow)
        valueHigh = c.whole(.valueHigh)
        toYouLow = c.whole(.toYouLow)
        toYouHigh = c.whole(.toYouHigh)
        barePP = c.whole(.barePP)
        bareSource = c.lenient(String.self, .bareSource)
        note = c.lenient(String.self, .note)
    }

    /// "Free at Sea: about $1,400 – $1,700 of drinks and Wi-Fi you said you buy". Never "save $X" here.
    var summary: String? {
        guard let name = name?.trimmed, !name.isEmpty else { return nil }
        let kinds = (includesKinds ?? []).map { AddonKind.title($0).lowercased() }
        if let toYou = Money.range(toYouLow, toYouHigh), toYouHigh ?? toYouLow ?? 0 > 0 {
            let what = kinds.isEmpty ? "extras" : ListText.join(kinds)
            return "\(name): about \(toYou) of \(what) you said you buy"
        }
        if let value = Money.range(valueLow, valueHigh) {
            return "\(name): worth about \(value) at the line's own prices"
        }
        return "\(name) is part of this fare"
    }
}

struct WhatToBuyItem: Decodable, Hashable, Identifiable {
    var kind: String?
    var key: String?
    var name: String?
    var low: Int?
    var high: Int?
    var unit: String?
    var persons: Int?
    var buyWhen: String?
    var worthIt: String?
    var counted: Bool?

    var id: String { key ?? name ?? kind ?? "item" }

    enum CodingKeys: String, CodingKey {
        case kind, key, name, low, high, unit, persons, buyWhen, worthIt, counted
    }

    init(kind: String?, key: String?, name: String?, low: Int?, high: Int?, unit: String?, persons: Int?,
         buyWhen: String?, worthIt: String?, counted: Bool?) {
        self.kind = kind
        self.key = key
        self.name = name
        self.low = low
        self.high = high
        self.unit = unit
        self.persons = persons
        self.buyWhen = buyWhen
        self.worthIt = worthIt
        self.counted = counted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(String.self, .kind)
        key = c.lenient(String.self, .key)
        name = c.lenient(String.self, .name)
        low = c.whole(.low)
        high = c.whole(.high)
        unit = c.lenient(String.self, .unit)
        persons = c.whole(.persons)
        buyWhen = c.lenient(String.self, .buyWhen)
        if let text = c.lenient(String.self, .worthIt) {
            worthIt = text
        } else {
            worthIt = c.lenient(AddonWorth.self, .worthIt).flatMap { $0.couple ?? $0.family }
        }
        counted = c.lenient(Bool.self, .counted)
    }

    var title: String { name?.trimmed.isEmpty == false ? name! : AddonKind.title(kind ?? "other") }

    /// "$210 – $343 for 2 · buy before the cruise"
    var detail: String {
        var parts: [String] = []
        if let range = Money.range(low, high) {
            parts.append(persons.map { $0 > 0 ? "\(range) for \($0)" : range } ?? range)
        } else {
            parts.append("price not researched")
        }
        if let when = BuyWhen.text(buyWhen) { parts.append(when) }
        return parts.joined(separator: " · ")
    }
}

struct SheetPay: Decodable, Hashable {
    var depositPP: Int?
    var depositNote: String?
    var finalPaymentDate: String?
    var refundableBeforeFinal: Bool?
    var note: String?
    var basis: String?
    var asOf: String?

    enum CodingKeys: String, CodingKey {
        case depositPP, depositNote, finalPaymentDate, refundableBeforeFinal, note, basis, asOf
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        depositPP = c.whole(.depositPP)
        depositNote = c.lenient(String.self, .depositNote)
        finalPaymentDate = c.lenient(String.self, .finalPaymentDate)
        refundableBeforeFinal = c.lenient(Bool.self, .refundableBeforeFinal)
        note = c.lenient(String.self, .note)
        basis = c.lenient(String.self, .basis)
        asOf = c.lenient(String.self, .asOf)
    }

    var basisValue: MoneyBasis { MoneyBasis(basis) }
}

/// The flight estimate (CONTRACT_V5 section 4): a recent fare a provider saw, per person, economy, round trip.
/// It is an estimate with its basis, never a quote.
struct SheetFlight: Decodable, Hashable {
    var pp: Int?
    var total: Int?
    var ageDays: Int?
    var provider: String?
    var state: String?
    /// The day the provider saw the fare ("2026-11-25").
    var foundAt: String?
    /// The server's own basis words ("recent fare seen 2026-11-25, SEA–IAH, per person, economy").
    var basis: String?
    /// "SEA–IAH" (the airport the fare is for).
    var route: String?
    /// "13:00": the earliest flight home on the day the ship returns.
    var returnNotBefore: String?
    /// A return departure time, when the provider gave one (a date-level fare has none).
    var returnTime: String?

    init(pp: Int? = nil, total: Int? = nil, ageDays: Int? = nil, provider: String? = nil, state: String?,
         foundAt: String? = nil, basis: String? = nil, route: String? = nil, returnNotBefore: String? = nil,
         returnTime: String? = nil) {
        self.pp = pp
        self.total = total
        self.ageDays = ageDays
        self.provider = provider
        self.state = state
        self.foundAt = foundAt
        self.basis = basis
        self.route = route
        self.returnNotBefore = returnNotBefore
        self.returnTime = returnTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func text(_ names: String...) -> String? {
            for name in names {
                if let value = c.lenient(String.self, AnyKey(name))?.trimmed, !value.isEmpty { return value }
            }
            return nil
        }
        pp = c.whole(AnyKey("pp"))
        total = c.whole(AnyKey("total"))
        ageDays = c.whole(AnyKey("ageDays"))
        provider = text("provider")
        state = text("state")
        foundAt = text("foundAt", "providerFoundAt", "seenAt")
        basis = text("basis", "basisText", "label")
        route = text("route")
        returnNotBefore = text("returnNotBefore")
        returnTime = text("returnTime", "returnDepartsAt")
    }

    /// An estimate is there to show.
    var isReady: Bool { state == "ready" && (pp ?? 0) > 0 }
}

/// Clock times the way the screens say them: "13:00" -> "1 PM", "13:30" -> "1:30 PM".
enum ClockWords {
    /// The disembark-day rule's line-agnostic default: a flight home on the return date leaves at or after 1 PM.
    static let defaultReturnNotBefore = "13:00"

    static func words(_ hhmm: String?) -> String? {
        guard let text = hhmm?.trimmed, text.count == 5, Array(text)[2] == ":",
              let hour = Int(text.prefix(2)), let minute = Int(text.suffix(2)),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let half = hour >= 12 ? "PM" : "AM"
        return minute == 0 ? "\(twelve) \(half)" : "\(twelve):\(String(format: "%02d", minute)) \(half)"
    }
}

struct SheetLineAir: Decodable, Hashable {
    var program: String?
    var url: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case program, url, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        program = c.lenient(String.self, .program)
        url = c.lenient(String.self, .url)
        note = c.lenient(String.self, .note)
    }

    var link: URL? { Fmt.webURL(url) }
}

struct SheetHotel: Decodable, Hashable {
    var nights: Int?
    var low: Int?
    var high: Int?
    var basis: String?

    enum CodingKeys: String, CodingKey {
        case nights, low, high, basis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nights = c.whole(.nights)
        low = c.whole(.low)
        high = c.whole(.high)
        basis = c.lenient(String.self, .basis)
    }
}

/// How Jim gets to the ship: home, drive, fly, or not known yet. An unknown mode is shown as it is.
enum TravelMode: Equatable {
    case home, drive, fly, notKnown
    case other(String)

    init(_ raw: String?) {
        switch raw?.trimmed ?? "" {
        case "home": self = .home
        case "drive": self = .drive
        case "fly": self = .fly
        case "unknown", "": self = .notKnown
        default: self = .other(raw ?? "")
        }
    }
}

struct SheetTravel: Decodable, Hashable {
    var mode: String?
    var fromAirport: String?
    var toAirport: String?
    var departDate: String?
    var returnDate: String?
    /// "13:00": the disembark-day rule for this sailing (never earlier than 1 PM; a line's own rule may be later).
    var returnNotBefore: String?
    /// The server's note for Getting there (the disembark-day rule, "return after 1 PM assumed").
    var note: String?
    var flight: SheetFlight?
    var searchUrl: String?
    var lineAir: SheetLineAir?
    var hotel: SheetHotel?

    enum CodingKeys: String, CodingKey {
        case mode, fromAirport, toAirport, departDate, returnDate, returnNotBefore, note, flight, searchUrl, lineAir
        case hotel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.lenient(String.self, .mode)
        fromAirport = c.lenient(String.self, .fromAirport)
        toAirport = c.lenient(String.self, .toAirport)
        departDate = c.lenient(String.self, .departDate)
        returnDate = c.lenient(String.self, .returnDate)
        returnNotBefore = c.lenient(String.self, .returnNotBefore)
        note = c.lenient(String.self, .note)
        flight = c.lenient(SheetFlight.self, .flight)
        searchUrl = c.lenient(String.self, .searchUrl)
        lineAir = c.lenient(SheetLineAir.self, .lineAir)
        hotel = c.lenient(SheetHotel.self, .hotel)
    }

    var modeValue: TravelMode { TravelMode(mode) }
    var searchLink: URL? { Fmt.webURL(searchUrl) }

    /// "SEA–IAH": the fare's own route, else home airport to the port's airport.
    var route: String? {
        if let route = flight?.route?.trimmed, !route.isEmpty { return route }
        let ends = [fromAirport, toAirport].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        return ends.count == 2 ? ends.joined(separator: "–") : nil
    }

    /// "1 PM": the earliest flight home on the day the ship returns. Never earlier than the 1 PM default, whatever
    /// a server or a line sends.
    var returnAfter: String {
        let given = [returnNotBefore, flight?.returnNotBefore].compactMap { $0?.trimmed }
            .filter { ClockWords.words($0) != nil }
        let latest = (given + [ClockWords.defaultReturnNotBefore]).max() ?? ClockWords.defaultReturnNotBefore
        return ClockWords.words(latest) ?? "1 PM"
    }

    /// "recent fare seen Nov 25, SEA–IAH, per person, economy": what the flight figure is, so it never reads as a
    /// quote.
    var flightBasis: String? {
        guard let flight, flight.isReady else { return nil }
        var seen = "recent fare seen"
        if let day = Fmt.day(flight.foundAt) {
            seen += " \(Fmt.shortDay(day))"
        } else if let basis = flight.basis?.trimmed, !basis.isEmpty {
            return basis
        } else if let age = flight.ageDays, age >= 0 {
            seen += age == 0 ? " today" : (age == 1 ? " 1 day ago" : " \(age) days ago")
        }
        return [seen, route, "per person", "economy"].compactMap { $0 }.joined(separator: ", ")
    }

    /// A date-level fare (no flight time) is priced on the rule, never on an earlier flight.
    var returnAssumed: Bool {
        guard let flight, flight.isReady else { return false }
        return flight.returnTime == nil
    }

    /// "Out Fri Sep 3 · home Sat Sep 11, after 1 PM" (the time only with the disembark-day rule on).
    func datesText(rule: Bool) -> String? {
        var parts: [String] = []
        if let out = Fmt.day(departDate) { parts.append("Out \(Fmt.weekday(out))") }
        if let home = Fmt.day(returnDate) {
            parts.append(rule ? "home \(Fmt.weekday(home)), after \(returnAfter)" : "home \(Fmt.weekday(home))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The disembark-day rule for Getting there (Jim: a 7 AM flight the day the ship returns is impossible). The
    /// server's note when it sends one; else the app's own words, only while flight estimates are on.
    func disembarkNote(flightsOn: Bool) -> String? {
        guard modeValue == .fly else { return nil }
        if let note = note?.trimmed, !note.isEmpty { return note }
        guard flightsOn else { return nil }
        if returnAssumed {
            return "Return after \(returnAfter) assumed: the fare is for the day, not a flight, and a flight home before \(returnAfter) on the day the ship docks is never priced."
        }
        return "Flights home on the day the ship docks should leave at \(returnAfter) or later."
    }
}

struct SheetItinerary: Decodable, Hashable {
    var seaDays: Int?
    var portDays: Int?
    var scenicDays: Int?

    enum CodingKeys: String, CodingKey {
        case seaDays, portDays, scenicDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seaDays = c.whole(.seaDays)
        portDays = c.whole(.portDays)
        scenicDays = c.whole(.scenicDays)
    }

    /// "3 sea days · 4 port days"
    var text: String? {
        var parts: [String] = []
        if let sea = seaDays { parts.append(sea == 1 ? "1 sea day" : "\(sea) sea days") }
        if let port = portDays { parts.append(port == 1 ? "1 port day" : "\(port) port days") }
        if let scenic = scenicDays, scenic > 0 { parts.append(scenic == 1 ? "1 scenic day" : "\(scenic) scenic days") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct SheetFreshness: Decodable, Hashable {
    var fareSeenAt: String?
    var oldestFigureAt: String?

    enum CodingKeys: String, CodingKey {
        case fareSeenAt, oldestFigureAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fareSeenAt = c.lenient(String.self, .fareSeenAt)
        oldestFigureAt = c.lenient(String.self, .oldestFigureAt)
    }
}

/// The trip cost for the party and a verdict, built by the deal server (never sent by the app).
struct DealSheet: Decodable, Hashable {
    var party: SheetParty?
    var cabin: String?
    var category: String?
    var lines: [SheetLine]
    var total: SheetTotal?
    var budget: SheetBudget?
    var verdict: SheetVerdict?
    var bundle: SheetBundle?
    var whatToBuy: [WhatToBuyItem]
    var pay: SheetPay?
    var travel: SheetTravel?
    var itinerary: SheetItinerary?
    var freshness: SheetFreshness?
    var refAsOf: String?
    var sig: String?
    var builtAt: String?

    enum CodingKeys: String, CodingKey {
        case party, cabin, category, lines, total, budget, verdict, bundle, whatToBuy, pay, travel, itinerary
        case freshness, refAsOf, sig, builtAt
    }

    private struct CabinObject: Decodable {
        var type: String?
        var cabin: String?
        var category: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        party = c.lenient(SheetParty.self, .party)
        if let text = c.lenient(String.self, .cabin) {
            cabin = text
            category = c.lenient(String.self, .category)
        } else if let object = c.lenient(CabinObject.self, .cabin) {
            cabin = object.type ?? object.cabin
            category = object.category ?? c.lenient(String.self, .category)
        } else {
            cabin = nil
            category = c.lenient(String.self, .category)
        }
        lines = c.list(SheetLine.self, .lines) ?? []
        total = c.lenient(SheetTotal.self, .total)
        budget = c.lenient(SheetBudget.self, .budget)
        verdict = c.lenient(SheetVerdict.self, .verdict)
        bundle = c.lenient(SheetBundle.self, .bundle)
        whatToBuy = c.list(WhatToBuyItem.self, .whatToBuy) ?? []
        pay = c.lenient(SheetPay.self, .pay)
        travel = c.lenient(SheetTravel.self, .travel)
        itinerary = c.lenient(SheetItinerary.self, .itinerary)
        freshness = c.lenient(SheetFreshness.self, .freshness)
        refAsOf = c.lenient(String.self, .refAsOf)
        sig = c.lenient(String.self, .sig)
        builtAt = c.lenient(String.self, .builtAt)
        guard total != nil || !lines.isEmpty || verdict != nil else {
            throw DecodingError.dataCorruptedError(forKey: .total, in: c, debugDescription: "An empty sheet")
        }
    }

    /// Reads the `sheet` field of a deal or tracked document; nil when missing or unreadable.
    static func from(_ data: JSONValue) -> DealSheet? {
        guard let value = data.field("sheet"), case .object = value else { return nil }
        return value.decode(DealSheet.self)
    }

    /// `GET /v1/sheet` answers with the sheet itself, or `{sheet: {...}}`.
    static func decodeResponse(_ data: Data) -> DealSheet? {
        if let sheet = try? JSONDecoder().decode(DealSheet.self, from: data) { return sheet }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return DealSheet.from(value)
    }

    /// "for 2 adults + 1 child", with the child's age on the sailing when the server knows it.
    var partyText: String? {
        guard let words = party?.words else { return nil }
        if let ages = party?.agesText { return "for \(words) (\(ages))" }
        return "for \(words)"
    }

    /// The flights line's words from the travel block: what the figure is, never a quote.
    func detail(for line: SheetLine) -> String? {
        guard line.key == "flights", let travel, let basis = travel.flightBasis else { return line.detail }
        var text = basis
        if let pp = travel.flight?.pp, let guests = party?.guests, guests > 0 {
            text += " · about \(Fmt.usd(pp)) × \(guests), round trip"
        }
        if travel.returnAssumed { text += " · return after \(travel.returnAfter) assumed" }
        return text
    }

    /// The flights line says it is an estimate and not a quote; every other line keeps its own tag.
    func tag(for line: SheetLine) -> String {
        guard line.key == "flights", travel?.flightBasis != nil, line.basisValue == .estimate else { return line.tag }
        return "estimate · not a quote"
    }

    /// "Cruise, taxes, tips $3,636": names only what the firm figure really holds (a line that is not shown is out).
    var firmText: String? {
        guard let firm = total?.firm else { return nil }
        func counted(_ key: String) -> Bool {
            guard let line = lines.first(where: { $0.key == key }) else { return false }
            return line.basisValue != .notShown
        }
        let taxes = counted("taxes"), tips = counted("gratuities")
        let label = taxes && tips ? "Cruise, taxes, tips" : taxes ? "Cruise + taxes" : tips ? "Cruise + tips" : "Cruise only"
        return "\(label) \(Fmt.usd(firm))"
    }

    var cabinTitle: String? {
        let type = cabin.flatMap { CabinType(rawValue: $0)?.title } ?? cabin.map { Words.humanize($0) }
        guard let category = category?.trimmed, !category.isEmpty else { return type }
        return type.map { "\($0) · \(category)" } ?? category
    }

    var tripCost: TripCost {
        TripCost(low: total?.low ?? total?.firm, high: total?.high ?? total?.low ?? total?.firm,
                 complete: total?.isComplete, verdict: verdict?.label)
    }
}

// MARK: - Reference: add-ons (`GET /v1/reference/addons?line=`; CONTRACT_V5 section 3)

enum AddonKind {
    static let all = ["drinks", "soft-drinks", "coffee", "wifi", "dining", "excursions", "perks-pass", "kids", "spa",
                      "photos", "other"]

    static func title(_ kind: String) -> String {
        switch kind {
        case "drinks": return "Drinks"
        case "soft-drinks": return "Soft drinks"
        case "coffee": return "Coffee"
        case "wifi": return "Wi-Fi"
        case "dining": return "Specialty dining"
        case "excursions": return "Excursions"
        case "perks-pass": return "Perks pass"
        case "kids": return "Kids' extras"
        case "spa": return "Spa"
        case "photos": return "Photos"
        case "other": return "Other"
        default: return Words.humanize(kind)
        }
    }
}

enum BuyWhen {
    static func text(_ raw: String?) -> String? {
        switch raw ?? "" {
        case "pre-cruise": return "buy before the cruise"
        case "onboard": return "buy on board"
        case "either": return "before or on board"
        case "": return nil
        default: return Words.humanize(raw ?? "").lowercased()
        }
    }
}

enum ListText {
    /// "drinks, Wi-Fi and dining"
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

struct AddonWorth: Decodable, Hashable {
    var couple: String?
    var family: String?

    enum CodingKeys: String, CodingKey {
        case couple, family
    }

    init(couple: String?, family: String?) {
        self.couple = couple
        self.family = family
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        couple = c.lenient(String.self, .couple)
        family = c.lenient(String.self, .family)
    }
}

struct AddonPrice: Decodable, Hashable, Identifiable {
    var key: String
    var kind: String?
    var name: String?
    var priceLow: Double?
    var priceHigh: Double?
    var onboardLow: Double?
    var onboardHigh: Double?
    var unit: String?
    var buyWhen: String?
    var appliesTo: String?
    var cabinRule: String?
    var defaultForKind: Bool?
    var worthIt: AddonWorth?
    var notes: String?
    var asOf: String?
    var source: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, kind, name, priceLow, priceHigh, onboardLow, onboardHigh, unit, buyWhen, appliesTo, cabinRule
        case defaultForKind, worthIt, notes, asOf, source
    }

    init(key: String, kind: String?, name: String?, priceLow: Double?, priceHigh: Double?, unit: String?,
         buyWhen: String?, worthIt: AddonWorth?, notes: String? = nil, asOf: String? = nil, source: String? = nil) {
        self.key = key
        self.kind = kind
        self.name = name
        self.priceLow = priceLow
        self.priceHigh = priceHigh
        self.unit = unit
        self.buyWhen = buyWhen
        self.worthIt = worthIt
        self.notes = notes
        self.asOf = asOf
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(String.self, .key) ?? UUID().uuidString
        kind = c.lenient(String.self, .kind)
        name = c.lenient(String.self, .name)
        priceLow = c.number(.priceLow)
        priceHigh = c.number(.priceHigh)
        onboardLow = c.number(.onboardLow)
        onboardHigh = c.number(.onboardHigh)
        unit = c.lenient(String.self, .unit)
        buyWhen = c.lenient(String.self, .buyWhen)
        appliesTo = c.lenient(String.self, .appliesTo)
        cabinRule = c.lenient(String.self, .cabinRule)
        defaultForKind = c.lenient(Bool.self, .defaultForKind)
        worthIt = c.lenient(AddonWorth.self, .worthIt)
        notes = c.lenient(String.self, .notes)
        asOf = c.lenient(String.self, .asOf)
        source = c.lenient(String.self, .source)
    }

    var title: String { name?.trimmed.isEmpty == false ? name! : AddonKind.title(kind ?? "other") }

    /// "$98 – $119 a person a day before the cruise; $108 – $137 on board"
    var priceText: String {
        let per = AddonPrice.unitText(unit)
        var parts: [String] = []
        if let before = AddonPrice.range(priceLow, priceHigh) {
            parts.append(per.isEmpty ? before : "\(before) \(per)")
        }
        if let onboard = AddonPrice.range(onboardLow, onboardHigh) {
            parts.append("\(onboard) on board")
        }
        return parts.isEmpty ? "price not researched" : parts.joined(separator: "; ")
    }

    static func unitText(_ unit: String?) -> String {
        switch unit ?? "" {
        case "pppd": return "a person a day"
        case "pp": return "a person"
        case "pppd-device": return "a device a day"
        case "per-meal": return "a meal"
        case "per-cabin": return "a cabin"
        case "per-voyage": return "a cruise"
        case "": return ""
        default: return Words.humanize(unit ?? "").lowercased()
        }
    }

    static func money(_ value: Double) -> String {
        if value.rounded() == value { return Fmt.usd(Int(value)) }
        return String(format: "$%.2f", value)
    }

    static func range(_ low: Double?, _ high: Double?) -> String? {
        switch (low, high) {
        case let (low?, high?) where low == high: return money(low)
        case let (low?, high?): return "\(money(min(low, high))) – \(money(max(low, high)))"
        case let (low?, nil): return money(low)
        case let (nil, high?): return "up to \(money(high))"
        case (nil, nil): return nil
        }
    }
}

struct AddonBundle: Decodable, Hashable, Identifiable {
    struct Range: Decodable, Hashable {
        var low: Double?
        var high: Double?

        enum CodingKeys: String, CodingKey {
            case low, high
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            low = c.number(.low)
            high = c.number(.high)
        }
    }

    var key: String
    var name: String?
    var includesKinds: [String]?
    var includesText: [String]?
    var pricePPPD: Range?
    var includesGratuities: Bool?
    var howItPrices: String?
    var asOf: String?
    var source: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, includesKinds, includesText, pricePPPD, includesGratuities, howItPrices, asOf, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(String.self, .key) ?? UUID().uuidString
        name = c.lenient(String.self, .name)
        includesKinds = c.lenient([String].self, .includesKinds)
        includesText = c.lenient([String].self, .includesText)
        pricePPPD = c.lenient(Range.self, .pricePPPD)
        includesGratuities = c.lenient(Bool.self, .includesGratuities)
        howItPrices = c.lenient(String.self, .howItPrices)
        asOf = c.lenient(String.self, .asOf)
        source = c.lenient(String.self, .source)
    }
}

struct AddonGratuity: Decodable, Hashable {
    var pppd: [String: Double]
    var appliesTo: String?
    var includedWithBundles: [String]?
    var asOf: String?
    var note: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case pppd, appliesTo, includedWithBundles, asOf, note, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var rates: [String: Double] = [:]
        if let raw = c.lenient([String: JSONValue].self, .pppd) {
            for (tier, value) in raw {
                switch value {
                case .int(let n): rates[tier] = Double(n)
                case .double(let n): rates[tier] = n
                default: break
                }
            }
        }
        pppd = rates
        appliesTo = c.lenient(String.self, .appliesTo)
        includedWithBundles = c.lenient([String].self, .includedWithBundles)
        asOf = c.lenient(String.self, .asOf)
        note = c.lenient(String.self, .note)
        source = c.lenient(String.self, .source)
    }

    /// "$16 standard · $18.50 suite a person a day"
    var ratesText: String? {
        let order = ["standard", "suite"]
        let tiers = order.filter { pppd[$0] != nil } + pppd.keys.filter { !order.contains($0) }.sorted()
        guard !tiers.isEmpty else { return nil }
        return tiers.map { "\(AddonPrice.money(pppd[$0] ?? 0)) \(Words.humanize($0).lowercased())" }
            .joined(separator: " · ") + " a person a day"
    }

    var appliesText: String? {
        switch appliesTo ?? "" {
        case "all": return "charged for every guest"
        case "adults": return "charged for adults"
        default: return nil
        }
    }
}

/// One line's add-ons guide: what is included, bundles, add-ons, gratuities, sources and as-of.
struct AddonsGuide: Decodable, Hashable {
    var line: String?
    var gratuity: AddonGratuity?
    var included: [String]
    var notIncluded: [String]
    var addons: [AddonPrice]
    var bundles: [AddonBundle]
    var sources: [String]
    var forParty: [WhatToBuyItem]
    var asOf: String?

    enum CodingKeys: String, CodingKey {
        case line, gratuity, included, notIncluded, addons, bundles, sources, forParty, asOf, lines, entry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = c.lenient(String.self, .line)
        gratuity = c.lenient(AddonGratuity.self, .gratuity)
        included = c.lenient([String].self, .included) ?? []
        notIncluded = c.lenient([String].self, .notIncluded) ?? []
        addons = c.list(AddonPrice.self, .addons) ?? []
        bundles = c.list(AddonBundle.self, .bundles) ?? []
        sources = c.lenient([String].self, .sources) ?? []
        if let rows = c.list(WhatToBuyItem.self, .forParty) {
            forParty = rows
        } else {
            // `forParty` may be an object around the list.
            struct Wrapped: Decodable { var items: LenientList<WhatToBuyItem>? }
            forParty = c.lenient(Wrapped.self, .forParty)?.items?.items ?? []
        }
        asOf = c.lenient(String.self, .asOf)
    }

    var isEmpty: Bool {
        gratuity == nil && included.isEmpty && notIncluded.isEmpty && addons.isEmpty && bundles.isEmpty
    }

    /// `GET /v1/reference/addons?line=`: the entry itself, `{entry: {...}}`, or `{lines: {<line>: {...}}}`.
    static func decodeResponse(_ data: Data, line: String) -> AddonsGuide? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        var extras: [String: JSONValue] = [:]
        if let party = value.field("forParty") { extras["forParty"] = party }
        if let asOf = value.field("asOf") { extras["asOf"] = asOf }
        var entry: JSONValue? = nil
        if let inner = value.field("entry"), case .object = inner {
            entry = inner
        } else if case .object(let lines)? = value.field("lines") {
            entry = lines.first { CruiseLine.same($0.key, line) }?.value
        } else {
            entry = value
        }
        guard let base = entry, case .object = base else { return nil }
        let found = base.merging(extras.filter { base.field($0.key) == nil })
        guard let guide = found.decode(AddonsGuide.self), !guide.isEmpty || !guide.forParty.isEmpty else { return nil }
        return guide
    }
}

// MARK: - My trips: what we had (CONTRACT_V5 section 3.5)

struct TripExtra: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String = ""
    var kind: String? = nil
    /// promo | bought | included
    var how: String = "bought"
    var liked: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case name, kind, how, liked
    }

    init(name: String = "", kind: String? = nil, how: String = "bought", liked: Bool? = nil) {
        self.name = name
        self.kind = kind
        self.how = how
        self.liked = liked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, .name) ?? ""
        kind = c.lenient(String.self, .kind)
        how = c.lenient(String.self, .how) ?? "bought"
        liked = c.lenient(Bool.self, .liked)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(how, forKey: .how)
        try c.encode(liked, forKey: .liked)
    }

    static let hows: [(id: String, title: String)] = [("promo", "Came with a promo"), ("bought", "We bought it"),
                                                      ("included", "Included in the fare")]

    static func howTitle(_ raw: String) -> String {
        hows.first { $0.id == raw }?.title ?? Words.humanize(raw)
    }

    var json: JSONValue {
        var item: [String: JSONValue] = ["name": .string(name.trimmed.capped(40)),
                                         "how": .string(["promo", "bought", "included"].contains(how) ? how : "bought")]
        item["kind"] = kind.flatMap { AddonKind.all.contains($0) ? JSONValue.string($0) : nil } ?? .null
        item["liked"] = liked.map { JSONValue.bool($0) } ?? .null
        return .object(item)
    }

    /// The `extras` field of a trip document.
    static func from(_ data: JSONValue) -> [TripExtra] {
        guard let value = data.field("extras"), case .array = value else { return [] }
        return value.decode(LenientList<TripExtra>.self)?.items.filter { !$0.name.trimmed.isEmpty } ?? []
    }
}

// MARK: - Ship classes, named in full (Jim: never "+ N more")

/// One class of one line, with every ship in it. "2 ships in this class: Norwegian Getaway, Norwegian Breakaway".
struct ShipClassGroup: Hashable, Identifiable {
    let line: String
    let name: String
    let ships: [CatalogShip]

    var id: String { "\(line)|\(name)" }
    var key: String { id }

    var title: String { "\(name) class" }

    var shipNames: [String] { ships.compactMap { $0.name?.trimmed }.filter { !$0.isEmpty } }

    /// "1 ship in this class" / "2 ships in this class"
    var countText: String { shipNames.count == 1 ? "1 ship in this class" : "\(shipNames.count) ships in this class" }

    /// Every ship named, with a plain total, never "+ N more".
    var label: String { "\(countText): \(shipNames.joined(separator: ", "))" }

    /// The longest length the catalog knows for a ship of this class.
    var lengthFt: Double? { ships.compactMap { $0.lengthFt }.max() }

    var gt: Int? { ships.compactMap { $0.gt }.max() }
    var passengers: Int? { ships.compactMap { $0.passengers }.max() }
    var tier: ShipSize? { ShipSize.tier(gt: gt) ?? ships.compactMap { $0.tier }.first }
}

extension Catalog {
    /// A line's classes in the catalog's order, each with every ship in it.
    func classGroups(line: String) -> [ShipClassGroup] {
        var order: [String] = []
        var members: [String: [CatalogShip]] = [:]
        for ship in ships(for: line) {
            let name = ShipClassGroup.className(of: ship)
            guard let name else { continue }
            if members[name] == nil { order.append(name) }
            members[name, default: []].append(ship)
        }
        let lineName = self.line(line)?.name ?? CruiseLine.resolved(line)
        return order.map { ShipClassGroup(line: lineName, name: $0, ships: members[$0] ?? []) }
    }

    /// The class a ship belongs to, with all its sisters.
    func classGroup(line: String, ship: String?) -> ShipClassGroup? {
        guard let known = self.ship(line: line, named: ship), let name = ShipClassGroup.className(of: known) else {
            return nil
        }
        return classGroups(line: line).first { $0.name == name }
    }

    /// The class with this slug or name on a line.
    func classGroup(line: String, classKey: String?) -> ShipClassGroup? {
        guard let wanted = classKey?.trimmed, !wanted.isEmpty, wanted != "other" else { return nil }
        let slug = Slug.plain(wanted)
        return classGroups(line: line).first { group in
            Slug.plain(group.name) == slug || group.ships.contains { $0.classSlug == wanted }
        }
    }

    /// Every class of every line, lines in the catalog's order.
    var allClassGroups: [ShipClassGroup] { lineNames.flatMap { classGroups(line: $0) } }
}

extension ShipClassGroup {
    /// The catalog's class name ("Breakaway"), else the class slug as words; nil for an unclassed ship.
    static func className(of ship: CatalogShip) -> String? {
        if let name = ship.className?.trimmed, !name.isEmpty { return name }
        if let slug = ship.classSlug?.trimmed, !slug.isEmpty, slug != "other" { return Words.title(fromSlug: slug) }
        return nil
    }
}

/// A ship the screens can open: its line and name.
struct ShipRef: Hashable, Identifiable {
    let line: String
    let name: String
    var id: String { "\(line)|\(name)" }
}

// MARK: - Ship photos (`GET /v1/ships/photos`)

/// One real side-on photo of a class, cropped bow to stern at the waterline (Wikimedia Commons, credited).
struct ShipPhoto: Hashable, Identifiable {
    let key: String
    let line: String
    let className: String
    var file: String?
    var url: String?
    var shipInPhoto: String?
    var sister: Bool
    var author: String?
    var license: String?
    var commonsPage: String?
    var lengthFt: Double?
    /// width / height of the cropped photo, when the manifest says.
    var aspect: Double?

    var id: String { key }

    /// Where the app fetches the image: the manifest's own path, else the api's photo path for the file.
    var path: String? {
        if let url = url?.trimmed, url.hasPrefix("/v1/"), !url.contains("..") { return url }
        // A bare file name only: anything with a path in it is refused, never followed.
        guard let name = file?.trimmed, !name.isEmpty, !name.contains(".."), !name.hasPrefix(".") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return "/v1/ships/photo/\(name)"
    }

    var commonsLink: URL? { Fmt.webURL(commonsPage) }

    /// "Icon of the Seas by Jane Doe, CC BY-SA 4.0"
    var credit: String {
        var text = shipInPhoto?.trimmed.isEmpty == false ? shipInPhoto! : "\(className) class"
        if sister { text += " (a sister ship)" }
        text += " by \(author?.trimmed.isEmpty == false ? author! : "unknown author")"
        if let license = license?.trimmed, !license.isEmpty { text += ", \(license)" }
        return text
    }
}

struct ShipPhotoManifest: Hashable {
    var photos: [String: ShipPhoto] = [:]

    var isEmpty: Bool { photos.isEmpty }

    func photo(line: String, className: String) -> ShipPhoto? {
        if let hit = photos["\(line)|\(className)"] { return hit }
        let wantedLine = Slug.plain(line), wantedClass = Slug.plain(className)
        return photos.values.first { Slug.plain($0.line) == wantedLine && Slug.plain($0.className) == wantedClass }
            ?? photos.values.first { CruiseLine.same($0.line, line) && Slug.plain($0.className) == wantedClass }
    }

    func photo(for group: ShipClassGroup) -> ShipPhoto? { photo(line: group.line, className: group.name) }

    /// The manifest as the api serves it: `{"Line|Class": {...}}`, or the same under `photos`.
    static func decode(_ data: Data) -> ShipPhotoManifest {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return ShipPhotoManifest() }
        return from(value)
    }

    static func from(_ value: JSONValue) -> ShipPhotoManifest {
        var table: [String: JSONValue] = [:]
        if case .object(let inner)? = value.field("photos") {
            table = inner
        } else if case .object(let top) = value {
            table = top
        }
        var out: [String: ShipPhoto] = [:]
        for (key, entry) in table {
            guard case .object = entry else { continue }
            let parts = key.split(separator: "|", maxSplits: 1).map { String($0).trimmed }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            func text(_ name: String) -> String? {
                entry.field(name)?.stringValue.flatMap { $0.trimmed.isEmpty ? nil : $0.trimmed }
            }
            func number(_ names: [String]) -> Double? {
                for name in names {
                    switch entry.field(name) {
                    case .int(let n)?: return Double(n)
                    case .double(let n)?: return n
                    default: continue
                    }
                }
                return nil
            }
            var sister = false
            switch entry.field("sister") {
            case .bool(let on)?: sister = on
            case .string(let name)?: sister = !name.trimmed.isEmpty
            default: break
            }
            let photo = ShipPhoto(
                key: key, line: parts[0], className: parts[1], file: text("file"), url: text("url"),
                shipInPhoto: text("shipInPhoto"), sister: sister, author: text("author"), license: text("license"),
                commonsPage: text("commonsPage"),
                lengthFt: number(["lengthFt", "length_ft", "lenFt", "len_ft", "len", "length"]),
                aspect: number(["aspect", "ratio"]))
            guard photo.path != nil else { continue }
            out[key] = photo
        }
        return ShipPhotoManifest(photos: out)
    }
}

/// An American football field, end zone to end zone, for the size ruler.
enum ShipScale {
    static let fieldFeet: Double = 360

    /// "1,198 ft · 3.3 football fields"
    static func lengthText(_ feet: Double) -> String {
        let fields = feet / fieldFeet
        return "\(Fmt.usd(Int(feet.rounded())).replacingOccurrences(of: "$", with: "")) ft · " +
            String(format: "%.1f football fields", fields)
    }
}
