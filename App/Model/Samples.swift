import Foundation

/// Made-up data for SwiftUI previews and the screenshot test: a few deals (one in the v2 shape with the full
/// summary sheet, older ones in the v1 shape), ways to save, rules, trip settings, questions and a price history.
/// Nothing here is a real booking or anyone's real trip.
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

    static let deals: [Deal] = [
        Deal(id: "sample-sale", data: sale),
        Deal(id: "sample-fits", data: fits),
        Deal(id: "sample-quantum", data: quantum),
        Deal(id: "sample-call", data: call),
        Deal(id: "sample-drop", data: drop),
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
        put("prefs", "trip", .object(trip.fields(stamp: Fmt.stamp(Date().addingTimeInterval(-86400)))))
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

    private static func isoDay(daysFromNow days: Int) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date().addingTimeInterval(Double(days) * 86400))
    }
}
