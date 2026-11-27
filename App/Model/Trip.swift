import Foundation

// MARK: - Trip settings (`prefs/trip`)

/// Jim's trip settings, edited in My Trip (DESIGN_V2 section 1). The app writes the document, the brain reads it
/// every run, and the phone re-buckets deals from it straight away. Every field has a default, so a document with
/// missing or newer fields still decodes; the defaults here are deliberately generic (the real settings live on
/// the deal server, never in this public repository).
struct TripPrefs: Decodable, Equatable {
    var shipClasses: [String] = ["icon", "oasis", "quantum", "other"]
    var preferredClasses: [String] = []
    var excludeShips: [String] = []
    var nightsMin: Int = 3
    var nightsMax: Int = 10
    var nightsPreferredMin: Int? = nil
    var cabinTypes: [String] = ["interior", "oceanview", "balcony", "suite"]
    var requireOceanView: Bool = false
    var excludeBalconyTypes: [String] = []
    var adults: Int = 2
    var children: Int = 0
    var childAges: [Int]? = nil
    var budgetTotal: Int = 5000
    var tradeoffBudget: Int? = nil
    var homeAirport: String? = nil
    var portsPreferred: [String] = []
    var portsExcluded: [String] = []
    var regions: [String] = []
    var dateFrom: String? = nil
    var dateTo: String? = nil
    var avoidHolidays: Bool = false
    var mustSeeMinScore: Int = 80
    var alertForMyTrip: Bool = true
    var alertMustSee: Bool = true
    var quietHoursStart: String? = nil
    var quietHoursEnd: String? = nil
    var notes: String? = nil
    var updatedAt: String? = nil
    // v3 (CONTRACT_V3 section 2). Sent only to a v3 deal server; an older one refuses fields it doesn't know.
    /// nil: absent on the server, which means Royal Caribbean only. `[]` means every line.
    var lines: [String]? = nil
    var shipSizes: [String] = []
    var dealTypes: [String] = []
    var minPctUnder: Int = 15
    var minScore: Int? = nil
    var sailMonths: [Int] = []
    var refreshMinutes: Int = 30

    /// Balcony kinds My Trip can rule out (the ids the server stores, and how they read).
    static let balconyKinds: [(id: String, title: String)] = [
        ("infinite", "Infinite"), ("central-park", "Central Park"), ("boardwalk", "Boardwalk"), ("surfside", "Surfside"),
    ]

    enum CodingKeys: String, CodingKey {
        case shipClasses, preferredClasses, excludeShips, nightsMin, nightsMax, nightsPreferredMin, cabinTypes
        case requireOceanView, excludeBalconyTypes, adults, children, childAges, budgetTotal, tradeoffBudget
        case homeAirport, portsPreferred, portsExcluded, regions, dateFrom, dateTo, avoidHolidays, mustSeeMinScore
        case alertForMyTrip, alertMustSee, quietHoursStart, quietHoursEnd, notes, updatedAt
        case lines, shipSizes, dealTypes, minPctUnder, minScore, sailMonths, refreshMinutes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        func maybe<T: Decodable>(_ key: CodingKeys, _ type: T.Type) -> T? {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        let base = TripPrefs()
        shipClasses = value(.shipClasses, base.shipClasses)
        preferredClasses = value(.preferredClasses, base.preferredClasses)
        excludeShips = value(.excludeShips, base.excludeShips)
        nightsMin = value(.nightsMin, base.nightsMin)
        nightsMax = value(.nightsMax, base.nightsMax)
        nightsPreferredMin = maybe(.nightsPreferredMin, Int.self)
        cabinTypes = value(.cabinTypes, base.cabinTypes)
        requireOceanView = value(.requireOceanView, base.requireOceanView)
        excludeBalconyTypes = value(.excludeBalconyTypes, base.excludeBalconyTypes)
        adults = value(.adults, base.adults)
        children = value(.children, base.children)
        childAges = maybe(.childAges, [Int].self)
        budgetTotal = value(.budgetTotal, base.budgetTotal)
        tradeoffBudget = maybe(.tradeoffBudget, Int.self)
        homeAirport = maybe(.homeAirport, String.self)
        portsPreferred = value(.portsPreferred, base.portsPreferred)
        portsExcluded = value(.portsExcluded, base.portsExcluded)
        regions = value(.regions, base.regions)
        dateFrom = maybe(.dateFrom, String.self)
        dateTo = maybe(.dateTo, String.self)
        avoidHolidays = value(.avoidHolidays, base.avoidHolidays)
        mustSeeMinScore = value(.mustSeeMinScore, base.mustSeeMinScore)
        alertForMyTrip = value(.alertForMyTrip, base.alertForMyTrip)
        alertMustSee = value(.alertMustSee, base.alertMustSee)
        quietHoursStart = maybe(.quietHoursStart, String.self)
        quietHoursEnd = maybe(.quietHoursEnd, String.self)
        notes = maybe(.notes, String.self)
        updatedAt = maybe(.updatedAt, String.self)
        lines = maybe(.lines, [String].self)
        shipSizes = value(.shipSizes, base.shipSizes)
        dealTypes = value(.dealTypes, base.dealTypes)
        minPctUnder = value(.minPctUnder, base.minPctUnder)
        minScore = maybe(.minScore, Int.self)
        sailMonths = value(.sailMonths, base.sailMonths)
        refreshMinutes = value(.refreshMinutes, base.refreshMinutes)
    }

    var party: Int { max(adults + children, 1) }

    /// The lines that count: absent means Royal Caribbean only (the legacy default); empty means every line.
    var effectiveLines: [String] { lines ?? [CruiseLine.royal] }

    /// Royal Caribbean is one of the lines that count (its class settings apply only then).
    var includesRoyal: Bool {
        effectiveLines.isEmpty || effectiveLines.contains { CruiseLine.same($0, CruiseLine.royal) }
    }

    /// "Royal Caribbean", "Royal Caribbean & Celebrity", "Royal Caribbean +2" or "Any line".
    var linesSummary: String {
        let chosen = effectiveLines
        if chosen.isEmpty { return "Any line" }
        if chosen.count == 1 { return chosen[0] }
        if chosen.count == 2 { return "\(chosen[0]) & \(chosen[1])" }
        return "\(chosen[0]) +\(chosen.count - 1)"
    }

    /// The same settings, trimmed to what the server accepts (schema caps, nightsMin <= nightsMax, dateFrom <=
    /// dateTo), so a save can never be refused for its shape.
    func cleaned() -> TripPrefs {
        var p = self
        func list(_ items: [String], each: Int, most: Int, allowed: [String]? = nil) -> [String] {
            var out: [String] = []
            for item in items {
                let text = item.trimmed.capped(each)
                guard !text.isEmpty, !out.contains(text) else { continue }
                if let allowed, !allowed.contains(text) { continue }
                out.append(text)
            }
            return Array(out.prefix(most))
        }
        let classes = ShipClass.allCases.map { $0.rawValue }
        p.shipClasses = list(shipClasses, each: 10, most: 4, allowed: classes)
        p.preferredClasses = list(preferredClasses, each: 10, most: 4, allowed: classes)
        p.excludeShips = list(excludeShips, each: 40, most: 30)
        p.nightsMin = min(max(nightsMin, 1), 30)
        p.nightsMax = min(max(nightsMax, 1), 30)
        if p.nightsMin > p.nightsMax { (p.nightsMin, p.nightsMax) = (p.nightsMax, p.nightsMin) }
        p.nightsPreferredMin = nightsPreferredMin.map { min(max($0, 1), 30) }
        p.cabinTypes = list(cabinTypes, each: 10, most: 4, allowed: ["interior", "oceanview", "balcony", "suite"])
        p.excludeBalconyTypes = list(excludeBalconyTypes, each: 30, most: 10)
        p.adults = min(max(adults, 1), 8)
        p.children = min(max(children, 0), 8)
        if let ages = childAges?.map({ min(max($0, 0), 17) }), !ages.isEmpty {
            p.childAges = Array(ages.prefix(8))
        } else {
            p.childAges = nil
        }
        p.budgetTotal = min(max(budgetTotal, 0), 1_000_000)
        p.tradeoffBudget = tradeoffBudget.map { min(max($0, 0), 1_000_000) }
        let airport = (homeAirport ?? "").trimmed.uppercased().capped(4)
        p.homeAirport = airport.isEmpty ? nil : airport
        p.portsPreferred = list(portsPreferred, each: 30, most: 20)
        p.portsExcluded = list(portsExcluded, each: 30, most: 20)
        p.regions = list(regions, each: 30, most: 12)
        p.dateFrom = dateFrom.flatMap { Fmt.day($0) }.map { Fmt.isoDay($0) }
        p.dateTo = dateTo.flatMap { Fmt.day($0) }.map { Fmt.isoDay($0) }
        if let from = p.dateFrom, let to = p.dateTo, from > to {
            p.dateFrom = to
            p.dateTo = from
        }
        p.mustSeeMinScore = min(max(mustSeeMinScore, 0), 100)
        p.quietHoursStart = quietHoursStart.flatMap { Fmt.clock($0) }.map { Fmt.clockText($0) }
        p.quietHoursEnd = quietHoursEnd.flatMap { Fmt.clock($0) }.map { Fmt.clockText($0) }
        let note = (notes ?? "").trimmed.capped(500)
        p.notes = note.isEmpty ? nil : note
        if let chosen = lines {
            var out: [String] = []
            for name in chosen {
                guard let known = CruiseLine.canonical(name), !CruiseLine.same(known, CruiseLine.other),
                      !out.contains(known) else { continue }
                out.append(known)
            }
            p.lines = Array(out.prefix(12))
        }
        p.shipSizes = list(shipSizes, each: 10, most: 4, allowed: ShipSize.allCases.map { $0.rawValue })
        p.dealTypes = list(dealTypes, each: 20, most: 5, allowed: DealType.allCases.map { $0.rawValue })
        p.minPctUnder = min(max(minPctUnder, 0), 90)
        p.minScore = minScore.map { min(max($0, 0), 100) }
        var months: [Int] = []
        for month in sailMonths where (1...12).contains(month) && !months.contains(month) { months.append(month) }
        p.sailMonths = months.sorted()
        p.refreshMinutes = [15, 30, 60].contains(refreshMinutes) ? refreshMinutes : 30
        return p
    }

    /// Every field as the server stores it. Unset optional fields are sent as `null`, so a save replaces the
    /// whole document (PATCH removes a field that is `null`; a first PUT simply leaves it out). The v3 fields go
    /// only to a v3 server (`v3`); an older one would refuse them, and its PATCH leaves them alone.
    func fields(stamp: String = Fmt.stamp(), v3: Bool = false) -> [String: JSONValue] {
        func strings(_ items: [String]) -> JSONValue { .array(items.map { JSONValue.string($0) }) }
        func text(_ value: String?) -> JSONValue { value.map { JSONValue.string($0) } ?? .null }
        func number(_ value: Int?) -> JSONValue { value.map { JSONValue.int($0) } ?? .null }
        var f: [String: JSONValue] = [:]
        f["shipClasses"] = strings(shipClasses)
        f["preferredClasses"] = strings(preferredClasses)
        f["excludeShips"] = strings(excludeShips)
        f["nightsMin"] = .int(nightsMin)
        f["nightsMax"] = .int(nightsMax)
        f["nightsPreferredMin"] = number(nightsPreferredMin)
        f["cabinTypes"] = strings(cabinTypes)
        f["requireOceanView"] = .bool(requireOceanView)
        f["excludeBalconyTypes"] = strings(excludeBalconyTypes)
        f["adults"] = .int(adults)
        f["children"] = .int(children)
        f["childAges"] = childAges.map { ages in JSONValue.array(ages.map { JSONValue.int($0) }) } ?? .null
        f["budgetTotal"] = .int(budgetTotal)
        f["tradeoffBudget"] = number(tradeoffBudget)
        f["homeAirport"] = text(homeAirport)
        f["portsPreferred"] = strings(portsPreferred)
        f["portsExcluded"] = strings(portsExcluded)
        f["regions"] = strings(regions)
        f["dateFrom"] = text(dateFrom)
        f["dateTo"] = text(dateTo)
        f["avoidHolidays"] = .bool(avoidHolidays)
        f["mustSeeMinScore"] = .int(mustSeeMinScore)
        f["alertForMyTrip"] = .bool(alertForMyTrip)
        f["alertMustSee"] = .bool(alertMustSee)
        f["quietHoursStart"] = text(quietHoursStart)
        f["quietHoursEnd"] = text(quietHoursEnd)
        f["notes"] = text(notes)
        f["updatedAt"] = .string(stamp)
        if v3 {
            // A v3 app always says which lines: that is how the brain knows a v3 app has saved them.
            f["lines"] = strings(effectiveLines)
            f["shipSizes"] = strings(shipSizes)
            f["dealTypes"] = strings(dealTypes)
            f["minPctUnder"] = .int(minPctUnder)
            f["minScore"] = number(minScore)
            f["sailMonths"] = .array(sailMonths.map { JSONValue.int($0) })
            f["refreshMinutes"] = .int(refreshMinutes)
        }
        return f
    }

    /// One glance line for the For my trip bucket: "Icon · Oasis · 4–7 nights · Balcony, ocean view · under $3,000".
    var summary: String {
        var parts: [String] = []
        if lines != nil { parts.append(linesSummary) }
        let classes = ShipClass.allCases.filter { shipClasses.contains($0.rawValue) }
        if includesRoyal && !classes.isEmpty && classes.count < ShipClass.allCases.count {
            parts.append(classes.map { $0.short }.joined(separator: " · "))
        }
        let sizes = ShipSize.allCases.filter { shipSizes.contains($0.rawValue) }
        if !sizes.isEmpty && sizes.count < ShipSize.allCases.count {
            parts.append(sizes.map { $0.title }.joined(separator: " or ") + " ships")
        }
        parts.append(nightsMin == nightsMax ? Fmt.nights(nightsMin) : "\(nightsMin)–\(nightsMax) nights")
        let cabins = ["interior", "oceanview", "balcony", "suite"].filter { cabinTypes.contains($0) }
        if !cabins.isEmpty && cabins.count < 4 {
            var cabin = cabins.compactMap { CabinType(rawValue: $0)?.title }.joined(separator: " or ")
            if requireOceanView && cabins.contains("balcony") { cabin += ", ocean view" }
            parts.append(cabin)
        }
        parts.append("under \(Fmt.usd(max(budgetTotal, tradeoffBudget ?? 0)))")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Does a deal fit the trip?

struct TripFit: Equatable {
    var fits: Bool
    /// Short reasons it doesn't ("4 nights", "Over $3,000"); shown as a caption in Best deals.
    var reasons: [String] = []
    /// Fits, but in the trade-off price zone.
    var tradeoff: String? = nil
    /// A preferred ship class, port or length: breaks ties in For my trip.
    var preferred: Bool = false
}

/// The same rules the brain applies (prompt.md section 2), worked out on the phone so the buckets move the moment
/// Jim changes a setting. Unknown facts never fail a deal; the card already says what is unconfirmed.
enum TripCheck {
    static func verdict(for deal: Deal, prefs: TripPrefs?) -> TripFit {
        if let prefs { return evaluate(deal, prefs) }
        // No settings on this phone yet: use the brain's own verdict from when it wrote the deal.
        if deal.kind == .sale { return TripFit(fits: false) }
        let reasons = deal.data.failsBecause ?? (deal.data.breaks.map { [$0] } ?? [])
        return TripFit(fits: deal.data.fitsTrip ?? (deal.kind == .fits), reasons: reasons)
    }

    static func evaluate(_ deal: Deal, _ p: TripPrefs) -> TripFit {
        if deal.kind == .sale { return TripFit(fits: false) }
        let d = deal.data
        var why: [String] = []
        var preferred = false

        // v3: the line must be one Jim picked (absent = Royal Caribbean only, empty = every line).
        let lines = p.effectiveLines
        if !lines.isEmpty && !lines.contains(where: { CruiseLine.same($0, deal.line) }) {
            why.append(deal.line)
        }
        // Royal Caribbean's classes apply to Royal Caribbean deals only.
        if deal.isRoyal, let cls = d.shipClass {
            if !p.shipClasses.isEmpty && !p.shipClasses.contains(cls) {
                why.append(ShipClass(rawValue: cls)?.title ?? "\(cls.capitalized) class")
            }
            if p.preferredClasses.contains(cls) { preferred = true }
        }
        // An unknown size never fails.
        if !p.shipSizes.isEmpty, let size = deal.sizeTier, !p.shipSizes.contains(size.rawValue) {
            why.append(size.shipTitle)
        }
        let ship = d.ship ?? ""
        if p.excludeShips.contains(where: { !$0.trimmed.isEmpty && ship.localizedCaseInsensitiveContains($0.trimmed) }) {
            why.append("Ship you skip")
        }
        if let nights = d.nights {
            if nights < p.nightsMin || nights > p.nightsMax { why.append(Fmt.nights(nights)) }
            if let want = p.nightsPreferredMin, nights >= want { preferred = true }
        }
        if let cabin = d.cabin {
            if !p.cabinTypes.isEmpty && !p.cabinTypes.contains(cabin) {
                let title = CabinType(rawValue: cabin)?.title ?? cabin.capitalized
                why.append(cabin == "suite" ? "Suite" : "\(title) cabin")
            } else if cabin == "balcony" {
                if p.requireOceanView && d.oceanViewConfirmed == false { why.append("No ocean view") }
                if let kind = excludedBalcony(d.cabinName, p.excludeBalconyTypes) { why.append("\(kind) balcony") }
            }
        }
        if let port = d.port?.trimmed, !port.isEmpty {
            if p.portsExcluded.contains(where: { matches(port, $0) }) { why.append(port.capped(30)) }
            if p.portsPreferred.contains(where: { matches(port, $0) }) { preferred = true }
        }
        if !p.regions.isEmpty, let region = d.region?.trimmed, !region.isEmpty,
           !p.regions.contains(where: { matches(region, $0) }) {
            why.append(region.capped(30))
        }
        if let sail = d.sailDate.map({ String($0.prefix(10)) }) {
            if let from = p.dateFrom, sail < from { why.append("Before \(shortDay(from))") }
            if let to = p.dateTo, sail > to { why.append("After \(shortDay(to))") }
        }
        if !p.sailMonths.isEmpty, let start = deal.sailDay, !p.sailMonths.contains(Fmt.month(of: start)) {
            why.append("\(Fmt.monthShort(Fmt.month(of: start))) sailing")
        }
        if p.avoidHolidays, let start = deal.sailDay, Holidays.overlaps(start, deal.returnDay ?? start) {
            why.append("Holiday week")
        }

        var tradeoff: String?
        var total: Int?
        if let t = d.totalFor3, t > 0 {
            total = t
        } else if let pp = d.pricePP, pp > 0 {
            total = pp * p.party
        }
        if let total {
            let cap = max(p.budgetTotal, p.tradeoffBudget ?? 0)
            let soft = min(p.budgetTotal, p.tradeoffBudget ?? p.budgetTotal)
            if total > cap {
                why.append("Over \(Fmt.usd(cap))")
            } else if total > soft {
                tradeoff = "Trade-off: over \(Fmt.usd(soft))"
            }
        }
        let reasons = Array(why.map { $0.capped(30) }.prefix(4))
        return TripFit(fits: reasons.isEmpty, reasons: reasons, tradeoff: reasons.isEmpty ? tradeoff : nil,
                       preferred: preferred)
    }

    /// "Galveston" matches "Galveston, Texas" and the other way round, ignoring case.
    static func matches(_ value: String, _ setting: String) -> Bool {
        let a = value.trimmed
        let b = setting.trimmed
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.localizedCaseInsensitiveContains(b) || b.localizedCaseInsensitiveContains(a)
    }

    /// The balcony kind a cabin name shows, if Jim rules it out ("Central Park").
    static func excludedBalcony(_ name: String?, _ kinds: [String]) -> String? {
        guard let name = name?.lowercased().replacingOccurrences(of: "-", with: " "), !name.isEmpty else { return nil }
        for kind in kinds {
            let words = kind.lowercased().replacingOccurrences(of: "-", with: " ").trimmed
            guard !words.isEmpty, name.contains(words) else { continue }
            return TripPrefs.balconyKinds.first { $0.id == kind }?.title ?? words.capitalized
        }
        return nil
    }

    private static func shortDay(_ iso: String) -> String {
        Fmt.day(iso).map { Fmt.shortDay($0) } ?? iso
    }
}

/// US holiday weeks that make sailings dearer and busier: Thanksgiving week, Christmas to New Year, July 4th.
enum Holidays {
    static func overlaps(_ start: Date, _ end: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let first = calendar.component(.year, from: start) - 1
        let last = calendar.component(.year, from: end)
        guard first <= last else { return false }
        for year in first...last {
            for window in windows(year, calendar) where window.start <= end && window.end >= start {
                return true
            }
        }
        return false
    }

    static func windows(_ year: Int, _ calendar: Calendar) -> [(start: Date, end: Date)] {
        var out: [(start: Date, end: Date)] = []
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            calendar.date(from: DateComponents(year: y, month: m, day: d))
        }
        if let a = day(year, 12, 20), let b = day(year + 1, 1, 2) { out.append((start: a, end: b)) }
        if let a = day(year, 7, 2), let b = day(year, 7, 6) { out.append((start: a, end: b)) }
        let thanksgiving = DateComponents(year: year, month: 11, weekday: 5, weekdayOrdinal: 4)
        if let t = calendar.date(from: thanksgiving),
           let a = calendar.date(byAdding: .day, value: -3, to: t),
           let b = calendar.date(byAdding: .day, value: 3, to: t) {
            out.append((start: a, end: b))
        }
        return out
    }
}

// MARK: - Buckets, sorting, filters

enum DealBucket: String, CaseIterable, Identifiable {
    case best, trip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: return "Best deals"
        case .trip: return "For my trip"
        }
    }
}

enum DealSort: String, CaseIterable, Identifiable {
    case score, total, under, soonest, newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .score: return "Best score"
        case .total: return "Lowest total"
        case .under: return "Biggest % under typical"
        case .soonest: return "Soonest sailing"
        case .newest: return "Newest"
        }
    }
}

/// The kinds of deal Jim can ask for (CONTRACT_V3 section 2). Worked out from a deal's own fields, never stored.
enum DealType: String, CaseIterable, Identifiable {
    case newLow = "new_low"
    case underTypical = "under_typical"
    case drop
    case sale
    case fitsTrip = "fits_trip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newLow: return "New low"
        case .underTypical: return "% under typical"
        case .drop: return "Price drop"
        case .sale: return "Sale"
        case .fitsTrip: return "Fits my trip"
        }
    }

    /// new_low: at or under the lowest we've seen · under_typical: at least `minPctUnder`% under typical ·
    /// drop: a price-drop deal, or cheaper than before · sale: a sale · fits_trip: passes My Trip.
    static func of(_ deal: Deal, fits: Bool, minPctUnder: Int) -> Set<DealType> {
        var out: Set<DealType> = []
        let d = deal.data
        if let price = d.pricePP, let low = d.lowestSeenPP, price > 0, price <= low { out.insert(.newLow) }
        if let pct = deal.pctUnder, pct >= minPctUnder { out.insert(.underTypical) }
        if deal.kind == .drop || deal.dropPP != nil { out.insert(.drop) }
        if deal.kind == .sale { out.insert(.sale) }
        if fits { out.insert(.fitsTrip) }
        return out
    }

    /// True when the deal is at least one of the picked kinds (none picked means every kind).
    static func matches(_ deal: Deal, picked: [String], fits: Bool, minPctUnder: Int) -> Bool {
        let wanted = Set(picked.compactMap { DealType(rawValue: $0) })
        guard !wanted.isEmpty else { return true }
        return !of(deal, fits: fits, minPctUnder: minPctUnder).isDisjoint(with: wanted)
    }
}

/// The minimum score: sales are exempt, and a deal with no score is never failed for it.
enum ScoreFloor {
    static func passes(_ deal: Deal, _ floor: Int?) -> Bool {
        guard let floor, deal.kind != .sale, let score = deal.data.score else { return true }
        return score >= floor
    }
}

enum DealOrder {
    /// Best score sorts by score, then the lowest total ("ranked by value"), then newest.
    static func sorted(_ deals: [Deal], by sort: DealSort, preferred: (Deal) -> Bool = { _ in false }) -> [Deal] {
        deals.sorted { a, b in
            let steps: [ComparisonResult]
            switch sort {
            case .score:
                steps = [desc(a.data.score, b.data.score), asc(a.totalEstimate, b.totalEstimate),
                         desc(preferred(a) ? 1 : 0, preferred(b) ? 1 : 0), desc(stamp(a.latest), stamp(b.latest))]
            case .total:
                steps = [asc(a.totalEstimate, b.totalEstimate), desc(a.data.score, b.data.score)]
            case .under:
                steps = [desc(a.pctUnder, b.pctUnder), desc(a.data.score, b.data.score)]
            case .soonest:
                steps = [asc(a.sailDay.map(stamp), b.sailDay.map(stamp)), desc(a.data.score, b.data.score)]
            case .newest:
                steps = [desc(stamp(a.latest), stamp(b.latest)), desc(a.data.score, b.data.score)]
            }
            for step in steps where step != .orderedSame {
                return step == .orderedAscending
            }
            return a.id < b.id
        }
    }

    private static func stamp(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    /// Smallest first; unknown last.
    static func asc(_ x: Int?, _ y: Int?) -> ComparisonResult {
        switch (x, y) {
        case let (x?, y?): return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.some, .none): return .orderedAscending
        case (.none, .some): return .orderedDescending
        case (.none, .none): return .orderedSame
        }
    }

    /// Largest first; unknown last.
    static func desc(_ x: Int?, _ y: Int?) -> ComparisonResult {
        switch (x, y) {
        case let (x?, y?): return x > y ? .orderedAscending : (x < y ? .orderedDescending : .orderedSame)
        case (.some, .none): return .orderedAscending
        case (.none, .some): return .orderedDescending
        case (.none, .none): return .orderedSame
        }
    }
}

/// The filter sheet: narrows both buckets. Empty means "any".
struct DealFilters: Codable, Equatable {
    // v3
    var lines: [String] = []
    var sizes: [String] = []
    var dealTypes: [String] = []
    var minScore: Int? = nil
    // v2
    var shipClasses: [String] = []
    var nightsMin: Int? = nil
    var nightsMax: Int? = nil
    var cabinTypes: [String] = []
    /// Departure ports and regions.
    var places: [String] = []
    /// Sail months as "2027-09".
    var months: [String] = []
    var maxTotal: Int? = nil

    enum CodingKeys: String, CodingKey {
        case lines, sizes, dealTypes, minScore, shipClasses, nightsMin, nightsMax, cabinTypes, places, months, maxTotal
    }

    var activeCount: Int {
        [!lines.isEmpty, !sizes.isEmpty, !dealTypes.isEmpty, minScore != nil,
         !shipClasses.isEmpty, nightsMin != nil || nightsMax != nil, !cabinTypes.isEmpty, !places.isEmpty,
         !months.isEmpty, maxTotal != nil].filter { $0 }.count
    }

    var isActive: Bool { activeCount > 0 }

    /// `fits` (does it pass My Trip) and `minPctUnder` are only needed for the deal-type filter.
    func matches(_ deal: Deal, fits: Bool = false, minPctUnder: Int = 15) -> Bool {
        let d = deal.data
        if !lines.isEmpty {
            guard lines.contains(where: { CruiseLine.same($0, deal.line) }) else { return false }
        }
        // An unknown size passes (CONTRACT_V3 rule 3).
        if !sizes.isEmpty, let size = deal.sizeTier, !sizes.contains(size.rawValue) { return false }
        if !DealType.matches(deal, picked: dealTypes, fits: fits, minPctUnder: minPctUnder) { return false }
        if !ScoreFloor.passes(deal, minScore) { return false }
        if !shipClasses.isEmpty {
            guard let c = d.shipClass, shipClasses.contains(c) else { return false }
        }
        if let lo = nightsMin {
            guard let n = d.nights, n >= lo else { return false }
        }
        if let hi = nightsMax {
            guard let n = d.nights, n <= hi else { return false }
        }
        if !cabinTypes.isEmpty {
            guard let c = d.cabin, cabinTypes.contains(c) else { return false }
        }
        if !places.isEmpty {
            let mine = [d.port, d.region].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
            guard mine.contains(where: { place in places.contains(place) }) else { return false }
        }
        if !months.isEmpty {
            guard let sail = d.sailDate, months.contains(String(sail.prefix(7))) else { return false }
        }
        if let cap = maxTotal {
            guard let total = deal.totalEstimate, total <= cap else { return false }
        }
        return true
    }

    /// "Oasis · 5–7 nights · Balcony"
    var summary: String {
        var parts: [String] = []
        if !lines.isEmpty { parts.append(lines.joined(separator: ", ")) }
        let tiers = ShipSize.allCases.filter { sizes.contains($0.rawValue) }.map { $0.title }
        if !tiers.isEmpty { parts.append(tiers.joined(separator: ", ") + " ships") }
        let kinds = DealType.allCases.filter { dealTypes.contains($0.rawValue) }.map { $0.title }
        if !kinds.isEmpty { parts.append(kinds.joined(separator: ", ")) }
        if let minScore { parts.append("score \(minScore)+") }
        let classes = ShipClass.allCases.filter { shipClasses.contains($0.rawValue) }.map { $0.short }
        if !classes.isEmpty { parts.append(classes.joined(separator: ", ")) }
        switch (nightsMin, nightsMax) {
        case let (lo?, hi?): parts.append(lo == hi ? Fmt.nights(lo) : "\(lo)–\(hi) nights")
        case let (lo?, nil): parts.append("\(lo)+ nights")
        case let (nil, hi?): parts.append("up to \(Fmt.nights(hi))")
        case (nil, nil): break
        }
        let cabins = cabinTypes.compactMap { CabinType(rawValue: $0)?.title }
        if !cabins.isEmpty { parts.append(cabins.joined(separator: ", ")) }
        if !places.isEmpty { parts.append(places.joined(separator: ", ")) }
        if !months.isEmpty { parts.append(months.sorted().map { Fmt.monthTitle($0) }.joined(separator: ", ")) }
        if let cap = maxTotal { parts.append("under \(Fmt.usd(cap))") }
        return parts.joined(separator: " · ")
    }

    static func decode(_ text: String) -> DealFilters {
        guard !text.isEmpty, let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(DealFilters.self, from: data) else { return DealFilters() }
        return value
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DealFilters {
    /// Filters saved by an older version (without the v3 keys) still read back.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = c.lenient([String].self, .lines) ?? []
        sizes = c.lenient([String].self, .sizes) ?? []
        dealTypes = c.lenient([String].self, .dealTypes) ?? []
        minScore = c.lenient(Int.self, .minScore)
        shipClasses = c.lenient([String].self, .shipClasses) ?? []
        nightsMin = c.lenient(Int.self, .nightsMin)
        nightsMax = c.lenient(Int.self, .nightsMax)
        cabinTypes = c.lenient([String].self, .cabinTypes) ?? []
        places = c.lenient([String].self, .places) ?? []
        months = c.lenient([String].self, .months) ?? []
        maxTotal = c.lenient(Int.self, .maxTotal)
    }
}
