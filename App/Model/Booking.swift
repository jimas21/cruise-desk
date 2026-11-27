import Foundation

// MARK: - v4 features (CONTRACT_V4 rule 0.8)

/// What a v4 deal server lists in `GET /v1/catalog` `features`. Each one turns on by itself, only when the server
/// says apiVersion 4 or more and names it; otherwise the app keeps its v3 behaviour for that part.
enum V4Feature: String, CaseIterable, Hashable {
    case booking, digest, search, plans, trips
}

extension JSONValue {
    /// The value at `key` when this is an object.
    func field(_ key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.rounded() == value && abs(value) < 1e15: return Int(value)
        default: return nil
        }
    }

    var stringList: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap { $0.stringValue }
    }
}

extension Words {
    /// "you were in Cozumel" -> "You were in Cozumel"
    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }
}

// MARK: - The booking object (CONTRACT_V4 section 1.6)

/// How close a booking link gets to the sailing. A tier this version does not know is shown as non-exact, so its
/// note is always shown.
enum BookingTier: Equatable {
    case exact, sailing, route, month, ship, line
    case unknown(String)

    init(_ raw: String?) {
        switch raw?.trimmed ?? "" {
        case "exact": self = .exact
        case "sailing": self = .sailing
        case "route": self = .route
        case "month": self = .month
        case "ship": self = .ship
        case "line": self = .line
        default: self = .unknown(raw ?? "")
        }
    }
}

/// The line's own page for a sailing, built by the deal server from the catalog (never sent by the app).
struct BookingInfo: Codable, Hashable {
    var url: String?
    var tier: String?
    var label: String?
    var note: String?
    var verified: Bool?
    var codes: [String]?
    var builtAt: String?

    enum CodingKeys: String, CodingKey {
        case url, tier, label, note, verified, codes, builtAt
    }

    var link: URL? { Fmt.webURL(url) }
    var tierValue: BookingTier { BookingTier(tier) }

    /// The line under the button. Never shown for an exact link; always for any other tier (one this version does
    /// not know counts as non-exact), so the button never pretends to land on the sailing.
    var shownNote: String? {
        if tierValue == .exact { return nil }
        let text = note?.trimmed ?? ""
        return text.isEmpty ? "opens the line's own site" : text
    }

    /// Reads the `booking` field of a document, or nil when it is missing or not an object.
    static func from(_ data: JSONValue) -> BookingInfo? {
        guard let value = data.field("booking"), case .object = value,
              let info = value.decode(BookingInfo.self), info.link != nil else { return nil }
        return info
    }
}

extension BookingInfo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.lenient(String.self, .url)
        tier = c.lenient(String.self, .tier)
        label = c.lenient(String.self, .label)
        note = c.lenient(String.self, .note)
        verified = c.lenient(Bool.self, .verified)
        codes = c.lenient([String].self, .codes)
        builtAt = c.lenient(String.self, .builtAt)
    }
}

/// An agency that is clearly better than the line's own site for this sailing and cabin (CONTRACT_V4 section 1.7).
/// The server includes one only with a stated reason; the app also never shows one without it.
struct BookAlternative: Codable, Hashable {
    var agency: String?
    var url: String?
    var pricePP: Int?
    var taxesIncluded: Bool?
    var cabinClass: String?
    var perks: [String]?
    var whyBetter: String?

    enum CodingKeys: String, CodingKey {
        case agency, url, pricePP, taxesIncluded, cabinClass, perks, whyBetter
    }

    var link: URL? { Fmt.webURL(url) }
    var name: String { agency?.trimmed ?? "" }
    var reason: String { whyBetter?.trimmed ?? "" }

    /// Shown only with an agency, a page to open and a reason.
    var isShowable: Bool { link != nil && !name.isEmpty && !reason.isEmpty }

    /// "Or Costco Travel · same fare + $250 Shop Card"
    var rowTitle: String { "Or \(name) · \(reason)" }

    /// The agency's sheet list, at most 3, each with its reason.
    static func from(_ data: JSONValue) -> [BookAlternative] {
        guard let value = data.field("bookAlternatives"), case .array(let items) = value else { return [] }
        return Array(items.compactMap { $0.decode(BookAlternative.self) }.filter { $0.isShowable }.prefix(3))
    }
}

extension BookAlternative {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agency = c.lenient(String.self, .agency)
        url = c.lenient(String.self, .url)
        pricePP = c.lenient(Int.self, .pricePP)
        taxesIncluded = c.lenient(Bool.self, .taxesIncluded)
        cabinClass = c.lenient(String.self, .cabinClass)
        perks = c.lenient([String].self, .perks)
        whyBetter = c.lenient(String.self, .whyBetter)
    }
}

/// `prefs/trip.bookingPreference`: the line's own site (the default) or the best value.
enum BookingPreference: String, CaseIterable, Identifiable {
    case line
    case bestValue = "best-value"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "The cruise line"
        case .bestValue: return "Best value"
        }
    }

    var detail: String {
        switch self {
        case .line: return "Book on the line's own site. An agency shows only when it is clearly better, with the reason."
        case .bestValue: return "Still opens the line's own site first; the cheapest known agency for that cabin is listed under it."
        }
    }

    init(raw: String?) {
        self = BookingPreference(rawValue: raw ?? "") ?? .line
    }
}

// MARK: - What the Book button opens

/// Everything one row or detail needs to hand Jim off to book: the primary button (always the sailing's own line),
/// the line under it, a small "Seen on <source>" link, and at most 3 agencies that are clearly better.
struct BookChoice: Equatable {
    struct Target: Equatable {
        var title: String
        var url: URL
    }

    struct Source: Equatable {
        var name: String
        var url: URL
    }

    var primary: Target?
    /// "opens Royal's search for Icon · Aug 15, 2027", or why there is no button.
    var note: String?
    var seenOn: Source?
    var alternatives: [BookAlternative] = []

    var isEmpty: Bool { primary == nil && note == nil && seenOn == nil && alternatives.isEmpty }

    /// v4 (`booking` listed): the line's own page from the server, else the line's home page from the catalog, never
    /// an agency. Otherwise (and for a sale, whose own page is the point) the deal's `link` as before.
    static func make(line: String, ship: String?, booking: BookingInfo?, link: String?, linkLabel: String?,
                     sources: [DealSource], pricePP: Int?, alternatives: [BookAlternative], v4: Bool,
                     isSale: Bool = false, catalog: Catalog = CatalogIndex.current) -> BookChoice {
        guard v4, !isSale else {
            return legacy(link: link, linkLabel: linkLabel, isSale: isSale)
        }
        var choice = BookChoice()
        if let booking, let url = booking.link {
            let label = booking.label?.trimmed ?? ""
            choice.primary = Target(title: label.isEmpty ? "Book on \(line)" : label.capped(30), url: url)
            choice.note = booking.shownNote
        } else if let spec = catalog.line(line)?.booking, let home = Fmt.webURL(spec.home),
                  !CruiseLine.same(line, CruiseLine.other) {
            let label = spec.label?.trimmed ?? ""
            choice.primary = Target(title: label.isEmpty ? "Book on \(line)" : label.capped(30), url: home)
            let short = (spec.short?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? line
            if let ship = ship?.trimmed, !ship.isEmpty {
                choice.note = "opens \(short)'s site · find \(ship) there"
            } else {
                choice.note = "opens \(short)'s site"
            }
        } else {
            choice.note = "no booking link for \(line) yet"
        }
        choice.seenOn = seenOn(sources: sources, pricePP: pricePP, excluding: choice.primary?.url)
        choice.alternatives = Array(alternatives.filter { $0.isShowable }.prefix(3))
        return choice
    }

    /// v3 behaviour: `link` / `linkLabel` (a v4 server has already set them to the line's page on a sailing deal).
    static func legacy(link: String?, linkLabel: String?, isSale: Bool) -> BookChoice {
        guard let url = Fmt.webURL(link) else { return BookChoice() }
        let label = linkLabel?.trimmed ?? ""
        var choice = BookChoice()
        if label.lowercased().hasPrefix("book on ") {
            choice.primary = Target(title: label.capped(30), url: url)
        } else {
            choice.primary = Target(title: isSale ? "See the sale" : "Open deal", url: url)
            if !label.isEmpty { choice.note = "opens \(label)" }
        }
        return choice
    }

    /// The source whose price equals the deal's, else the first one; never the same page as the button.
    static func seenOn(sources: [DealSource], pricePP: Int?, excluding: URL?) -> Source? {
        let usable = sources.compactMap { source -> (DealSource, URL)? in
            guard let url = Fmt.webURL(source.url), !source.name.trimmed.isEmpty, url != excluding else { return nil }
            return (source, url)
        }
        let match = usable.first { pricePP != nil && $0.0.pricePP == pricePP } ?? usable.first
        guard let match else { return nil }
        return Source(name: match.0.name.trimmed.capped(30), url: match.1)
    }
}

/// `POST /v1/link/parse`: what the deal server reads from a line's own link (its text only; nothing is fetched).
struct LinkParse: Decodable, Equatable {
    var line: String?
    var tier: String?
    var sailDate: String?
    var ship: String?
    var lineUrl: String?

    enum CodingKeys: String, CodingKey {
        case line, tier, sailDate, ship, lineUrl
    }

    init(line: String?, tier: String?, sailDate: String?, ship: String?, lineUrl: String?) {
        self.line = line
        self.tier = tier
        self.sailDate = sailDate
        self.ship = ship
        self.lineUrl = lineUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = c.lenient(String.self, .line)
        tier = c.lenient(String.self, .tier)
        sailDate = c.lenient(String.self, .sailDate)
        ship = c.lenient(String.self, .ship)
        lineUrl = c.lenient(String.self, .lineUrl)
    }
}
