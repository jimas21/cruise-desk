import Foundation

/// Made-up v5 data for previews, tests and screenshots: the catalog's regions and the visible default, what is
/// collected, a search that explains itself, a deal sheet, a line's add-ons guide and ship photo entries. Nothing
/// here is real: every price, date and credit is invented for the layout.
extension Samples {
    static let v5Features = V4Feature.allCases.map { $0.rawValue }
        + [V5Feature.catalog5, .explain, .collect, .reference, .sheet].map { $0.rawValue }

    /// The sample catalog on a v5 server: regions, the never-saved default, more lines' ships and counts.
    static let catalogV5: Catalog = {
        var c = Samples.catalogV4
        c.apiVersion = 5
        c.catalogVersion = 3
        c.features = v5Features
        c.linesState = LinesState(trip: "legacy_default", effective: [CruiseLine.royal])
        c.regions = [
            CatalogRegion(key: "caribbean", name: "Caribbean", aliases: ["Caribbean & Atlantic"], sailings: 2140),
            CatalogRegion(key: "western-caribbean", name: "Western Caribbean", parent: "caribbean", sailings: 980),
            CatalogRegion(key: "eastern-caribbean", name: "Eastern Caribbean", parent: "caribbean", sailings: 610),
            CatalogRegion(key: "southern-caribbean", name: "Southern Caribbean", parent: "caribbean", sailings: 240),
            CatalogRegion(key: "bahamas", name: "Bahamas", sailings: 520),
            CatalogRegion(key: "alaska", name: "Alaska", aliases: ["Inside Passage"], sailings: 58),
            CatalogRegion(key: "pacific-coastal", name: "Pacific Coastal", sailings: 31),
            CatalogRegion(key: "mexico", name: "Mexico", aliases: ["Mexican Riviera"], sailings: 190),
            CatalogRegion(key: "hawaii", name: "Hawaii", sailings: 12),
            CatalogRegion(key: "mediterranean", name: "Mediterranean", sailings: 0),
        ]
        func ship(_ name: String, _ cls: String, _ size: ShipSize, gt: Int? = nil, guests: Int? = nil) -> CatalogShip {
            var s = CatalogShip(name: name, slug: Slug.ship(name), className: cls, classSlug: Slug.plain(cls),
                                size: size.rawValue, gt: gt)
            s.passengers = guests
            return s
        }
        c.lines = (c.lines ?? []).map { line in
            var l = line
            switch line.name ?? "" {
            case "Norwegian":
                l.ships = [
                    ship("Norwegian Prima", "Prima", .large), ship("Norwegian Viva", "Prima", .large),
                    ship("Norwegian Aqua", "Prima", .large, gt: 156_300, guests: 3_571),
                    ship("Norwegian Getaway", "Breakaway", .large), ship("Norwegian Breakaway", "Breakaway", .large),
                ]
                l.sailings = 0
            case "Disney":
                l.ships = [
                    ship("Disney Wish", "Wish", .large), ship("Disney Treasure", "Wish", .large),
                    ship("Disney Dream", "Dream", .large), ship("Disney Fantasy", "Dream", .large),
                    ship("Disney Magic", "Magic", .mid), ship("Disney Wonder", "Magic", .mid),
                ]
                l.sailings = 289
                l.coverage = "tracking_live"
                l.coverageNote = nil
                l.sources = [CatalogLineSource(source: "Example agency", listed: 700,
                                               ships: ["disney-wish", "disney-dream", "disney-fantasy", "disney-treasure"])]
            default:
                break
            }
            return l
        }
        return c
    }()

    /// v5 docs: the v4 samples, with the trip's lines never saved (the visible default), a sheet on the Icon deal
    /// and on the tracked Star sailing, Collect prices for, and what we had on the Aqua trip.
    static var docsV5: [String: [String: RawDoc]] {
        var colls = docsV4
        func merge(_ coll: String, _ id: String, _ fields: [String: JSONValue]) {
            guard var doc = colls[coll]?[id] else { return }
            doc.data = doc.data.merging(fields)
            colls[coll]?[id] = doc
        }
        func put(_ coll: String, _ id: String, _ value: JSONValue) {
            colls[coll, default: [:]][id] = RawDoc(id: id, data: value, version: 1, updatedAt: nil)
        }
        var tripDoc = Samples.trip.fields(stamp: Fmt.stamp(Date().addingTimeInterval(-86400)), v3: true)
        tripDoc["lines"] = nil
        tripDoc["buyKinds"] = .array([.string("wifi")])
        tripDoc["homeAirport"] = .string("ORD")
        put("prefs", "trip", .object(tripDoc))
        put("prefs", "collect", .object(["lines": .array([.string("Disney")]), "every": .bool(false),
                                         "updatedAt": .string(Fmt.stamp())]))
        merge("deals", "sample-fits", ["sheet": sheetJSON])
        merge("tracked", "trk-sample-star", ["sheet": sheetJSON])
        merge("trips", "trip-sample-aqua", ["extras": .array([
            .object(["name": .string("Drinks package"), "kind": .string("drinks"), "how": .string("promo"),
                     "liked": .bool(true)]),
        ])])
        return colls
    }

    static let sheetText = """
    {"party": {"adults": 2, "children": 1, "childAges": [], "guests": 3, "childAgesKnown": false},
     "cabin": "balcony", "category": "Ocean View Balcony",
     "lines": [
      {"key": "fare", "label": "Cruise fare (2 × $1,276)", "amount": 2552, "low": 2552, "high": 2552, "basis": "read",
       "detail": "the best balcony fare seen", "source": "Example agency", "asOf": null, "counted": true},
      {"key": "extraGuests", "label": "3rd guest fare", "amount": null, "low": null, "high": 1276, "basis": "not_shown",
       "detail": "not shown by any source; counted at up to the per-person fare in the high end", "source": null,
       "asOf": null, "counted": false},
      {"key": "taxes", "label": "Taxes, fees, ports", "amount": 567, "low": 567, "high": 567, "basis": "read",
       "detail": "$189 × 3", "source": "Example agency", "asOf": null, "counted": true},
      {"key": "gratuities", "label": "Gratuities ($18.50 × 6 × 3)", "amount": 333, "low": 333, "high": 333,
       "basis": "rule", "detail": "the line's daily rate", "source": "Royal 2026 rate", "asOf": "2026-11-27",
       "counted": true},
      {"key": "addon:voom", "label": "Wi-Fi (you buy it)", "amount": null, "low": 264, "high": 312, "basis": "rule",
       "detail": "2 devices × 6 days", "source": "Royal 2026", "asOf": "2026-11-27", "counted": true},
      {"key": "flights", "label": "Flights ORD–IAH", "amount": null, "low": null, "high": null, "basis": "not_shown",
       "detail": "flight estimate not set up", "source": null, "asOf": null, "counted": false}
     ],
     "total": {"firm": 3452, "low": 3716, "high": 5040, "cabinLow": 3119, "cabinHigh": 4395, "complete": false,
               "notShown": ["3rd guest fare", "Flights", "Hotel night"]},
     "budget": {"budgetTotal": 3200, "basis": "cabin", "low": 3119, "high": 4395, "state": "within_tradeoff"},
     "verdict": {"label": "YOUR_CALL", "reasons": ["within_tradeoff", "price_under:22", "incomplete:3"],
                 "line": "22% under typical; the 3rd guest's fare and the flights decide it.", "lineBy": "api"},
     "bundle": null,
     "whatToBuy": [
      {"kind": "wifi", "key": "voom", "name": "VOOM Wi-Fi", "low": 264, "high": 312, "unit": "pppd-device",
       "persons": 2, "buyWhen": "pre-cruise", "worthIt": "Worth it for one or two phones", "counted": true},
      {"kind": "drinks", "key": "deluxe-bev", "name": "Deluxe Beverage Package", "low": 1176, "high": 1428,
       "unit": "pppd", "persons": 2, "buyWhen": "pre-cruise", "worthIt": "Only if you'd drink six or more a day",
       "counted": false},
      {"kind": "soft-drinks", "key": "refreshment", "name": "Refreshment Package", "low": 420, "high": 504,
       "unit": "pppd", "persons": 3, "buyWhen": "pre-cruise", "worthIt": "Handy with a child who likes soda",
       "counted": false}
     ],
     "pay": {"depositPP": 250, "depositNote": "per guest, at booking", "finalPaymentDate": "2027-06-07",
             "refundableBeforeFinal": true, "note": "Royal Caribbean's standard terms as of 2026-11; confirm at booking.",
             "basis": "rule", "asOf": "2026-11"},
     "travel": {"mode": "fly", "fromAirport": "ORD", "toAirport": "IAH", "departDate": "2027-09-04",
                "returnDate": "2027-09-11", "flight": {"pp": null, "total": null, "ageDays": null, "provider": null,
                "state": "not_set_up"},
                "searchUrl": "https://www.google.com/travel/flights?q=Flights%20from%20ORD%20to%20IAH%20on%202027-09-04%20through%202027-09-11",
                "lineAir": {"program": "The line's air program", "url": "https://www.example.com/air",
                            "note": "An option to compare, never a price here."},
                "hotel": {"nights": 1, "low": null, "high": null, "basis": "not_shown"}},
     "itinerary": {"seaDays": 2, "portDays": 3, "scenicDays": 0},
     "freshness": {"fareSeenAt": null, "oldestFigureAt": "2026-11-27"},
     "refAsOf": "2026-11-27", "sig": "sample", "builtAt": null}
    """

    static var sheetJSON: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(sheetText.utf8))) ?? .null
    }

    static var sheet: DealSheet? { DealSheet.from(.object(["sheet": sheetJSON])) }

    /// What is collected: Royal always, Disney just added, Norwegian not collected, Cunard with no source.
    static let collectState = CollectState(
        linesState: LinesState(trip: "legacy_default", effective: [CruiseLine.royal]),
        lines: [
            CollectLine(line: "Royal Caribbean", state: "collecting", why: ["always"], tier: "daily",
                        sources: [CollectSource(source: "Example agency", listed: 5_100, collected: 4_986, passDays: 1)]),
            CollectLine(line: "Disney", state: "queued", why: ["collect"], tier: "named",
                        sources: [CollectSource(source: "Example agency", listed: 700, collected: 0, passDays: 1)],
                        note: "added today"),
            CollectLine(line: "Norwegian", state: "not_collected", why: []),
            CollectLine(line: "Cunard", state: "no_source", why: [], note: "no source we read lists this line"),
        ])

    /// The catalog's ports, searched by name.
    static func ports(matching text: String, kind: PortKind) -> [CatalogPort] {
        let all = [
            CatalogPort(key: "seattle", name: "Seattle", country: "United States", region: "Pacific Coastal",
                        kind: "embark", airports: ["SEA"], sailings: 5),
            CatalogPort(key: "vancouver", name: "Vancouver", country: "Canada", region: "Alaska", kind: "both",
                        airports: ["YVR"], sailings: 17),
            CatalogPort(key: "galveston", name: "Galveston", country: "United States", region: "Western Caribbean",
                        kind: "embark", airports: ["IAH", "HOU"], sailings: 210),
            CatalogPort(key: "miami", name: "Miami", country: "United States", region: "Caribbean", kind: "embark",
                        airports: ["MIA"], sailings: 640),
            CatalogPort(key: "juneau", name: "Juneau", country: "United States", region: "Alaska", kind: "call",
                        sailings: 41),
            CatalogPort(key: "ketchikan", name: "Ketchikan", country: "United States", region: "Alaska", kind: "call",
                        sailings: 39),
            CatalogPort(key: "glacier-bay", name: "Glacier Bay", country: "United States", region: "Alaska",
                        kind: "scenic", sailings: 12),
            CatalogPort(key: "cozumel", name: "Cozumel", country: "Mexico", region: "Western Caribbean", kind: "call",
                        sailings: 720),
        ]
        let needle = text.trimmed.lowercased()
        return all.filter { port in
            kind.admits(port.kind) && (needle.isEmpty || port.name.lowercased().contains(needle))
        }
    }

    /// A search for Disney in Alaska from Seattle or Vancouver that finds nothing, and says why.
    static let searchExplained = SearchResult(
        rows: [], total: 0, nextOffset: nil, notes: [],
        funnel: [FunnelStep(step: "seen", label: "Seen 9,410", remaining: 9_410),
                 FunnelStep(step: "line", label: "Disney 289", remaining: 289),
                 FunnelStep(step: "dates", label: "2027 289", remaining: 289),
                 FunnelStep(step: "port", label: "Seattle or Vancouver 0", remaining: 0),
                 FunnelStep(step: "region", label: "Alaska 0", remaining: 0)],
        coverageGap: [CoverageGap(line: "Disney", reason: "no_source_for_ships", ships: ["Disney Magic", "Disney Wonder"],
                                  region: "alaska",
                                  note: "No source we read lists Disney Magic or Disney Wonder, which sail Alaska from Vancouver in 2027",
                                  action: "open_line")],
        why: ["No source we read lists Disney Magic or Disney Wonder, which sail Alaska from Vancouver in 2027.",
              "None of the 289 Disney sailings we see leave from Seattle or Vancouver."])

    static let disneyAlaska = SearchQuery(lines: ["Disney"], ports: ["Seattle", "Vancouver"], regions: ["Alaska"],
                                          dateFrom: "2027-01-01", dateTo: "2027-12-31", cabin: "balcony")

    /// The preview server's search: the explained empty result for a Disney search on v5, else the v4 rows (with a
    /// trip cost on the first when the catalog lists `sheet`).
    static func previewSearch(_ query: SearchQuery, catalog: Catalog) -> SearchResult {
        if catalog.has(.explain), query.lines.contains(where: { CruiseLine.same($0, "Disney") }) { return searchExplained }
        var result = searchResult
        if catalog.has(.sheet), !result.rows.isEmpty, let sheet {
            result.rows[0].tripCost = sheet.tripCost
        }
        return result
    }

    static let addonsText = """
    {"line": "Royal Caribbean",
     "gratuity": {"pppd": {"standard": 18.5, "suite": 21}, "appliesTo": "all", "includedWithBundles": [],
                  "asOf": "2026-11-27", "note": "Charged daily to the onboard account.", "source": "https://www.example.com/tips"},
     "included": ["Main dining room and buffet", "Kids' clubs", "Water, iced tea and lemonade"],
     "notIncluded": ["Alcohol", "Soda", "Wi-Fi", "Specialty dining"],
     "addons": [
      {"key": "voom", "kind": "wifi", "name": "VOOM Wi-Fi", "priceLow": 22, "priceHigh": 26, "onboardLow": 28,
       "onboardHigh": 32, "unit": "pppd-device", "buyWhen": "pre-cruise", "appliesTo": "device", "cabinRule": null,
       "defaultForKind": true, "worthIt": {"couple": "One or two devices", "family": "A device per adult"},
       "notes": "Sample figures for the layout.", "asOf": "2026-11-27", "source": "https://www.example.com/voom"},
      {"key": "deluxe-bev", "kind": "drinks", "name": "Deluxe Beverage Package", "priceLow": 98, "priceHigh": 119,
       "onboardLow": 108, "onboardHigh": 137, "unit": "pppd", "buyWhen": "pre-cruise", "appliesTo": "adults",
       "cabinRule": "Every adult in the cabin must buy it.", "defaultForKind": true,
       "worthIt": {"couple": "Six or more drinks a day", "family": null}, "notes": null, "asOf": "2026-11-27",
       "source": "https://www.example.com/drinks"}
     ],
     "bundles": [],
     "sources": ["https://www.example.com/tips", "https://www.example.com/voom"],
     "forParty": [
      {"kind": "wifi", "key": "voom", "name": "VOOM Wi-Fi", "low": 308, "high": 364, "unit": "pppd-device", "persons": 2,
       "buyWhen": "pre-cruise", "worthIt": "One or two devices", "counted": true}
     ],
     "asOf": "2026-11-27"}
    """

    static var addonsGuide: AddonsGuide? { AddonsGuide.decodeResponse(Data(addonsText.utf8), line: CruiseLine.royal) }

    /// Photo entries for a few classes (no image files: the preview draws plain bars at the same lengths).
    static let shipPhotos: ShipPhotoManifest = {
        let text = """
        {"Royal Caribbean|Icon": {"file": "royal-caribbean-icon.jpg", "shipInPhoto": "Icon of the Seas", "sister": false,
           "author": "Example photographer", "license": "CC BY-SA 4.0",
           "commonsPage": "https://commons.wikimedia.org/wiki/File:Example_1.jpg", "lengthFt": 1198, "aspect": 5.6},
         "Royal Caribbean|Oasis": {"file": "royal-caribbean-oasis.jpg", "shipInPhoto": "Wonder of the Seas",
           "sister": false, "author": "Example photographer", "license": "CC BY 2.0",
           "commonsPage": "https://commons.wikimedia.org/wiki/File:Example_2.jpg", "lengthFt": 1188, "aspect": 5.9},
         "Royal Caribbean|Quantum": {"file": "royal-caribbean-quantum.jpg", "shipInPhoto": "Anthem of the Seas",
           "sister": false, "author": "Example photographer", "license": "CC0",
           "commonsPage": "https://commons.wikimedia.org/wiki/File:Example_3.jpg", "lengthFt": 1139, "aspect": 6.2},
         "Norwegian|Prima": {"file": "norwegian-prima.jpg", "shipInPhoto": "Norwegian Prima", "sister": false,
           "author": "Example photographer", "license": "CC BY-SA 4.0",
           "commonsPage": "https://commons.wikimedia.org/wiki/File:Example_4.jpg", "lengthFt": 965, "aspect": 6.4},
         "Norwegian|Breakaway": {"file": "norwegian-breakaway.jpg", "shipInPhoto": "Norwegian Getaway", "sister": false,
           "author": "Example photographer", "license": "CC BY-SA 3.0",
           "commonsPage": "https://commons.wikimedia.org/wiki/File:Example_5.jpg", "lengthFt": 1068, "aspect": 6.6}}
        """
        return ShipPhotoManifest.decode(Data(text.utf8))
    }()
}

extension Store {
    /// The preview on a v5 server: pickers, the visible default, collection, the sheet, guides and ship sizes.
    static func previewV5() -> Store {
        Store(previewDocs: Samples.docsV5, catalog: Samples.catalogV5)
    }
}
