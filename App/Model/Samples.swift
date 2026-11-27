import Foundation

/// Made-up data for SwiftUI previews and the screenshot test: a few deals (one in the v2 shape with the full
/// summary sheet, older ones in the v1 shape, one on another line), ways to save, rules, trip settings, questions,
/// a price history, a v3 catalog and tracked sailings in every fill state. Nothing here is a real booking or
/// anyone's real trip.
enum Samples {
    static let fits: DealData = {
        var d = DealData()
        d.kind = "fits"
        d.ship = "Icon of the Seas"
        d.shipClass = "icon"
        d.sailDate = "2027-09-05"
        d.returnDate = "2027-09-11"
        d.nights = 6
        d.port = "Galveston"
        d.roundTrip = true
        d.region = "Western Caribbean"
        d.stops = ["Cozumel", "Roatán", "Costa Maya"]
        d.cabin = "balcony"
        d.cabinName = "Ocean View Balcony"
        d.oceanViewConfirmed = true
        d.pricePP = 1276
        d.priceIncludesTaxes = true
        d.typicalPP = 1560
        d.lowPP = 1180
        d.highPP = 1940
        d.pctUnderTypical = 18
        d.lowestSeenPP = 1240
        d.perNightPP = 213
        d.totalFor3 = 2650
        d.totalAssumes = "3rd guest at the kids' fare, tips in"
        d.score = 78
        d.scoreLabel = "Great"
        d.why = "Lowest Icon balcony we've seen this year"
        d.flight = "~3h nonstop"
        d.perks = ["Kids sail at a low fare", "$100 onboard credit"]
        d.bookBy = Samples.isoDay(daysFromNow: 2)
        d.bookByWhat = "Holiday sale price"
        d.link = "https://example.com/sailing"
        d.linkLabel = "Example agency"
        d.sources = [
            DealSource(name: "Example agency", url: "https://example.com/a", pricePP: 1276, includesTaxes: true),
            DealSource(name: "Cruise line site", url: "https://example.com/b", pricePP: 1318, includesTaxes: true),
        ]
        d.cabinOptions = [
            CabinOption(category: "Interior", type: "interior", pricePP: 899, taxesIncluded: true, source: "Example agency"),
            CabinOption(category: "Ocean View", type: "oceanview", pricePP: 1049, taxesIncluded: true, source: "Example agency"),
            CabinOption(category: "Ocean View Balcony", type: "balcony", pricePP: 1276, taxesIncluded: true, source: "Example agency"),
            CabinOption(category: "Central Park Balcony", type: "balcony", pricePP: 1190, taxesIncluded: true, source: "Cruise line site"),
            CabinOption(category: "Grand Suite", type: "suite", pricePP: 3420, taxesIncluded: true, source: "Cruise line site"),
        ]
        d.itineraryDays = [
            ItineraryDay(day: 1, date: "2027-09-05", port: "Galveston", arrive: nil, depart: "4:00 PM"),
            ItineraryDay(day: 2, date: "2027-09-06", port: "At sea", arrive: nil, depart: nil),
            ItineraryDay(day: 3, date: "2027-09-07", port: "Cozumel", arrive: "8:00 AM", depart: "5:00 PM"),
            ItineraryDay(day: 4, date: "2027-09-08", port: "Roatán", arrive: "8:00 AM", depart: "4:00 PM"),
            ItineraryDay(day: 5, date: "2027-09-09", port: "Costa Maya", arrive: "8:00 AM", depart: "5:00 PM"),
            ItineraryDay(day: 6, date: "2027-09-10", port: "At sea", arrive: nil, depart: nil),
            ItineraryDay(day: 7, date: "2027-09-11", port: "Galveston", arrive: "6:00 AM", depart: nil),
        ]
        d.scoop = """
        A six-night Western Caribbean trip on the newest, biggest ship in the fleet, leaving Galveston on a Sunday \
        and back the next Saturday, with three beach stops and two lazy sea days. The price is for a real \
        ocean-view balcony (confirmed, not one facing inside the ship), and $2,650 covers all three of you with \
        taxes and tips, before flights.

        Why it's good: balconies on this ship usually go for about $1,560 a person; this is $1,276, about 18% \
        under, and close to the lowest we've seen ($1,180, briefly in the summer).

        The catches: early September is hurricane season, so travel insurance is worth it. The sale price ends \
        in two days, and the cheaper Central Park balconies look into the ship, not at the sea.

        Verdict: a strong, easy yes if the dates work for school.
        """
        d.scoreHow = "+40 well under typical, +20 near the lowest seen, +10 newest ship"
        d.nearby = "The Sep 12 sailing is $60 pp more."
        d.fitsTrip = true
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-3600))
        d.changedAt = d.postedAt
        return d
    }()

    /// A v1-shaped deal (usualPP, ports): still renders.
    static let call: DealData = {
        var d = DealData()
        d.kind = "call"
        d.ship = "Wonder of the Seas"
        d.shipClass = "oasis"
        d.sailDate = "2027-02-08"
        d.nights = 4
        d.port = "Port Canaveral"
        d.roundTrip = true
        d.region = "Bahamas"
        d.ports = ["Nassau", "CocoCay"]
        d.cabin = "balcony"
        d.oceanViewConfirmed = true
        d.pricePP = 689
        d.priceIncludesTaxes = true
        d.usualPP = 910
        d.totalFor3 = 1540
        d.score = 62
        d.scoreLabel = "Good"
        d.why = "Oasis-class balcony at $172/night, 24% under usual"
        d.breaks = "4 nights"
        d.link = "https://example.com/wonder"
        d.linkLabel = "Example agency"
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-7200))
        return d
    }()

    static let quantum: DealData = {
        var d = DealData()
        d.kind = "fits"
        d.ship = "Odyssey of the Seas"
        d.shipClass = "quantum"
        d.sailDate = "2027-03-14"
        d.returnDate = "2027-03-19"
        d.nights = 5
        d.port = "Fort Lauderdale"
        d.roundTrip = true
        d.region = "Western Caribbean"
        d.stops = ["Nassau", "Cozumel"]
        d.cabin = "balcony"
        d.cabinName = "Balcony"
        d.pricePP = 899
        d.priceIncludesTaxes = false
        d.typicalPP = 1020
        d.lowPP = 860
        d.highPP = 1310
        d.pctUnderTypical = 12
        d.totalFor3 = 2890
        d.score = 64
        d.scoreLabel = "Good"
        d.why = "Spring break week, 12% under the usual balcony price"
        d.link = "https://example.com/odyssey"
        d.linkLabel = "Example agency"
        d.fitsTrip = true
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-5400))
        return d
    }()

    static let drop: DealData = {
        var d = DealData()
        d.kind = "drop"
        d.ship = "Harmony of the Seas"
        d.shipClass = "oasis"
        d.sailDate = "2027-10-16"
        d.nights = 7
        d.port = "Galveston"
        d.roundTrip = true
        d.region = "Western Caribbean"
        d.cabin = "balcony"
        d.pricePP = 1239
        d.previousPP = 1288
        d.priceIncludesTaxes = true
        d.usualPP = 1310
        d.score = 48
        d.scoreLabel = "Good"
        d.why = "Down $49 pp since yesterday; ties our lowest seen"
        d.link = "https://example.com/harmony"
        d.linkLabel = "Example agency"
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-600))
        return d
    }()

    static let sale: DealData = {
        var d = DealData()
        d.kind = "sale"
        d.ship = "Black Friday sale"
        d.nights = 6
        d.pricePP = 0
        d.score = 80
        d.scoreLabel = "Exceptional"
        d.why = "Biggest balcony discount of the year"
        d.offers = [
            OfferRow(label: "6+ nights balcony", value: "$300 off"),
            OfferRow(label: "2nd guest", value: "60% off"),
            OfferRow(label: "Kids", value: "Sail free"),
        ]
        d.endsAt = Samples.isoDay(daysFromNow: 2)
        d.link = "https://example.com/sale"
        d.linkLabel = "Cruise line site"
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-300))
        return d
    }()

    /// v3: a deal on another line (Celebrity), with its own class and size tier.
    static let celebrity: DealData = {
        var d = DealData()
        d.kind = "fits"
        d.line = "Celebrity"
        d.ship = "Celebrity Beyond"
        d.shipClass = "edge"
        d.shipSize = "large"
        d.sailDate = "2027-04-11"
        d.returnDate = "2027-04-18"
        d.nights = 7
        d.port = "Fort Lauderdale"
        d.roundTrip = true
        d.region = "Eastern Caribbean"
        d.stops = ["San Juan", "Tortola", "St. Maarten"]
        d.cabin = "balcony"
        d.cabinName = "Veranda"
        d.oceanViewConfirmed = true
        d.pricePP = 1049
        d.priceIncludesTaxes = false
        d.typicalPP = 1240
        d.lowPP = 990
        d.highPP = 1580
        d.pctUnderTypical = 15
        d.totalFor3 = 3150
        d.score = 58
        d.scoreLabel = "Good"
        d.why = "Edge-class veranda 15% under typical"
        d.link = "https://example.com/beyond"
        d.linkLabel = "Example agency"
        d.fitsTrip = true
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-8000))
        return d
    }()

    static let deals: [Deal] = [
        Deal(id: "sample-sale", data: sale),
        Deal(id: "sample-fits", data: fits),
        Deal(id: "sample-quantum", data: quantum),
        Deal(id: "sample-call", data: call),
        Deal(id: "sample-drop", data: drop),
        Deal(id: "sample-celebrity", data: celebrity),
    ]

    /// Made-up trip settings for previews: Icon, Oasis or Quantum, 5–8 nights, an ocean-view balcony, a family
    /// of three, $3,200 at most (trade-off above $2,800).
    static let trip: TripPrefs = {
        var p = TripPrefs()
        p.shipClasses = ["icon", "oasis", "quantum"]
        p.preferredClasses = ["icon", "oasis"]
        p.nightsMin = 5
        p.nightsMax = 8
        p.nightsPreferredMin = 6
        p.cabinTypes = ["balcony"]
        p.requireOceanView = true
        p.excludeBalconyTypes = ["central-park", "boardwalk"]
        p.adults = 2
        p.children = 1
        p.budgetTotal = 3200
        p.tradeoffBudget = 2800
        p.portsPreferred = ["Galveston", "Fort Lauderdale"]
        p.mustSeeMinScore = 80
        return p
    }()

    /// The same trip on a v3 server: Royal Caribbean and Celebrity, large and mega ships.
    static let tripV3: TripPrefs = {
        var p = trip
        p.lines = ["Royal Caribbean", "Celebrity"]
        p.shipSizes = ["large", "mega"]
        p.minPctUnder = 10
        return p
    }()

    // MARK: v3

    /// A made-up v3 catalog: Royal Caribbean tracked live, Celebrity from alert emails, the rest news only.
    static let catalog: Catalog = {
        func ship(_ name: String, _ cls: String, _ slug: String, _ size: ShipSize) -> CatalogShip {
            CatalogShip(name: name, slug: Slug.ship(name), className: cls, classSlug: slug, size: size.rawValue, gt: nil)
        }
        let royal = Catalog.builtIn.line(CruiseLine.royal)?.ships ?? []
        let celebrity = [
            ship("Celebrity Edge", "Edge", "edge", .large), ship("Celebrity Apex", "Edge", "edge", .large),
            ship("Celebrity Beyond", "Edge", "edge", .large), ship("Celebrity Ascent", "Edge", "edge", .large),
            ship("Celebrity Xcel", "Edge", "edge", .large),
        ]
        let norwegian = [
            ship("Norwegian Prima", "Prima", "prima", .large), ship("Norwegian Viva", "Prima", "prima", .large),
            ship("Norwegian Aqua", "Prima", "prima", .large),
        ]
        var lines: [CatalogLine] = [
            CatalogLine(name: "Royal Caribbean", slug: "royal-caribbean", coverage: "tracking_live",
                        coverageNote: "4 sources live · 412 sailings", liveSources: ["Example agency"], sailings: 412,
                        ships: royal),
            CatalogLine(name: "Celebrity", slug: "celebrity", coverage: "limited_data", coverageNote: "alert emails only",
                        liveSources: [], sailings: 18, ships: celebrity),
            CatalogLine(name: "Norwegian", slug: "norwegian", coverage: "news_only", coverageNote: "news and leads only",
                        liveSources: [], sailings: 0, ships: norwegian),
        ]
        for name in CruiseLine.names where !lines.contains(where: { $0.name == name }) {
            lines.append(CatalogLine(name: name, slug: CruiseLine.slug(name), coverage: "news_only",
                                     coverageNote: "news and leads only", liveSources: [], sailings: 0, ships: []))
        }
        let sizes = ShipSize.allCases.map { CatalogSize(tier: $0.rawValue, label: $0.title, gtMin: nil, gtMax: nil) }
        return Catalog(apiVersion: 3, catalogVersion: 1, generatedAt: Fmt.stamp(), sizes: sizes, lines: lines)
    }()

    /// Tracked sailings in each state: filled and live, still filling, a line with no price source, and sailed.
    static let trackedStar: TrackedData = {
        var t = TrackedData()
        t.line = "Royal Caribbean"
        t.ship = "Star of the Seas"
        t.sailDate = "2027-06-12"
        t.nights = 7
        t.cabin = "balcony"
        t.cabinName = "Ocean View Balcony"
        t.addedVia = "pick"
        t.addedAt = Fmt.stamp(Date().addingTimeInterval(-12 * 86400))
        t.fareState = "matched"
        t.coverage = "tracking_live"
        t.sailingId = "star-of-the-seas-2027-06-12-7n"
        t.pricePP = 1312
        t.perNightPP = 187
        t.priceIncludesTaxes = false
        t.priceCategory = "Ocean View Balcony"
        t.priceSource = "Example agency"
        t.priceSeenAt = Fmt.stamp(Date().addingTimeInterval(-3 * 3600))
        t.typicalPP = 1480
        t.typicalN = 14
        t.lowPP = 1190
        t.highPP = 1720
        t.pctUnderTypical = 11
        t.lowestSeenPP = 1248
        t.lowestSeenAt = Samples.isoDay(daysFromNow: -20)
        t.history = [1460, 1420, 1395, 1248, 1330, 1376, 1340, 1312].enumerated().map { item in
            DailyPrice(date: Samples.isoDay(daysFromNow: (item.offset - 8) * 6), pp: item.element)
        }
        t.embarkPort = "Port Canaveral"
        t.returnDate = "2027-06-19"
        t.stops = ["Perfect Day at CocoCay", "Cozumel", "Roatán"]
        t.sources = [DealSource(name: "Example agency", url: "https://example.com/star", pricePP: 1312, includesTaxes: false)]
        t.cabinOptions = [
            CabinOption(category: "Interior", type: "interior", pricePP: 940, taxesIncluded: false, source: "Example agency"),
            CabinOption(category: "Ocean View Balcony", type: "balcony", pricePP: 1312, taxesIncluded: false,
                        source: "Example agency"),
            CabinOption(category: "Grand Suite", type: "suite", pricePP: 3610, taxesIncluded: false, source: "Example agency"),
        ]
        t.filledAt = Fmt.stamp(Date().addingTimeInterval(-3 * 3600))
        t.region = "Western Caribbean"
        t.alerts = [
            SiteAlert(site: "Cruise alert site", state: "set", note: "at Ocean View Balcony", at: Fmt.stamp()),
            SiteAlert(site: "Line's own alerts", state: "needs_jim", note: "needs a free account", at: Fmt.stamp()),
        ]
        t.alertPrices = [AlertPrice(source: "Cruise alert site", category: "Ocean View Balcony", pricePP: 1329,
                                    taxesIncluded: false, seenAt: Fmt.stamp(Date().addingTimeInterval(-86400)))]
        t.brainNote = "Down $64 since last week; still above the low from the spring."
        t.enrichedAt = Fmt.stamp(Date().addingTimeInterval(-6 * 3600))
        return t
    }()

    static let trackedBeyond: TrackedData = {
        var t = TrackedData()
        t.line = "Celebrity"
        t.ship = "Celebrity Beyond"
        t.sailDate = "2027-11-07"
        t.nights = 7
        t.cabin = "balcony"
        t.cabinName = "Veranda"
        t.port = "Fort Lauderdale"
        t.addedVia = "link"
        t.link = "https://example.com/beyond-nov"
        t.addedAt = Fmt.stamp(Date().addingTimeInterval(-2 * 86400))
        t.fareState = "searching"
        t.coverage = "limited_data"
        t.typicalN = 2
        return t
    }()

    static let trackedPrima: TrackedData = {
        var t = TrackedData()
        t.line = "Norwegian"
        t.ship = "Norwegian Prima"
        t.sailDate = "2028-02-20"
        t.nights = 7
        t.cabin = "oceanview"
        t.addedVia = "pick"
        t.addedAt = Fmt.stamp(Date().addingTimeInterval(-86400))
        t.fareState = "no_coverage"
        t.coverage = "news_only"
        return t
    }()

    static let trackedSailed: TrackedData = {
        var t = TrackedData()
        t.line = "Royal Caribbean"
        t.ship = "Wonder of the Seas"
        t.sailDate = Samples.isoDay(daysFromNow: -10)
        t.nights = 4
        t.cabin = "balcony"
        t.addedVia = "pick"
        t.addedAt = Fmt.stamp(Date().addingTimeInterval(-90 * 86400))
        t.fareState = "sailed"
        t.coverage = "tracking_live"
        t.pricePP = 702
        t.lowestSeenPP = 655
        return t
    }()

    static let tracked: [TrackedSailing] = [
        TrackedSailing(id: "trk-sample-star", data: trackedStar),
        TrackedSailing(id: "trk-sample-beyond", data: trackedBeyond),
        TrackedSailing(id: "trk-sample-prima", data: trackedPrima),
        TrackedSailing(id: "trk-sample-sailed", data: trackedSailed),
    ]

    /// Known sailings for the Track builder's browse-and-pick (the sample catalog's Star of the Seas).
    static let sailings: [FareSailing] = [
        ("2027-05-29", 7, 1388), ("2027-06-12", 7, 1312), ("2027-06-26", 7, 1406), ("2027-07-10", 7, 1452),
    ].map { item in
        FareSailing(id: "star-of-the-seas-\(item.0)-\(item.1)n", ship: "star-of-the-seas", line: "Royal Caribbean",
                    sailDate: item.0, nights: item.1, embarkPort: "Port Canaveral",
                    bestByClass: ["balcony": FareRow(pricePP: item.2, taxesIncluded: false, category: "Balcony",
                                                     source: "Example agency")])
    }

    /// A shared sailing page and its title, as Safari hands them over.
    static let sharedLink = "Star of the Seas — Jun 26, 2027 — 7-Night Caribbean https://allaboarddeals.com/cruise-lines/royal-caribbean/star-of-the-seas/2027-06-26-sample1"

    /// The sample Icon deal's prices over the last few months, oldest first.
    static let history: [String: [PricePoint]] = {
        let prices = [1420, 1389, 1335, 1240, 1310, 1276]
        let points = prices.enumerated().map { item in
            PricePoint(pricePP: item.element, cabin: "balcony", source: "Example agency",
                       seenAt: Fmt.stamp(Date().addingTimeInterval(Double(item.offset - prices.count) * 14 * 86400)))
        }
        return ["sample-fits": points]
    }()

    static let livePlay: PlayData = {
        var p = PlayData()
        p.kind = "now"
        p.title = "Black Friday stack: $300 off + free 3rd guest"
        p.who = "Cruise line, any agency"
        p.saves = "$300–$1,000+"
        p.how = "Book a 6+ night balcony before the deadline; the 3rd-guest offer applies automatically."
        p.stacks = "Agency onboard credit"
        p.catchText = "Non-refundable deposit on the lowest fares"
        p.deadline = Samples.isoDay(daysFromNow: 2)
        p.deadlineWhat = "$300 off ends"
        p.fit = "Yes: 6+ nights, balcony"
        p.link = "https://example.com/offer"
        p.linkLabel = "Offer page"
        p.addedAt = Fmt.stamp(Date())
        return p
    }()

    static let standingPlay: PlayData = {
        var p = PlayData()
        p.kind = "standing"
        p.title = "Reprice after booking"
        p.who = "Anyone booked before final payment"
        p.saves = "$50–$400"
        p.how = "If the fare drops before final payment, ask for the new price or the difference as credit."
        p.addedAt = Fmt.stamp(Date().addingTimeInterval(-86400))
        return p
    }()

    static var docs: [String: [String: RawDoc]] {
        var colls: [String: [String: RawDoc]] = [:]
        func put(_ coll: String, _ id: String, _ value: JSONValue) {
            colls[coll, default: [:]][id] = RawDoc(id: id, data: value, version: 1, updatedAt: nil)
        }
        for deal in deals { put("deals", deal.id, JSONValue(encoding: deal.data)) }
        put("feedback", "sample-drop", .object([
            "dealId": .string("sample-drop"), "verdict": .string("interested"), "reasons": .array([.string("watch")]),
            "note": .string(""), "updatedAt": .string(Fmt.stamp(Date().addingTimeInterval(-7200))),
            "claudeReadAt": .string(Fmt.stamp(Date().addingTimeInterval(-3600))),
            "claudeReply": .string("Watching it. I'll ping you if it goes under $1,200 pp."),
        ]))
        put("plays", "sample-live", JSONValue(encoding: livePlay))
        put("plays", "sample-standing", JSONValue(encoding: standingPlay))
        put("playnotes", "sample-live", .object(["status": .string("using"), "note": .string(""), "updatedAt": .string(Fmt.stamp())]))
        put("rules", "sample-rule-1", .object([
            "text": .string("No sailings under 5 nights"), "unless": .string("the price is exceptional"),
            "status": .string("active"), "origin": .string("jim"), "createdAt": .string(Fmt.stamp()),
        ]))
        put("rules", "sample-rule-2", .object([
            "text": .string("Skip ships older than 2015"), "status": .string("proposed"), "origin": .string("claude"),
            "why": .string("You passed on three older ships this month."),
            "question": .string("Should newer refits count?"), "createdAt": .string(Fmt.stamp()),
        ]))
        put("meta", "status", .object([
            "lastRun": .string(Fmt.stamp(Date().addingTimeInterval(-900))), "ok": .bool(true),
            "sourcesWorked": .array((1...10).map { JSONValue.string("Source \($0)") }), "sourcesFailed": .array([.string("Source 11")]),
            "sailingsChecked": .int(203), "newItems": .int(2), "summary": .string("Two new deals; one price drop."),
        ]))
        put("meta", "profile", .object(["lines": .array([
            .string("Balcony, ocean view preferred"), .string("5–8 nights"), .string("Newer, bigger ships"),
        ])]))
        put("prefs", "trip", .object(tripV3.fields(stamp: Fmt.stamp(Date().addingTimeInterval(-86400)), v3: true)))
        for item in tracked { put("tracked", item.id, JSONValue(encoding: item.data)) }
        put("questions", "q-sample-answered", .object([
            "dealId": .string("sample-fits"),
            "text": .string("Is the ocean-view balcony worth it over an interior cabin for us?"),
            "askedAt": .string(Fmt.stamp(Date().addingTimeInterval(-5400))),
            "answer": .string("For a family of three on a six-night trip, yes: it's $377 more per person, but you get a private outdoor space for naps and sea days, and these balconies sell out first. If you'd rather save, the plain Ocean View cabin is $227 less per person and still has a window."),
            "answeredAt": .string(Fmt.stamp(Date().addingTimeInterval(-5300))),
            "sources": .array([.object(["name": .string("Example guide"), "url": .string("https://example.com/guide")])]),
        ]))
        put("questions", "q-sample-waiting", .object([
            "dealId": .string("sample-fits"),
            "text": .string("Are gratuities included in the $2,650?"),
            "askedAt": .string(Fmt.stamp(Date().addingTimeInterval(-40))),
        ]))
        put("questions", "q-sample-general", .object([
            "text": .string("When do Caribbean prices usually drop?"),
            "askedAt": .string(Fmt.stamp(Date().addingTimeInterval(-86400))),
            "answer": .string("The biggest sales tend to come around Black Friday and in January to March, when most people book. Prices also dip about 60 to 90 days before sailing if cabins are unsold, but balconies on the newest ships rarely wait that long."),
            "answeredAt": .string(Fmt.stamp(Date().addingTimeInterval(-86300))),
        ]))
        return colls
    }

    static func isoDay(daysFromNow days: Int) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date().addingTimeInterval(Double(days) * 86400))
    }
}
