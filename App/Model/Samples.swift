import Foundation

/// Made-up data for SwiftUI previews: one deal of each kind, a couple of ways to save and rules.
/// Nothing here is a real booking or anyone's real trip.
enum Samples {
    static let fits: DealData = {
        var d = DealData()
        d.kind = "fits"
        d.ship = "Icon of the Seas"
        d.shipClass = "icon"
        d.sailDate = "2028-10-15"
        d.nights = 7
        d.port = "Galveston"
        d.roundTrip = true
        d.region = "Western Caribbean"
        d.cabin = "balcony"
        d.cabinName = "Ocean View Balcony"
        d.oceanViewConfirmed = nil
        d.pricePP = 1138
        d.priceIncludesTaxes = true
        d.usualPP = 1520
        d.lowestSeenPP = 1138
        d.perNightPP = 163
        d.totalFor3 = 2580
        d.totalAssumes = "3rd guest sails free"
        d.score = 70
        d.scoreLabel = "Great"
        d.why = "Lowest Icon balcony we've seen — $163/night vs $216"
        d.flight = "~3h nonstop"
        d.perks = ["Free 3rd guest", "BOGO60", "$75 onboard credit"]
        d.bookBy = Samples.isoDay(daysFromNow: 2)
        d.bookByWhat = "Black Friday $300 off"
        d.link = "https://example.com/sailing"
        d.linkLabel = "Example agency"
        d.sources = [
            DealSource(name: "Example agency", url: "https://example.com/a", pricePP: 1138, includesTaxes: true),
            DealSource(name: "Cruise line site", url: "https://example.com/b", pricePP: 1176, includesTaxes: false),
        ]
        d.ports = ["Roatán", "Costa Maya", "Cozumel"]
        d.nearby = "Oct 22 sailing is $40 pp more."
        d.scoreHow = "+40 below the 3-month median, +20 lowest seen, +10 free 3rd guest"
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-3600))
        d.changedAt = d.postedAt
        return d
    }()

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
        d.cabin = "balcony"
        d.oceanViewConfirmed = true
        d.pricePP = 689
        d.priceIncludesTaxes = true
        d.usualPP = 910
        d.totalFor3 = 1540
        d.score = 62
        d.scoreLabel = "Good"
        d.why = "Oasis-class balcony at $172/night, 24% under usual"
        d.breaks = "4 nights, Florida"
        d.link = "https://example.com/wonder"
        d.linkLabel = "Example agency"
        d.postedAt = Fmt.stamp(Date().addingTimeInterval(-7200))
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
        Deal(id: "sample-call", data: call),
        Deal(id: "sample-drop", data: drop),
    ]

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
            "note": .string(""), "updatedAt": .string(Fmt.stamp()),
            "claudeReply": .string("Watching it. I'll ping you if it goes under $1,200 pp."),
        ]))
        put("plays", "sample-live", JSONValue(encoding: livePlay))
        put("plays", "sample-standing", JSONValue(encoding: standingPlay))
        put("playnotes", "sample-live", .object(["status": .string("using"), "note": .string(""), "updatedAt": .string(Fmt.stamp())]))
        put("rules", "sample-rule-1", .object([
            "text": .string("No sailings under 6 nights"), "unless": .string("the price is exceptional"),
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
            .string("Balcony, ocean view preferred"), .string("6–8 nights"), .string("Newer, bigger ships"),
        ])]))
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
