import Foundation

// MARK: - Cruise lines (CONTRACT_V3 section 1)

/// The lines Deal Desk knows, by the exact names the deal server stores. A deal, watch or tracked sailing with no
/// `line` is Royal Caribbean, the line covered first.
enum CruiseLine {
    static let royal = "Royal Caribbean"
    static let other = "Other"

    static let names = ["Royal Caribbean", "Celebrity", "Norwegian", "MSC", "Carnival", "Princess", "Virgin Voyages",
                        "Holland America", "Disney", "Cunard", "Oceania", "Viking", "Other"]

    /// The lines My Lines offers: the server's own list when it has one, else the built-in names ("Other" is only
    /// ever a deal's line, never a choice).
    static func choosable(_ catalog: Catalog = CatalogIndex.current) -> [String] {
        catalog.lineNames.filter { !same($0, other) }
    }

    /// "Holland America" -> "holland-america"
    static func slug(_ name: String) -> String { Slug.plain(name) }

    /// Absent or empty means Royal Caribbean.
    static func resolved(_ name: String?) -> String {
        let text = name?.trimmed ?? ""
        return text.isEmpty ? royal : text
    }

    static func isRoyal(_ name: String?) -> Bool { same(resolved(name), royal) }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmed.caseInsensitiveCompare(b.trimmed) == .orderedSame || slug(a) == slug(b)
    }

    /// The canonical name for a line's name, slug or a common way of writing it ("RCI", "celebrity-cruises").
    static func canonical(_ text: String, catalog: Catalog = CatalogIndex.current) -> String? {
        let s = slug(text)
        guard !s.isEmpty else { return nil }
        let known = catalog.lineNames + names.filter { name in !catalog.lineNames.contains(where: { same($0, name) }) }
        if let exact = known.first(where: { slug($0) == s }) { return exact }
        if let alias = aliases[s] { return alias }
        // "celebrity-cruises", "norwegian-cruise-line", "carnival-cruise-line", "royal-caribbean-international"
        return known.first { name in
            let n = slug(name)
            return n != slug(other) && s.hasPrefix(n + "-")
        }
    }

    private static let aliases: [String: String] = [
        "rci": royal, "rcl": royal, "royal": royal, "ncl": "Norwegian", "virgin": "Virgin Voyages",
        "hal": "Holland America", "disney-cruise": "Disney",
    ]

    /// The line whose own website a link is on.
    static func fromHost(_ host: String) -> String? {
        let h = host.lowercased()
        let sites: [(String, String)] = [
            ("royalcaribbean.", royal), ("celebritycruises.", "Celebrity"), ("ncl.com", "Norwegian"),
            ("msccruises", "MSC"), ("carnival.com", "Carnival"), ("princess.com", "Princess"),
            ("virginvoyages.", "Virgin Voyages"), ("hollandamerica.", "Holland America"), ("disneycruise.", "Disney"),
            ("cunard.", "Cunard"), ("oceaniacruises.", "Oceania"), ("vikingcruises.", "Viking"), ("viking.com", "Viking"),
        ]
        return sites.first { h.contains($0.0) }?.1
    }
}

enum Slug {
    /// Lowercase; every run of anything that is not a letter a-z or a digit becomes one "-", none at the ends.
    static func plain(_ text: String) -> String {
        var out = ""
        var gap = false
        for scalar in text.lowercased().unicodeScalars {
            let keep = (97...122).contains(scalar.value) || (48...57).contains(scalar.value)
            if keep {
                if gap && !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                gap = false
            } else {
                gap = true
            }
        }
        return out
    }

    /// The server's `identity.ship_slug`: accents dropped, "'s " removed, Royal noise words stripped, then `plain`.
    /// "Royal Caribbean's Icon of the Seas" -> "icon-of-the-seas".
    static func ship(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.decomposedStringWithCompatibilityMapping.unicodeScalars
        where scalar.properties.canonicalCombiningClass.rawValue == 0 {
            scalars.append(scalar)
        }
        var s = String(scalars)
        s = s.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "'s ", with: " ")
        if let noise {
            s = noise.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                               withTemplate: " ")
        }
        return plain(s)
    }

    private static let noise = try? NSRegularExpression(
        pattern: #"\b(royal caribbean international|royal caribbean|rcl|rci|m/?s|m/?v|ss)\b"#,
        options: [.caseInsensitive])
}

enum Words {
    /// "needs_jim" -> "Needs jim", "tracking-live" -> "Tracking live": how an unknown value is shown, neutrally.
    static func humanize(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmed
        guard let first = words.first else { return raw }
        return first.uppercased() + words.dropFirst()
    }

    /// "icon-of-the-seas" -> "Icon of the Seas"
    static func title(fromSlug slug: String) -> String {
        let small: Set<String> = ["of", "the", "and", "a", "at", "by", "for", "in", "on"]
        let parts = slug.split(separator: "-").map(String.init)
        return parts.enumerated().map { item -> String in
            let word = item.element.lowercased()
            if item.offset > 0 && small.contains(word) { return word }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

// MARK: - Ship size tiers

/// The cross-line size tier, by gross tonnage, so size works the same on every line.
enum ShipSize: String, CaseIterable, Identifiable {
    case small, mid, large, mega

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .mid: return "Mid-size"
        case .large: return "Large"
        case .mega: return "Mega"
        }
    }

    /// "Mega ship"
    var shipTitle: String { "\(title) ship" }

    var tonnage: String {
        switch self {
        case .small: return "under 70k tons"
        case .mid: return "70k–120k tons"
        case .large: return "120k–180k tons"
        case .mega: return "180k tons and up"
        }
    }

    /// small < 70,000 · mid 70,000-119,999 · large 120,000-179,999 · mega >= 180,000
    static func tier(gt: Int?) -> ShipSize? {
        guard let gt, gt > 0 else { return nil }
        if gt < 70_000 { return .small }
        if gt < 120_000 { return .mid }
        if gt < 180_000 { return .large }
        return .mega
    }

    /// A tier's ship title, or an unknown value shown plainly.
    static func shipTitle(_ raw: String?) -> String? {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        return ShipSize(rawValue: raw)?.shipTitle ?? "\(Words.humanize(raw)) ship"
    }
}

// MARK: - What Deal Desk can see for a line

/// `coverage` on a catalog line and on a tracked sailing: tracking_live | limited_data | news_only. A value this
/// version does not know is shown as it is, never dropped.
enum Coverage: Equatable {
    case live, limited, newsOnly
    case unknown(String)

    init?(_ raw: String?) {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        switch raw {
        case "tracking_live": self = .live
        case "limited_data": self = .limited
        case "news_only": self = .newsOnly
        default: self = .unknown(raw)
        }
    }

    var title: String {
        switch self {
        case .live: return "Tracking live"
        case .limited: return "Limited data"
        case .newsOnly: return "News only"
        case .unknown(let raw): return Words.humanize(raw)
        }
    }

    var detail: String {
        switch self {
        case .live: return "A fare source Deal Desk reads has current prices."
        case .limited: return "Only alert emails or older fares so far."
        case .newsOnly: return "No price source yet: news and leads only."
        case .unknown: return "What Deal Desk can see here is new to this version of the app."
        }
    }
}

// MARK: - The catalog (`GET /v1/catalog`)

extension KeyedDecodingContainer {
    /// The value at `key`, or nil when it is missing, null or of another type: one odd field never hides the rest.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

struct CatalogShip: Codable, Hashable {
    var name: String?
    var slug: String?
    var className: String?
    var classSlug: String?
    var size: String?
    var gt: Int?
    // v4
    /// The line's own ship code ("IC"), when the catalog has one.
    var code: String? = nil
    var passengers: Int? = nil
    var maidenYear: Int? = nil

    enum CodingKeys: String, CodingKey {
        case name, slug
        case className = "class"
        case classSlug, size, gt
        case code, passengers, maidenYear
    }

    /// The slug the server matches on (its own, else worked out from the name the same way).
    var key: String {
        if let slug, !slug.isEmpty { return slug }
        return Slug.ship(name ?? "")
    }

    var tier: ShipSize? { ShipSize(rawValue: size ?? "") ?? ShipSize.tier(gt: gt) }
}

extension CatalogShip {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, .name)
        slug = c.lenient(String.self, .slug)
        className = c.lenient(String.self, .className)
        classSlug = c.lenient(String.self, .classSlug)
        size = c.lenient(String.self, .size)
        gt = c.lenient(Int.self, .gt)
        code = c.lenient(String.self, .code)
        passengers = c.lenient(Int.self, .passengers)
        maidenYear = c.lenient(Int.self, .maidenYear)
    }
}

/// v4: how a line's own booking pages are reached (`lines[].booking` in `GET /v1/catalog`).
struct CatalogBooking: Codable, Hashable {
    struct Tier: Codable, Hashable {
        var tier: String?
        var verified: Bool?
    }

    var label: String?
    var short: String?
    var home: String?
    var tiers: [Tier]?

    enum CodingKeys: String, CodingKey {
        case label, short, home, tiers
    }
}

extension CatalogBooking {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = c.lenient(String.self, .label)
        short = c.lenient(String.self, .short)
        home = c.lenient(String.self, .home)
        tiers = c.lenient([Tier].self, .tiers)
    }
}

struct CatalogLine: Codable, Hashable {
    var name: String?
    var slug: String?
    var coverage: String?
    var coverageNote: String?
    var liveSources: [String]?
    var sailings: Int?
    var ships: [CatalogShip]?
    // v4
    var booking: CatalogBooking? = nil

    enum CodingKeys: String, CodingKey {
        case name, slug, coverage, coverageNote, liveSources, sailings, ships, booking
    }

    var coverageState: Coverage? { Coverage(coverage) }
}

extension CatalogLine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, .name)
        slug = c.lenient(String.self, .slug)
        coverage = c.lenient(String.self, .coverage)
        coverageNote = c.lenient(String.self, .coverageNote)
        liveSources = c.lenient([String].self, .liveSources)
        sailings = c.lenient(Int.self, .sailings)
        ships = c.lenient([CatalogShip].self, .ships)
        booking = c.lenient(CatalogBooking.self, .booking)
    }
}

struct CatalogSize: Codable, Hashable {
    var tier: String?
    var label: String?
    var gtMin: Int?
    var gtMax: Int?

    enum CodingKeys: String, CodingKey {
        case tier, label, gtMin, gtMax
    }
}

extension CatalogSize {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tier = c.lenient(String.self, .tier)
        label = c.lenient(String.self, .label)
        gtMin = c.lenient(Int.self, .gtMin)
        gtMax = c.lenient(Int.self, .gtMax)
    }
}

struct Catalog: Codable, Hashable {
    var apiVersion: Int?
    var catalogVersion: Int?
    var generatedAt: String?
    var sizes: [CatalogSize]?
    var lines: [CatalogLine]?
    // v4
    var features: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case apiVersion, catalogVersion, generatedAt, sizes, lines, features
    }

    /// The deal server speaks v3 (lines, tracking, the refresh nudge).
    var isV3: Bool { (apiVersion ?? 0) >= 3 }

    /// A v4 feature is on only when the server says apiVersion 4 or more and lists it (CONTRACT_V4 rule 0.8).
    func has(_ feature: V4Feature) -> Bool {
        (apiVersion ?? 0) >= 4 && (features ?? []).contains(feature.rawValue)
    }

    /// Every line name, in the server's order; the built-in names when the server gave none.
    var lineNames: [String] {
        let named = (lines ?? []).compactMap { $0.name?.trimmed }.filter { !$0.isEmpty }
        return named.isEmpty ? CruiseLine.names : named
    }

    func line(_ name: String?) -> CatalogLine? {
        let wanted = CruiseLine.resolved(name)
        return (lines ?? []).first { line in
            if let n = line.name, CruiseLine.same(n, wanted) { return true }
            if let s = line.slug, s == CruiseLine.slug(wanted) { return true }
            return false
        }
    }

    /// A line's ships: the server's list, else the built-in copy (the Royal fleet).
    func ships(for name: String?) -> [CatalogShip] {
        let own = line(name)?.ships ?? []
        if !own.isEmpty { return own }
        return Catalog.builtIn.line(name)?.ships ?? []
    }

    func ship(line: String?, named ship: String?) -> CatalogShip? {
        guard let ship, !ship.trimmed.isEmpty else { return nil }
        let key = Slug.ship(ship)
        return ships(for: line).first { $0.key == key }
    }

    /// The size tier of a line's ship, when the catalog knows the ship.
    func size(line: String?, ship: String?) -> ShipSize? {
        self.ship(line: line, named: ship)?.tier
    }

    /// "Edge class" for another line's class slug, from the catalog's own class name when it has one.
    func classTitle(line: String?, classSlug: String?, ship: String?) -> String? {
        if let known = self.ship(line: line, named: ship), let name = known.className?.trimmed, !name.isEmpty {
            return "\(name) class"
        }
        guard let slug = classSlug?.trimmed, !slug.isEmpty, slug != "other" else { return nil }
        if let match = ships(for: line).first(where: { $0.classSlug == slug }), let name = match.className, !name.isEmpty {
            return "\(name) class"
        }
        return "\(Words.title(fromSlug: slug)) class"
    }

    /// The line names plus the Royal fleet by class (CONTRACT_V3 section 1): what the app knows with no server.
    /// Never v3 on its own (no apiVersion).
    static let builtIn: Catalog = {
        let royal: [(String, String, String, ShipSize)] = [
            ("Icon of the Seas", "Icon", "icon", .mega), ("Star of the Seas", "Icon", "icon", .mega),
            ("Legend of the Seas", "Icon", "icon", .mega),
            ("Oasis of the Seas", "Oasis", "oasis", .mega), ("Allure of the Seas", "Oasis", "oasis", .mega),
            ("Harmony of the Seas", "Oasis", "oasis", .mega), ("Symphony of the Seas", "Oasis", "oasis", .mega),
            ("Wonder of the Seas", "Oasis", "oasis", .mega), ("Utopia of the Seas", "Oasis", "oasis", .mega),
            ("Quantum of the Seas", "Quantum", "quantum", .large), ("Anthem of the Seas", "Quantum", "quantum", .large),
            ("Ovation of the Seas", "Quantum", "quantum", .large), ("Spectrum of the Seas", "Quantum", "quantum", .large),
            ("Odyssey of the Seas", "Quantum", "quantum", .large),
            ("Freedom of the Seas", "Freedom", "other", .large), ("Liberty of the Seas", "Freedom", "other", .large),
            ("Independence of the Seas", "Freedom", "other", .large),
            ("Voyager of the Seas", "Voyager", "other", .large), ("Explorer of the Seas", "Voyager", "other", .large),
            ("Adventure of the Seas", "Voyager", "other", .large), ("Navigator of the Seas", "Voyager", "other", .large),
            ("Mariner of the Seas", "Voyager", "other", .large),
            ("Radiance of the Seas", "Radiance", "other", .mid), ("Brilliance of the Seas", "Radiance", "other", .mid),
            ("Serenade of the Seas", "Radiance", "other", .mid), ("Jewel of the Seas", "Radiance", "other", .mid),
            ("Grandeur of the Seas", "Vision", "other", .mid), ("Enchantment of the Seas", "Vision", "other", .mid),
            ("Vision of the Seas", "Vision", "other", .mid), ("Rhapsody of the Seas", "Vision", "other", .mid),
        ]
        let fleet = royal.map { item in
            CatalogShip(name: item.0, slug: Slug.ship(item.0), className: item.1, classSlug: item.2,
                        size: item.3.rawValue, gt: nil)
        }
        let lines = CruiseLine.names.map { name in
            CatalogLine(name: name, slug: CruiseLine.slug(name), coverage: nil, coverageNote: nil, liveSources: nil,
                        sailings: nil, ships: name == CruiseLine.royal ? fleet : [])
        }
        return Catalog(apiVersion: nil, catalogVersion: nil, generatedAt: nil, sizes: nil, lines: lines)
    }()
}

extension Catalog {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = c.lenient(Int.self, .apiVersion)
        catalogVersion = c.lenient(Int.self, .catalogVersion)
        generatedAt = c.lenient(String.self, .generatedAt)
        sizes = c.lenient([CatalogSize].self, .sizes)
        lines = c.lenient([CatalogLine].self, .lines)
        features = c.lenient([String].self, .features)
    }
}

/// The catalog the screens read: the deal server's (v3) or the built-in copy. The Store keeps it current.
enum CatalogIndex {
    static var current: Catalog = .builtIn
}
