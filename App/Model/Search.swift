import Foundation

// MARK: - Search (CONTRACT_V4 section 3.1)

/// How search results are ordered.
enum SearchSort: String, CaseIterable, Identifiable {
    case deal, price, date, perNight, fit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deal: return "Best deal"
        case .price: return "Lowest price"
        case .date: return "Soonest"
        case .perNight: return "Lowest per night"
        case .fit: return "Best fit for me"
        }
    }

    init(raw: String?) {
        self = SearchSort(rawValue: raw ?? "") ?? .deal
    }
}

/// The deal kinds search and plans can ask for (no sales: a sale is not one sailing).
enum SearchDealType: String, CaseIterable, Identifiable {
    case newLow = "new_low"
    case underTypical = "under_typical"
    case drop
    case fitsTrip = "fits_trip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newLow: return "New low"
        case .underTypical: return "Under typical"
        case .drop: return "Price drop"
        case .fitsTrip: return "Fits my trip"
        }
    }

    static func title(_ raw: String) -> String {
        SearchDealType(rawValue: raw)?.title ?? Words.humanize(raw)
    }
}

/// What Jim is looking for. Empty means "any". The same fields make a saved plan.
struct SearchQuery: Codable, Equatable {
    var lines: [String] = []
    var ships: [String] = []
    var sizes: [String] = []
    var ports: [String] = []
    var regions: [String] = []
    var dateFrom: String? = nil
    var dateTo: String? = nil
    var months: [Int] = []
    var nightsMin: Int? = nil
    var nightsMax: Int? = nil
    var cabin: String? = nil
    var maxPP: Int? = nil
    var dealTypes: [String] = []
    var sort: String = SearchSort.deal.rawValue
    /// v5: ports of call, any of them (CONTRACT_V5 section 1.6). Sent only to a v5 server; never part of a plan.
    var calls: [String] = []

    var isEmpty: Bool { self.cleaned() == SearchQuery(sort: cleaned().sort) }

    enum CodingKeys: String, CodingKey {
        case lines, ships, sizes, ports, regions, dateFrom, dateTo, months, nightsMin, nightsMax, cabin, maxPP
        case dealTypes, sort, calls
    }

    init(lines: [String] = [], ships: [String] = [], sizes: [String] = [], ports: [String] = [],
         regions: [String] = [], dateFrom: String? = nil, dateTo: String? = nil, months: [Int] = [],
         nightsMin: Int? = nil, nightsMax: Int? = nil, cabin: String? = nil, maxPP: Int? = nil,
         dealTypes: [String] = [], sort: String = SearchSort.deal.rawValue, calls: [String] = []) {
        self.lines = lines
        self.ships = ships
        self.sizes = sizes
        self.ports = ports
        self.regions = regions
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.months = months
        self.nightsMin = nightsMin
        self.nightsMax = nightsMax
        self.cabin = cabin
        self.maxPP = maxPP
        self.dealTypes = dealTypes
        self.sort = sort
        self.calls = calls
    }

    /// A search saved by an older version (no `calls`) still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = c.lenient([String].self, .lines) ?? []
        ships = c.lenient([String].self, .ships) ?? []
        sizes = c.lenient([String].self, .sizes) ?? []
        ports = c.lenient([String].self, .ports) ?? []
        regions = c.lenient([String].self, .regions) ?? []
        dateFrom = c.lenient(String.self, .dateFrom)
        dateTo = c.lenient(String.self, .dateTo)
        months = c.lenient([Int].self, .months) ?? []
        nightsMin = c.lenient(Int.self, .nightsMin)
        nightsMax = c.lenient(Int.self, .nightsMax)
        cabin = c.lenient(String.self, .cabin)
        maxPP = c.lenient(Int.self, .maxPP)
        dealTypes = c.lenient([String].self, .dealTypes) ?? []
        sort = c.lenient(String.self, .sort) ?? SearchSort.deal.rawValue
        calls = c.lenient([String].self, .calls) ?? []
    }

    /// Trimmed to what the server takes, so a search is never refused for its shape.
    func cleaned() -> SearchQuery {
        var q = self
        func list(_ items: [String], _ each: Int, _ most: Int, allowed: [String]? = nil) -> [String] {
            var out: [String] = []
            for item in items {
                let text = item.trimmed.capped(each)
                guard !text.isEmpty, !out.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) else { continue }
                if let allowed, !allowed.contains(text) { continue }
                out.append(text)
            }
            return Array(out.prefix(most))
        }
        q.lines = list(lines.compactMap { CruiseLine.canonical($0) }.filter { !CruiseLine.same($0, CruiseLine.other) }, 30, 12)
        q.ships = list(ships, 40, 20)
        q.sizes = list(sizes, 10, 4, allowed: ShipSize.allCases.map { $0.rawValue })
        q.ports = list(ports, 30, 10)
        q.regions = list(regions, 30, 12)
        q.calls = list(calls, 30, 10)
        q.dateFrom = dateFrom.flatMap { Fmt.day($0) }.map { Fmt.isoDay($0) }
        q.dateTo = dateTo.flatMap { Fmt.day($0) }.map { Fmt.isoDay($0) }
        if let from = q.dateFrom, let to = q.dateTo, from > to { (q.dateFrom, q.dateTo) = (to, from) }
        var picked: [Int] = []
        for month in months where (1...12).contains(month) && !picked.contains(month) { picked.append(month) }
        q.months = picked.sorted()
        q.nightsMin = nightsMin.map { min(max($0, 1), 30) }
        q.nightsMax = nightsMax.map { min(max($0, 1), 30) }
        if let low = q.nightsMin, let high = q.nightsMax, low > high { (q.nightsMin, q.nightsMax) = (high, low) }
        q.cabin = cabin.flatMap { CabinType(rawValue: $0) }?.rawValue
        q.maxPP = maxPP.flatMap { $0 > 0 ? min($0, 1_000_000) : nil }
        q.dealTypes = list(dealTypes, 20, 4, allowed: SearchDealType.allCases.map { $0.rawValue })
        q.sort = SearchSort(raw: sort).rawValue
        return q
    }

    /// `nights=7` or `nights=6-8`; one end alone becomes 1-N or N-30.
    var nightsParam: String? {
        switch (nightsMin, nightsMax) {
        case let (low?, high?): return low == high ? "\(low)" : "\(low)-\(high)"
        case let (low?, nil): return "\(low)-30"
        case let (nil, high?): return "1-\(high)"
        case (nil, nil): return nil
        }
    }

    /// The query string for `GET /v1/search`.
    func queryItems(offset: Int = 0, limit: Int = 50) -> [URLQueryItem] {
        let q = cleaned()
        var items: [URLQueryItem] = []
        func add(_ name: String, _ values: [String]) {
            if !values.isEmpty { items.append(URLQueryItem(name: name, value: values.joined(separator: ","))) }
        }
        add("line", q.lines)
        add("ship", q.ships)
        add("size", q.sizes)
        add("port", q.ports)
        add("region", q.regions)
        if let from = q.dateFrom { items.append(URLQueryItem(name: "from", value: from)) }
        if let to = q.dateTo { items.append(URLQueryItem(name: "to", value: to)) }
        add("months", q.months.map(String.init))
        if let nights = q.nightsParam { items.append(URLQueryItem(name: "nights", value: nights)) }
        if let cabin = q.cabin { items.append(URLQueryItem(name: "cabin", value: cabin)) }
        if let maxPP = q.maxPP { items.append(URLQueryItem(name: "maxPP", value: String(maxPP))) }
        add("dealType", q.dealTypes)
        add("calls", q.calls)
        items.append(URLQueryItem(name: "sort", value: q.sort))
        if offset > 0 { items.append(URLQueryItem(name: "offset", value: String(min(offset, 5000)))) }
        items.append(URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100))))
        return items
    }

    /// "Royal Caribbean · Balcony · 6–8 nights · ≤ $1,300 pp", or "Every sailing".
    var summary: String {
        let q = cleaned()
        var parts: [String] = []
        if !q.lines.isEmpty { parts.append(ListText.join(q.lines)) }
        if !q.ships.isEmpty { parts.append(q.ships.count == 1 ? q.ships[0] : "\(q.ships.count) ships") }
        let sizes = ShipSize.allCases.filter { q.sizes.contains($0.rawValue) }
        if !sizes.isEmpty { parts.append(sizes.map { $0.title }.joined(separator: " · ")) }
        if !q.ports.isEmpty { parts.append("from \(q.ports.joined(separator: ", "))") }
        if !q.regions.isEmpty { parts.append(q.regions.joined(separator: ", ")) }
        if !q.calls.isEmpty { parts.append("visits \(q.calls.joined(separator: " or "))") }
        if let from = Fmt.day(q.dateFrom), let to = Fmt.day(q.dateTo) {
            parts.append("\(Fmt.shortDay(from))–\(Fmt.shortDay(to))")
        } else if let from = Fmt.day(q.dateFrom) {
            parts.append("from \(Fmt.shortDay(from))")
        } else if let to = Fmt.day(q.dateTo) {
            parts.append("by \(Fmt.shortDay(to))")
        }
        if !q.months.isEmpty { parts.append(q.months.map { Fmt.monthShort($0) }.joined(separator: ", ")) }
        switch (q.nightsMin, q.nightsMax) {
        case let (low?, high?): parts.append(low == high ? Fmt.nights(low) : "\(low)–\(high) nights")
        case let (low?, nil): parts.append("\(low)+ nights")
        case let (nil, high?): parts.append("up to \(high) nights")
        case (nil, nil): break
        }
        if let cabin = q.cabin.flatMap({ CabinType(rawValue: $0) }) { parts.append(cabin.title) }
        if let maxPP = q.maxPP { parts.append("≤ \(Fmt.usd(maxPP)) pp") }
        if !q.dealTypes.isEmpty { parts.append(q.dealTypes.map { SearchDealType.title($0) }.joined(separator: ", ")) }
        return parts.isEmpty ? "Every sailing Deal Desk has seen" : parts.joined(separator: " · ")
    }
}

struct SearchCoverage: Decodable, Hashable {
    var line: String?
    var coverage: String?
    var coverageNote: String?
}

/// One sailing a source has seen in the last 45 days, priced for one cabin class.
struct SearchRow: Decodable, Hashable, Identifiable {
    var sailingId: String
    var line: String?
    var ship: String?
    var shipName: String?
    var shipSize: String?
    var shipClass: String?
    var sailDate: String?
    var nights: Int?
    var embarkPort: String?
    var returnDate: String?
    var stops: [String]?
    var region: String?
    var cabin: String?
    var pricePP: Int?
    var perNightPP: Int?
    var priceIncludesTaxes: Bool?
    var priceSource: String?
    var priceSeenAt: String?
    var priceState: String?
    var typicalPP: Int?
    var typicalN: Int?
    var pctUnderTypical: Int?
    var lowestSeenPP: Int?
    var dealTypes: [String]?
    var dealId: String?
    var score: Int?
    var scoreLabel: String?
    var sourceScore: Int?
    var sourceScoreBy: String?
    var trackedId: String?
    var fit: PortFit?
    var unknown: [String]?
    var coverage: String?
    var booking: BookingInfo?
    var sources: [DealSource]?
    var bookAlternatives: [BookAlternative]?
    // v5 (CONTRACT_V5 section 1.6)
    var regionBasis: String?
    var embarkKey: String?
    var tripCost: TripCost?

    var id: String { "\(sailingId)|\(cabin ?? "")" }

    enum CodingKeys: String, CodingKey {
        case sailingId, line, ship, shipName, shipSize, shipClass, sailDate, nights, embarkPort, returnDate, stops
        case region, cabin, pricePP, perNightPP, priceIncludesTaxes, priceSource, priceSeenAt, priceState, typicalPP
        case typicalN, pctUnderTypical, lowestSeenPP, dealTypes, dealId, score, scoreLabel, sourceScore, sourceScoreBy
        case trackedId, fit, unknown, coverage, booking, sources, bookAlternatives
        case regionBasis, embarkKey, tripCost
    }

    init(sailingId: String) {
        self.sailingId = sailingId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sailingId = c.lenient(String.self, .sailingId) ?? ""
        line = c.lenient(String.self, .line)
        ship = c.lenient(String.self, .ship)
        shipName = c.lenient(String.self, .shipName)
        shipSize = c.lenient(String.self, .shipSize)
        shipClass = c.lenient(String.self, .shipClass)
        sailDate = c.lenient(String.self, .sailDate)
        nights = c.lenient(Int.self, .nights)
        embarkPort = c.lenient(String.self, .embarkPort)
        returnDate = c.lenient(String.self, .returnDate)
        stops = c.lenient([String].self, .stops)
        region = c.lenient(String.self, .region)
        cabin = c.lenient(String.self, .cabin)
        pricePP = c.lenient(Int.self, .pricePP)
        perNightPP = c.lenient(Int.self, .perNightPP)
        priceIncludesTaxes = c.lenient(Bool.self, .priceIncludesTaxes)
        priceSource = c.lenient(String.self, .priceSource)
        priceSeenAt = c.lenient(String.self, .priceSeenAt)
        priceState = c.lenient(String.self, .priceState)
        typicalPP = c.lenient(Int.self, .typicalPP)
        typicalN = c.lenient(Int.self, .typicalN)
        pctUnderTypical = c.lenient(Int.self, .pctUnderTypical)
        lowestSeenPP = c.lenient(Int.self, .lowestSeenPP)
        dealTypes = c.lenient([String].self, .dealTypes)
        dealId = c.lenient(String.self, .dealId)
        score = c.lenient(Int.self, .score)
        scoreLabel = c.lenient(String.self, .scoreLabel)
        sourceScore = c.lenient(Int.self, .sourceScore)
        sourceScoreBy = c.lenient(String.self, .sourceScoreBy)
        trackedId = c.lenient(String.self, .trackedId)
        fit = c.lenient(PortFit.self, .fit)
        unknown = c.lenient([String].self, .unknown)
        coverage = c.lenient(String.self, .coverage)
        booking = c.lenient(BookingInfo.self, .booking).flatMap { $0.link == nil ? nil : $0 }
        sources = c.lenient([DealSource].self, .sources)
        bookAlternatives = c.lenient([BookAlternative].self, .bookAlternatives)
        regionBasis = c.lenient(String.self, .regionBasis)
        embarkKey = c.lenient(String.self, .embarkKey)
        tripCost = c.lenient(TripCost.self, .tripCost).flatMap { $0.low == nil && $0.high == nil ? nil : $0 }
    }

    var lineName: String { CruiseLine.resolved(line) }

    /// v5: a region filter passed this row only because its region is not known; it is listed last.
    var regionUnknown: Bool { (unknown ?? []).contains { $0.trimmed.lowercased() == "region" } }

    /// v5: a sailing a schedule lists with no current fare ("price not seen").
    var scheduleOnly: Bool { priceState == "schedule_only" }
    var shipTitle: String {
        for value in [shipName, ship] {
            if let text = value?.trimmed, !text.isEmpty {
                return text.contains("-") && !text.contains(" ") ? Words.title(fromSlug: text) : text
            }
        }
        return "Sailing"
    }
    var sailDay: Date? { Fmt.day(sailDate) }
    var cabinType: CabinType? { cabin.flatMap { CabinType(rawValue: $0) } }
    var coverageState: Coverage? { Coverage(coverage) }
    var hasPrice: Bool { (pricePP ?? 0) > 0 }

    /// "Royal Caribbean · Mega ship"
    var eyebrow: String {
        [lineName, ShipSize.shipTitle(shipSize)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Sun Aug 15 – Sun Aug 22, 2027 · 7 nights"
    var datesLine: String {
        var parts: [String] = []
        if let start = sailDay {
            let end = Fmt.day(returnDate) ?? nights.flatMap { Fmt.adding(days: $0, to: start) }
            parts.append(Fmt.tripDates(from: start, to: end))
        }
        if let nights { parts.append(Fmt.nights(nights)) }
        return parts.joined(separator: " · ")
    }

    /// "Galveston → Cozumel · Roatán"
    var route: String? {
        let names = (stops ?? []).map { $0.trimmed }.filter { !$0.isEmpty && !Deal.isSeaDay($0) }
        let from = embarkPort?.trimmed ?? ""
        if names.isEmpty { return from.isEmpty ? nil : "From \(from)" }
        return from.isEmpty ? names.joined(separator: " · ") : "\(from) → \(names.joined(separator: " · "))"
    }

    /// "New low", "18% under typical", "Price drop", "Fits my trip"
    var typeChips: [String] {
        (dealTypes ?? []).map { raw -> String in
            if raw == SearchDealType.underTypical.rawValue, let pct = pctUnderTypical, pct > 0 { return "\(pct)% under typical" }
            return SearchDealType.title(raw)
        }
    }

    /// "region unknown · size unknown": filters this row passed only because the fact is unknown.
    var unknownNote: String? {
        let list = (unknown ?? []).map { $0.trimmed }.filter { !$0.isEmpty }
        return list.isEmpty ? nil : list.map { "\($0) unknown" }.joined(separator: " · ")
    }

    /// The pick for Track, in the cabin this row is priced for (else the one searched for, else a balcony).
    func trackPick(cabin wanted: String?) -> TrackPick {
        var pick = TrackPick()
        pick.line = lineName
        pick.ship = shipTitle.capped(40)
        pick.sailDate = sailDay
        pick.nights = nights ?? 7
        pick.cabin = cabinType ?? wanted.flatMap { CabinType(rawValue: $0) } ?? .balcony
        pick.port = (embarkPort ?? "").capped(30)
        return pick
    }
}

struct SearchResult: Decodable, Equatable {
    var rows: [SearchRow]
    var total: Int?
    var nextOffset: Int?
    var notes: [String]
    var coverage: [SearchCoverage]
    var generatedAt: String?
    // v5: why a search came back empty, and what to do about it (CONTRACT_V5 section 1.6)
    var funnel: [FunnelStep] = []
    var coverageGap: [CoverageGap] = []
    var why: [String] = []

    enum CodingKeys: String, CodingKey {
        case rows, total, nextOffset, notes, coverage, generatedAt, funnel, coverageGap, why
    }

    init(rows: [SearchRow], total: Int?, nextOffset: Int?, notes: [String], coverage: [SearchCoverage] = [],
         generatedAt: String? = nil, funnel: [FunnelStep] = [], coverageGap: [CoverageGap] = [], why: [String] = []) {
        self.rows = rows
        self.total = total
        self.nextOffset = nextOffset
        self.notes = notes
        self.coverage = coverage
        self.generatedAt = generatedAt
        self.funnel = funnel
        self.coverageGap = coverageGap
        self.why = why
    }

    /// The why lines, trimmed, at most 4.
    var whyLines: [String] {
        Array(why.map { $0.trimmed }.filter { !$0.isEmpty }.prefix(4))
    }

    var hasExplanation: Bool { !whyLines.isEmpty || !funnel.isEmpty || !coverageGap.isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One odd row never hides the rest.
        let raw = c.lenient([JSONValue].self, .rows) ?? []
        rows = raw.compactMap { $0.decode(SearchRow.self) }.filter { !$0.sailingId.isEmpty }
        total = c.lenient(Int.self, .total)
        nextOffset = c.lenient(Int.self, .nextOffset)
        notes = c.lenient([String].self, .notes) ?? []
        coverage = c.lenient([SearchCoverage].self, .coverage) ?? []
        generatedAt = c.lenient(String.self, .generatedAt)
        funnel = c.list(FunnelStep.self, .funnel) ?? []
        coverageGap = c.list(CoverageGap.self, .coverageGap) ?? []
        why = c.lenient([String].self, .why) ?? []
    }
}

// MARK: - Plans (CONTRACT_V4 section 3.2)

struct PlanData: Codable, Hashable {
    var name: String?
    var lines: [String]?
    var ships: [String]?
    var sizes: [String]?
    var ports: [String]?
    var regions: [String]?
    var dateFrom: String?
    var dateTo: String?
    var months: [Int]?
    var nightsMin: Int?
    var nightsMax: Int?
    var cabin: String?
    var maxPP: Int?
    var dealTypes: [String]?
    var sort: String?
    var watch: Bool?
    var alerts: Bool?
    var note: String?
    var createdAt: String?
    var updatedAt: String?
    var promotedAt: String?
    // the brain's
    var matches: Int?
    var bestPP: Int?
    var bestSailingId: String?
    var brainNote: String?
    var checkedAt: String?

    enum CodingKeys: String, CodingKey {
        case name, lines, ships, sizes, ports, regions, dateFrom, dateTo, months, nightsMin, nightsMax, cabin, maxPP
        case dealTypes, sort, watch, alerts, note, createdAt, updatedAt, promotedAt
        case matches, bestPP, bestSailingId, brainNote, checkedAt
    }
}

extension PlanData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, .name)
        lines = c.lenient([String].self, .lines)
        ships = c.lenient([String].self, .ships)
        sizes = c.lenient([String].self, .sizes)
        ports = c.lenient([String].self, .ports)
        regions = c.lenient([String].self, .regions)
        dateFrom = c.lenient(String.self, .dateFrom)
        dateTo = c.lenient(String.self, .dateTo)
        months = c.lenient([Int].self, .months)
        nightsMin = c.lenient(Int.self, .nightsMin)
        nightsMax = c.lenient(Int.self, .nightsMax)
        cabin = c.lenient(String.self, .cabin)
        maxPP = c.lenient(Int.self, .maxPP)
        dealTypes = c.lenient([String].self, .dealTypes)
        sort = c.lenient(String.self, .sort)
        watch = c.lenient(Bool.self, .watch)
        alerts = c.lenient(Bool.self, .alerts)
        note = c.lenient(String.self, .note)
        createdAt = c.lenient(String.self, .createdAt)
        updatedAt = c.lenient(String.self, .updatedAt)
        promotedAt = c.lenient(String.self, .promotedAt)
        matches = c.lenient(Int.self, .matches)
        bestPP = c.lenient(Int.self, .bestPP)
        bestSailingId = c.lenient(String.self, .bestSailingId)
        brainNote = c.lenient(String.self, .brainNote)
        checkedAt = c.lenient(String.self, .checkedAt)
    }
}

/// A saved search: a named, editable filter Deal Desk can watch, and that can become My Trip.
struct Plan: Identifiable, Hashable {
    let id: String
    let version: Int
    let data: PlanData
    var isLocal = false

    init?(raw: RawDoc, isLocal: Bool = false) {
        guard let decoded = raw.data.decode(PlanData.self) else { return nil }
        id = raw.id
        version = raw.version
        data = decoded
        self.isLocal = isLocal
    }

    init(id: String, data: PlanData) {
        self.id = id
        self.version = 1
        self.data = data
    }

    var name: String {
        let text = data.name?.trimmed ?? ""
        return text.isEmpty ? "Plan" : text
    }

    var query: SearchQuery {
        SearchQuery(lines: data.lines ?? [], ships: data.ships ?? [], sizes: data.sizes ?? [], ports: data.ports ?? [],
                    regions: data.regions ?? [], dateFrom: data.dateFrom, dateTo: data.dateTo, months: data.months ?? [],
                    nightsMin: data.nightsMin, nightsMax: data.nightsMax, cabin: data.cabin, maxPP: data.maxPP,
                    dealTypes: data.dealTypes ?? [], sort: data.sort ?? SearchSort.deal.rawValue)
    }

    var watching: Bool { data.watch == true }

    /// "12 matches · best $1,154 pp · checked 9:12", from Deal Desk's last look.
    var checkLine: String? {
        var parts: [String] = []
        if let n = data.matches { parts.append(n == 1 ? "1 match" : "\(n) matches") }
        if let best = data.bestPP, best > 0 { parts.append("best \(Fmt.usd(best)) pp") }
        if let at = Fmt.timestamp(data.checkedAt) { parts.append("checked \(Fmt.when(at))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func order(_ a: Plan, _ b: Plan) -> Bool {
        let x = a.data.createdAt ?? ""
        let y = b.data.createdAt ?? ""
        if x != y { return x > y }
        return a.id < b.id
    }
}

/// What the plan editor saves.
struct PlanDraft: Equatable {
    var name: String = ""
    var query = SearchQuery()
    var watch = true
    var alerts = false
    var note: String = ""

    init() {}

    init(plan: Plan) {
        name = plan.data.name ?? ""
        query = plan.query
        watch = plan.data.watch ?? true
        alerts = plan.data.alerts ?? false
        note = plan.data.note ?? ""
    }

    var problem: String? {
        let text = name.trimmed
        if text.isEmpty { return "Give the plan a name." }
        if text.count > 60 { return "The name is longer than 60 letters." }
        return nil
    }

    /// The pick fields (the brain's enrichment is never sent). A create leaves out what is empty; an edit sends
    /// every pick field so a cleared one is cleared on the server too.
    func fields(isNew: Bool, stamp: String = Fmt.stamp()) -> [String: JSONValue] {
        let q = query.cleaned()
        func strings(_ items: [String]) -> JSONValue { .array(items.map { JSONValue.string($0) }) }
        func text(_ value: String?) -> JSONValue { value.map { JSONValue.string($0) } ?? .null }
        func number(_ value: Int?) -> JSONValue { value.map { JSONValue.int($0) } ?? .null }
        let cleanNote = note.trimmed.capped(120)
        var f: [String: JSONValue] = [
            "name": .string(name.trimmed.capped(60)),
            "lines": strings(q.lines),
            "ships": strings(q.ships),
            "sizes": strings(q.sizes),
            "ports": strings(q.ports),
            "regions": strings(q.regions),
            "dateFrom": text(q.dateFrom),
            "dateTo": text(q.dateTo),
            "months": .array(q.months.map { JSONValue.int($0) }),
            "nightsMin": number(q.nightsMin),
            "nightsMax": number(q.nightsMax),
            "cabin": text(q.cabin),
            "maxPP": number(q.maxPP),
            "dealTypes": strings(q.dealTypes),
            "sort": .string(q.sort),
            "watch": .bool(watch),
            "alerts": .bool(alerts),
            "note": cleanNote.isEmpty ? .null : .string(cleanNote),
        ]
        if isNew {
            f["createdAt"] = .string(stamp)
            f = f.filter { $0.value != .null }
        } else {
            f["updatedAt"] = .string(stamp)
        }
        return f
    }

    var key: String { name.trimmed.lowercased() }
}

/// "Promote to my trip" (CONTRACT_V4 section 3.2): what a plan changes on My Trip, and what it can't carry over.
enum PlanPromotion {
    /// The trip settings with the plan's lines, sizes, dates, months, nights, cabin and deal kinds.
    static func apply(_ plan: Plan, to trip: TripPrefs) -> TripPrefs {
        let q = plan.query.cleaned()
        var p = trip
        p.lines = q.lines
        p.shipSizes = q.sizes
        p.dateFrom = q.dateFrom
        p.dateTo = q.dateTo
        p.sailMonths = q.months
        if let low = q.nightsMin { p.nightsMin = low }
        if let high = q.nightsMax { p.nightsMax = high }
        if let cabin = q.cabin { p.cabinTypes = [cabin] }
        p.dealTypes = q.dealTypes
        return p.cleaned()
    }

    /// The parts of a plan My Trip has no place for.
    static func notCopied(_ plan: Plan) -> [String] {
        let q = plan.query.cleaned()
        var out: [String] = []
        if !q.ships.isEmpty { out.append("ships") }
        if !q.ports.isEmpty { out.append("ports") }
        if !q.regions.isEmpty { out.append("regions") }
        if q.maxPP != nil { out.append("budget per person") }
        return out
    }
}
