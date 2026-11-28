import Foundation

/// Made-up 1.6 data for previews, tests and screenshots: a server that lists `flights`, a deal sheet whose trip cost
/// counts a flight estimate (a recent fare seen, with its basis and the disembark-day rule), a sailing the party
/// drives to, and a soft budget that says how far over. Nothing here is real: every fare, date and figure is
/// invented for the layout.
extension Samples {
    static let v6Features = v5Features + [V5Feature.flights.rawValue]

    /// The v5 sample catalog on a server that also has flight estimates.
    static let catalogV6: Catalog = {
        var c = Samples.catalogV5
        c.features = v6Features
        return c
    }()

    /// v6 docs: the v5 samples, with the budget counting the whole trip, a port the party drives to, a sheet with a
    /// flight estimate on the Icon deal and a drive sheet on the tracked Star sailing.
    static var docsV6: [String: [String: RawDoc]] {
        var colls = docsV5
        func merge(_ coll: String, _ id: String, _ fields: [String: JSONValue]) {
            guard var doc = colls[coll]?[id] else { return }
            doc.data = doc.data.merging(fields)
            colls[coll]?[id] = doc
        }
        merge("prefs", "trip", ["budgetBasis": .string("trip"), "groundPorts": .array([.string("port-canaveral")]),
                                "buyKinds": .array([.string("wifi")]), "hotelNightBefore": .bool(true)])
        merge("deals", "sample-fits", ["sheet": sheetFlyJSON])
        merge("tracked", "trk-sample-star", ["sheet": sheetDriveJSON])
        return colls
    }

    /// Fly: the flight is a recent fare seen three days ago, per person in economy, counted in the trip cost as an
    /// estimate; the return is assumed after 1 PM (the fare is for the day, not a flight).
    static let sheetFlyText = """
    {"party": {"adults": 2, "children": 1, "childAges": [], "agesOnSailing": [8], "guests": 3, "childAgesKnown": true},
     "cabin": {"type": "balcony", "category": "Ocean View Balcony"},
     "lines": [
      {"key": "fare", "label": "Cruise fare (2 × $1,276)", "amount": 2552, "low": 2552, "high": 2552, "basis": "read",
       "detail": "the best balcony fare seen", "source": "Example agency", "asOf": null, "counted": true},
      {"key": "extraGuests", "label": "3rd guest fare", "amount": null, "low": null, "high": 1276, "basis": "estimate",
       "detail": "3rd guest fare not shown; counted at up to the per-person fare in the high end", "source": null,
       "asOf": null, "counted": false},
      {"key": "taxes", "label": "Taxes, fees, ports", "amount": 567, "low": 567, "high": 567, "basis": "read",
       "detail": "$189 × 3", "source": "Example agency", "asOf": null, "counted": true},
      {"key": "gratuities", "label": "Gratuities ($18.50 × 6 × 3)", "amount": 333, "low": 333, "high": 333,
       "basis": "rule", "detail": "the line's daily rate", "source": "Example 2026 rate", "asOf": "2026-11-27",
       "counted": true},
      {"key": "addon:voom", "label": "Wi-Fi (you buy it)", "amount": null, "low": 264, "high": 312, "basis": "rule",
       "detail": "2 devices × 6 days", "source": "Example 2026", "asOf": "2026-11-27", "counted": true},
      {"key": "flights", "label": "Flights", "amount": null, "low": 1290, "high": 1290, "basis": "estimate",
       "detail": "recent fare seen 2026-11-24, ORD–IAH, per person, economy (est., round trip)",
       "source": "example provider", "asOf": "2026-11-24", "counted": true},
      {"key": "hotel", "label": "Hotel night before", "amount": null, "low": 150, "high": 230, "basis": "estimate",
       "detail": "1 room, 1 night in Galveston", "source": "Example rate", "asOf": "2026-11", "counted": true}
     ],
     "total": {"firm": 3452, "low": 5156, "high": 6560, "cabinLow": 3119, "cabinHigh": 4395, "complete": false,
               "notShown": ["3rd guest fare"]},
     "budget": {"budgetTotal": 3200, "basis": "trip", "low": 5156, "high": 6560, "state": "over", "overBy": 1956,
                "complete": true},
     "verdict": {"label": "YOUR_CALL", "reasons": ["over_budget:61", "price_under:22"],
                 "line": "22% under typical; $1,956 over your $3,200 target.", "lineBy": "api"},
     "bundle": null,
     "whatToBuy": [
      {"kind": "wifi", "key": "voom", "name": "VOOM Wi-Fi", "low": 264, "high": 312, "unit": "pppd-device",
       "persons": 2, "buyWhen": "pre-cruise", "worthIt": "Worth it for one or two phones", "counted": true}
     ],
     "pay": {"depositPP": 250, "depositNote": "per guest, at booking", "finalPaymentDate": "2027-06-07",
             "refundableBeforeFinal": true, "note": "The line's standard terms as of 2026-11; confirm at booking.",
             "basis": "rule", "asOf": "2026-11"},
     "travel": {"mode": "fly", "fromAirport": "ORD", "toAirport": "IAH", "departDate": "2027-09-04",
                "returnDate": "2027-09-11", "returnNotBefore": "13:00",
                "note": "Return after 1 PM assumed on disembark day (the fare is date-level); never priced on an earlier flight.",
                "flight": {"pp": 430, "total": 1290, "ageDays": 3, "provider": "example provider", "state": "ready",
                           "foundAt": "2026-11-24",
                           "basis": "recent fare seen 2026-11-24, ORD–IAH, per person, economy",
                           "route": "ORD–IAH", "returnNotBefore": "13:00"},
                "searchUrl": "https://www.google.com/travel/flights?q=Flights%20from%20ORD%20to%20IAH%20on%202027-09-04%20through%202027-09-11",
                "lineAir": {"program": "The line's air program", "url": "https://www.example.com/air",
                            "note": "An option to compare, never a price here."},
                "hotel": {"nights": 1, "low": 150, "high": 230, "basis": "estimate"}},
     "itinerary": {"seaDays": 2, "portDays": 3, "scenicDays": 0},
     "freshness": {"fareSeenAt": null, "oldestFigureAt": "2026-11-24"},
     "refAsOf": "2026-11-27", "sig": "sample-fly", "builtAt": null}
    """

    /// Drive: a port the party drives to; no flight, no hotel, nothing for getting there in the total.
    static let sheetDriveText = """
    {"party": {"adults": 2, "children": 1, "childAges": [], "agesOnSailing": [8], "guests": 3, "childAgesKnown": true},
     "cabin": "balcony", "category": "Ocean View Balcony",
     "lines": [
      {"key": "fare", "label": "Cruise fare (2 × $1,276)", "amount": 2552, "low": 2552, "high": 2552, "basis": "read",
       "detail": "the best balcony fare seen", "source": "Example agency", "asOf": null, "counted": true},
      {"key": "extraGuests", "label": "3rd guest fare", "amount": null, "low": null, "high": 1276, "basis": "estimate",
       "detail": "3rd guest fare not shown; counted at up to the per-person fare in the high end", "source": null,
       "asOf": null, "counted": false},
      {"key": "taxes", "label": "Taxes, fees, ports", "amount": 567, "low": 567, "high": 567, "basis": "read",
       "detail": "$189 × 3", "source": "Example agency", "asOf": null, "counted": true},
      {"key": "gratuities", "label": "Gratuities ($16 × 7 × 3)", "amount": 336, "low": 336, "high": 336,
       "basis": "rule", "detail": "the line's daily rate", "source": "Example 2026 rate", "asOf": "2026-11-27",
       "counted": true},
      {"key": "addon:voom", "label": "Wi-Fi (you buy it)", "amount": null, "low": 308, "high": 364, "basis": "rule",
       "detail": "2 devices × 7 days", "source": "Example 2026", "asOf": "2026-11-27", "counted": true}
     ],
     "total": {"firm": 3455, "low": 3763, "high": 5095, "cabinLow": 3119, "cabinHigh": 4395, "complete": false,
               "notShown": ["3rd guest fare"]},
     "budget": {"budgetTotal": 3200, "basis": "trip", "low": 3763, "high": 5095, "state": "over", "overBy": 563,
                "complete": true},
     "verdict": {"label": "YOUR_CALL", "reasons": ["over_budget:18", "price_typical"],
                 "line": "About typical; $563 over your $3,200 target.", "lineBy": "api"},
     "bundle": null, "whatToBuy": [],
     "pay": {"depositPP": null, "depositNote": null, "finalPaymentDate": null, "refundableBeforeFinal": null,
             "note": "not researched yet; check on the line's page", "basis": "not_shown", "asOf": null},
     "travel": {"mode": "drive", "fromAirport": "ORD", "toAirport": "MCO", "departDate": null, "returnDate": null,
                "returnNotBefore": null, "note": "Drive or train to the port; not priced.",
                "flight": {"pp": null, "total": null, "ageDays": null, "provider": null, "state": "none"},
                "searchUrl": null, "lineAir": null, "hotel": {"nights": 0, "low": null, "high": null, "basis": "not_shown"}},
     "itinerary": {"seaDays": 3, "portDays": 3, "scenicDays": 0},
     "freshness": {"fareSeenAt": null, "oldestFigureAt": "2026-11-27"},
     "refAsOf": "2026-11-27", "sig": "sample-drive", "builtAt": null}
    """

    static var sheetFlyJSON: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(sheetFlyText.utf8))) ?? .null
    }

    static var sheetDriveJSON: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(sheetDriveText.utf8))) ?? .null
    }

    static var sheetFly: DealSheet? { DealSheet.from(.object(["sheet": sheetFlyJSON])) }
    static var sheetDrive: DealSheet? { DealSheet.from(.object(["sheet": sheetDriveJSON])) }
}

extension Store {
    /// The preview on a 1.6 server: everything v5 has, plus flight estimates in the trip cost.
    static func previewV6() -> Store {
        Store(previewDocs: Samples.docsV6, catalog: Samples.catalogV6)
    }
}
