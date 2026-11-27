import Foundation

/// Made-up v4 data for previews, tests and screenshots: booking links, the digest, search, plans, past trips and
/// the port summary. Nothing here is real.
extension Samples {
    /// The sample catalog on a v4 server: every feature listed, and each line's own booking spec.
    static let catalogV4: Catalog = {
        var c = Samples.catalog
        c.apiVersion = 4
        c.features = V4Feature.allCases.map { $0.rawValue }
        let homes: [String: (String, String, String)] = [
            "Royal Caribbean": ("Book on Royal Caribbean", "Royal", "https://www.royalcaribbean.com/cruises"),
            "Celebrity": ("Book on Celebrity", "Celebrity", "https://www.celebritycruises.com/"),
            "Norwegian": ("Book on Norwegian", "Norwegian", "https://www.ncl.com/vacations"),
            "Carnival": ("Book on Carnival", "Carnival", "https://www.carnival.com/cruise-search"),
            "Princess": ("Book on Princess", "Princess", "https://www.princess.com/"),
            "MSC": ("Book on MSC", "MSC", "https://www.msccruisesusa.com/"),
        ]
        c.lines = (c.lines ?? []).map { line in
            var l = line
            if let name = line.name, let spec = homes[name] {
                l.booking = CatalogBooking(label: spec.0, short: spec.1, home: spec.2,
                                           tiers: [CatalogBooking.Tier(tier: "sailing", verified: true)])
            }
            return l
        }
        return c
    }()

    static let bookingIcon = BookingInfo(
        url: "https://www.royalcaribbean.com/cruises?search=ship:IC%7CstartDate:2027-09-05~2027-09-05",
        tier: "sailing", label: "Book on Royal Caribbean", note: "opens Royal's search for Icon · Sep 5, 2027",
        verified: true, codes: ["shipCode", "sailDate"], builtAt: nil)

    static let bookingBeyond = BookingInfo(
        url: "https://www.celebritycruises.com/booking-cruise/selectRoom/stateroomQuantity?groupId=BY07FLL-1&pID=BY07W001&sDT=2027-04-11&sCD=BY&sCT=CO&country=USA",
        tier: "exact", label: "Book on Celebrity", note: nil, verified: true,
        codes: ["groupId", "packageCode", "shipCode", "sailDate"], builtAt: nil)

    static let bookingStar = BookingInfo(
        url: "https://www.royalcaribbean.com/cruises?search=ship:ST%7CstartDate:2027-06-12~2027-06-12",
        tier: "sailing", label: "Book on Royal Caribbean", note: "opens Royal's search for Star · Jun 12, 2027",
        verified: true, codes: ["shipCode", "sailDate"], builtAt: nil)

    static let costcoAlternative = BookAlternative(
        agency: "Costco Travel", url: "https://example.com/costco-icon", pricePP: 1276, taxesIncluded: true,
        cabinClass: "balcony", perks: ["$250 Costco Shop Card"],
        whyBetter: "same fare + $250 Costco Shop Card")

    /// v4 docs: the v3 samples plus booking on deals and tracked sailings, the digest, plans, trips and ports.
    static var docsV4: [String: [String: RawDoc]] {
        var colls = docs
        func merge(_ coll: String, _ id: String, _ fields: [String: JSONValue]) {
            guard var doc = colls[coll]?[id] else { return }
            doc.data = doc.data.merging(fields)
            colls[coll]?[id] = doc
        }
        func put(_ coll: String, _ id: String, _ value: JSONValue) {
            colls[coll, default: [:]][id] = RawDoc(id: id, data: value, version: 1, updatedAt: nil)
        }
        merge("deals", "sample-fits", [
            "booking": JSONValue(encoding: bookingIcon),
            "bookAlternatives": .array([JSONValue(encoding: costcoAlternative)]),
            "link": .string(bookingIcon.url ?? ""), "linkLabel": .string("Book on Royal Caribbean"),
        ])
        merge("deals", "sample-celebrity", ["booking": JSONValue(encoding: bookingBeyond)])
        merge("tracked", "trk-sample-star", ["booking": JSONValue(encoding: bookingStar)])

        let today = isoDay(daysFromNow: 0)
        put("digest", today, digestJSON(date: today))
        put("plans", "plan-sample-icon", JSONValue(encoding: planIcon))
        put("trips", "trip-sample-aqua", JSONValue(encoding: tripAqua))
        put("ports", "summary", portsJSON)
        return colls
    }

    // MARK: Digest

    static func digestItem(_ id: String, kind: String, headline: String, summary: String?, link: String,
                           sources: [String], line: String? = nil, ship: String? = nil, sailDate: String? = nil,
                           pricePP: Int? = nil, endsAt: String? = nil, fits: Bool = false, dealId: String? = nil,
                           booking: BookingInfo? = nil) -> DigestItem {
        var item = DigestItem(id: id)
        item.kind = kind
        item.headline = headline
        item.summary = summary
        item.link = link
        item.sources = sources.map { DigestSource(name: $0, inboxId: "inbox-\($0.lowercased().prefix(6))", receivedAt: Fmt.stamp()) }
        item.line = line
        item.ship = ship
        item.sailDate = sailDate
        item.pricePP = pricePP
        item.endsAt = endsAt
        item.matchesTrip = fits
        item.dealId = dealId
        item.booking = booking
        item.firstSeenAt = Fmt.stamp(Date().addingTimeInterval(-86400))
        item.lastSeenAt = Fmt.stamp()
        return item
    }

    static let digestItems: [DigestItem] = [
        digestItem("s-royal-caribbean-icon-of-the-seas-2027-09-05", kind: "price_drop",
                   headline: "Icon of the Seas balcony drops to $1,276 pp",
                   summary: "Western Caribbean from Galveston, 6 nights; lowest this year.",
                   link: "https://example.com/newsletter/icon", sources: ["Cruise Fever", "Vacations To Go"],
                   line: "Royal Caribbean", ship: "Icon of the Seas", sailDate: "2027-09-05", pricePP: 1276,
                   fits: true, dealId: "sample-fits", booking: bookingIcon),
        digestItem("sale-royal-caribbean-black-friday", kind: "sale", headline: "Royal Caribbean Black Friday: 60% off the 2nd guest",
                   summary: "Plus kids sail free on select sailings.", link: "https://example.com/newsletter/bf",
                   sources: ["Royal Caribbean", "Cruiseline.com", "Cruise Fever"], line: "Royal Caribbean",
                   endsAt: isoDay(daysFromNow: 4)),
        digestItem("l-0a1b2c3d4e5f", kind: "news", headline: "Star of the Seas opens 2028 sailings",
                   summary: "Port Canaveral, 7 nights, from August 2028.", link: "https://example.com/newsletter/star",
                   sources: ["Cruise Hive"], line: "Royal Caribbean", ship: "Star of the Seas"),
        digestItem("h-9f8e7d6c5b4a", kind: "something_new", headline: "What's new in cruise packing rules",
                   summary: nil, link: "https://example.com/newsletter/rules", sources: ["Cruiseline.com"]),
    ]

    static func digestJSON(date: String) -> JSONValue {
        .object([
            "date": .string(date),
            "items": .array(digestItems.map { JSONValue(encoding: $0) }),
            "emailsRead": .int(23),
            "senders": .array(["Cruise Fever", "Vacations To Go", "Cruiseline.com", "Royal Caribbean", "Cruise Hive"]
                .map { JSONValue.string($0) }),
            "updatedAt": .string(Fmt.stamp()),
        ])
    }

    // MARK: Search and plans

    static let planIcon: PlanData = {
        var p = PlanData()
        p.name = "Icon from Galveston, fall 2027"
        p.lines = ["Royal Caribbean"]
        p.ships = ["Icon of the Seas"]
        p.ports = ["Galveston"]
        p.dateFrom = "2027-08-01"
        p.dateTo = "2027-11-30"
        p.nightsMin = 6
        p.nightsMax = 8
        p.cabin = "balcony"
        p.maxPP = 1300
        p.sort = "deal"
        p.watch = true
        p.alerts = true
        p.createdAt = Fmt.stamp(Date().addingTimeInterval(-3 * 86400))
        p.matches = 6
        p.bestPP = 1154
        p.checkedAt = Fmt.stamp(Date().addingTimeInterval(-1800))
        return p
    }()

    static func searchRow(_ id: String, ship: String, date: String, nights: Int, port: String, stops: [String],
                          price: Int?, typical: Int?, pct: Int?, types: [String], score: Int? = nil,
                          dealId: String? = nil, fit: PortFit? = nil, booking: BookingInfo? = nil,
                          alternatives: [BookAlternative] = [], unknown: [String] = []) -> SearchRow {
        var r = SearchRow(sailingId: id)
        r.line = "Royal Caribbean"
        r.ship = Slug.ship(ship)
        r.shipName = ship
        r.shipSize = "mega"
        r.sailDate = date
        r.nights = nights
        r.embarkPort = port
        r.stops = stops
        r.region = "Western Caribbean"
        r.cabin = "balcony"
        r.pricePP = price
        r.perNightPP = price.map { $0 / max(nights, 1) }
        r.priceIncludesTaxes = price == nil ? nil : false
        r.priceSource = price == nil ? nil : "Example agency"
        r.priceState = price == nil ? "no_current_price" : "priced"
        r.typicalPP = typical
        r.pctUnderTypical = pct
        r.dealTypes = types
        r.score = score
        r.dealId = dealId
        r.fit = fit
        r.unknown = unknown
        r.coverage = "tracking_live"
        r.booking = booking ?? BookingInfo(
            url: "https://www.royalcaribbean.com/cruises?search=ship:IC%7CstartDate:\(date)~\(date)", tier: "sailing",
            label: "Book on Royal Caribbean", note: "opens Royal's search for \(ship.replacingOccurrences(of: " of the Seas", with: "")) · \(date)",
            verified: true, codes: ["shipCode", "sailDate"], builtAt: nil)
        r.sources = price.map { [DealSource(name: "Example agency", url: "https://example.com/\(id)", pricePP: $0, includesTaxes: false)] }
        r.bookAlternatives = alternatives
        return r
    }

    static let searchResult = SearchResult(rows: [
        searchRow("icon-of-the-seas-2027-09-05-6n", ship: "Icon of the Seas", date: "2027-09-05", nights: 6,
                  port: "Galveston", stops: ["Cozumel", "Roatán", "Costa Maya"], price: 1154, typical: 1480, pct: 22,
                  types: ["new_low", "under_typical", "fits_trip"], score: 78, dealId: "sample-fits",
                  fit: PortFit(adj: -9, reasons: ["Costa Maya 3/10", "Cozumel 4 wk ago"]), booking: bookingIcon,
                  alternatives: [costcoAlternative]),
        searchRow("icon-of-the-seas-2027-10-31-6n", ship: "Icon of the Seas", date: "2027-10-31", nights: 6,
                  port: "Galveston", stops: ["Cozumel", "Costa Maya"], price: 1211, typical: 1390, pct: 13,
                  types: ["fits_trip"]),
        searchRow("icon-of-the-seas-2027-08-22-6n", ship: "Icon of the Seas", date: "2027-08-22", nights: 6,
                  port: "Galveston", stops: ["Roatán", "Cozumel"], price: nil, typical: nil, pct: nil, types: [],
                  unknown: ["price"]),
    ], total: 3, nextOffset: nil, notes: ["no data for MSC yet"])

    static let prefill = TripPrefill(embarkPort: "Miami", nights: 7,
                                     stops: ["Roatan (Coxen Hole)", "Harvest Caye", "At sea", "Costa Maya", "Cozumel"],
                                     source: "fares")

    // MARK: Trips and ports

    static let tripAqua: PastTripData = {
        var t = PastTripData()
        t.line = "Norwegian"
        t.ship = "Norwegian Aqua"
        t.sailDate = Samples.isoDay(daysFromNow: -26)
        t.nights = 7
        t.embarkPort = "Miami"
        t.ports = [
            TripPort(name: "Roatan (Coxen Hole)", rating: 9, note: "Snorkel trip was the best day"),
            TripPort(name: "Harvest Caye", rating: 8, note: nil),
            TripPort(name: "Costa Maya", rating: 3, note: "Crowded, little to do"),
            TripPort(name: "Cozumel", rating: nil, note: nil),
        ]
        t.rating = 8
        t.cabin = "balcony"
        t.addedVia = "seed"
        t.addedAt = Fmt.stamp(Date().addingTimeInterval(-2 * 86400))
        return t
    }()

    static let portSummaries: [PortSummary] = [
        port("roatan", "Roatan (Coxen Hole)", rating: 9, ratingAdj: 6, recencyAdj: -6),
        port("harvest-caye", "Harvest Caye", rating: 8, ratingAdj: 3, recencyAdj: -6),
        port("costa-maya", "Costa Maya", rating: 3, ratingAdj: -6, recencyAdj: -6),
        port("cozumel", "Cozumel", rating: nil, ratingAdj: 0, recencyAdj: -6),
    ]

    static func port(_ key: String, _ name: String, rating: Int?, ratingAdj: Int, recencyAdj: Int) -> PortSummary {
        let sail = isoDay(daysFromNow: -26)
        return PortSummary(key: key, name: name, region: "Western Caribbean", rating: rating,
                           ratedAt: rating == nil ? nil : isoDay(daysFromNow: -2), visits: 1, lastVisited: sail,
                           daysSince: 26, history: [PortVisit(tripId: "trip-sample-aqua", sailDate: sail, rating: rating)],
                           ratingAdj: ratingAdj, recencyAdj: recencyAdj, adj: ratingAdj + recencyAdj)
    }

    static var portsJSON: JSONValue {
        .object([
            "asOf": .string(isoDay(daysFromNow: 0)),
            "knobs": .object(["recencyMonths": .int(6), "fadeMonths": .int(12), "useRatings": .bool(true)]),
            "ports": .array(portSummaries.map { JSONValue(encoding: $0) }),
            "computedAt": .string(Fmt.stamp()),
        ])
    }

    static let portsSummary = PortsSummary(asOf: isoDay(daysFromNow: 0), ports: portSummaries, computedAt: nil)
}
