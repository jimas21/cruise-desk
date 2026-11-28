import XCTest
@testable import DealDesk

/// CONTRACT_V5 for the app: every v5 part gated on the catalog's features, decoding that never rejects an unknown
/// field, the sheet's wording, and ship classes named in full (Jim: never "+ N more").
final class V5Tests: XCTestCase {
    // MARK: Feature gates (CONTRACT_V5 rule 0.8, section 9)

    func testV5FeaturesNeedApiVersion5AndTheirName() throws {
        let v5 = try JSONDecoder().decode(Catalog.self, from: Data("""
        {"apiVersion": 5, "features": ["booking", "search", "catalog5", "sheet"], "lines": []}
        """.utf8))
        XCTAssertTrue(v5.isV3)
        XCTAssertTrue(v5.has(.search), "v4 modes still turn on at apiVersion 5")
        XCTAssertTrue(v5.has(.catalog5))
        XCTAssertTrue(v5.has(.sheet))
        XCTAssertFalse(v5.has(.collect))
        XCTAssertFalse(v5.has(.flights))

        let v4 = try JSONDecoder().decode(Catalog.self, from: Data("""
        {"apiVersion": 4, "features": ["booking", "catalog5", "sheet"], "lines": []}
        """.utf8))
        XCTAssertFalse(v4.has(.catalog5), "a v5 name on a v4 server turns nothing on")
        XCTAssertFalse(v4.has(.sheet))
    }

    func testCatalogV5DecodesRegionsLinesStateAndSources() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data("""
        {"apiVersion": 5, "catalogVersion": 3, "features": ["catalog5"],
         "regions": [{"key": "caribbean", "name": "Caribbean", "parent": null, "aliases": ["Caribbean & Atlantic"]},
                     {"key": "western-caribbean", "name": "Western Caribbean", "parent": "caribbean"},
                     {"key": 7},
                     {"key": "alaska", "name": "Alaska", "aliases": ["Inside Passage"], "ciaIds": ["alaska-region"],
                      "sailings": 58}],
         "linesState": {"trip": "legacy_default", "effective": ["Royal Caribbean"]},
         "lines": [{"name": "Disney", "slug": "disney", "sailings": 289, "somethingNew": {"x": 1},
                    "sources": [{"source": "allaboard", "listed": 700, "ships": ["disney-wish"]}, "odd"],
                    "ships": [{"name": "Disney Wonder", "class": "Magic", "classSlug": "magic", "lengthFt": 964,
                               "beam_ft": 106, "decks": 11, "unknownField": true}]}]}
        """.utf8))
        XCTAssertEqual(catalog.regions?.map { $0.key }, ["caribbean", "western-caribbean", "alaska"],
                       "one bad region is skipped, never the list")
        XCTAssertEqual(catalog.regionTree.map { $0.region.key }, ["caribbean", "alaska"])
        XCTAssertEqual(catalog.regionTree.first?.children.map { $0.key }, ["western-caribbean"])
        XCTAssertTrue(catalog.region("Caribbean", contains: "Western Caribbean"), "a parent takes its children")
        XCTAssertTrue(catalog.region("Inside Passage", contains: "Alaska"), "aliases name a region")
        XCTAssertFalse(catalog.region("Alaska", contains: "Western Caribbean"))
        XCTAssertEqual(catalog.linesState?.isLegacyDefault, true)
        let disney = try XCTUnwrap(catalog.line("Disney"))
        XCTAssertEqual(disney.sources?.first?.listed, 700)
        XCTAssertEqual(disney.sources?.count, 1)
        let wonder = try XCTUnwrap(disney.ships?.first)
        XCTAssertEqual(wonder.lengthFt, 964)
        XCTAssertEqual(wonder.beamFt, 106)
        XCTAssertEqual(wonder.decks, 11)

        // The cache round trip keeps the v5 fields.
        let again = try JSONDecoder().decode(Catalog.self, from: JSONEncoder().encode(catalog))
        XCTAssertEqual(again.regions?.count, 3)
        XCTAssertEqual(again.linesState, catalog.linesState)
        XCTAssertEqual(again.line("Disney")?.ships?.first?.lengthFt, 964)
    }

    // MARK: Search (CONTRACT_V5 section 1.6)

    func testSearchResultReadsTheExplanationAndV4ShapesStillDecode() throws {
        let explained = try JSONDecoder().decode(SearchResult.self, from: Data("""
        {"rows": [], "total": 0, "notes": [],
         "funnel": [{"step": "seen", "label": "Seen 9,410", "remaining": 9410},
                    {"step": "line", "label": "Disney 289", "remaining": 289},
                    {"step": "port", "label": "Seattle or Vancouver 0", "remaining": 0}],
         "coverageGap": [{"line": "Disney", "reason": "no_source_for_ships", "ships": ["Disney Magic", "Disney Wonder"],
                          "region": "alaska", "note": "No source we read lists Disney Magic or Disney Wonder",
                          "action": "open_line"}],
         "why": ["No source we read lists Disney Magic or Disney Wonder, which sail Alaska from Vancouver in 2027", ""]}
        """.utf8))
        XCTAssertTrue(explained.hasExplanation)
        XCTAssertEqual(explained.funnel.map { $0.text }, ["Seen 9,410", "Disney 289", "Seattle or Vancouver 0"])
        XCTAssertEqual(explained.coverageGap.first?.ships, ["Disney Magic", "Disney Wonder"])
        XCTAssertEqual(explained.whyLines.count, 1, "an empty line is dropped")
        XCTAssertTrue(explained.whyLines[0].contains("Vancouver"))

        let v4 = try JSONDecoder().decode(SearchResult.self, from: Data("""
        {"rows": [{"sailingId": "a", "line": "Royal Caribbean", "pricePP": 900, "unknown": ["region"],
                   "regionBasis": "stops", "embarkKey": "seattle", "priceState": "schedule_only",
                   "tripCost": {"low": 5980, "high": 7240, "complete": false, "verdict": "YOUR_CALL"}}],
         "total": 1, "notes": ["n"]}
        """.utf8))
        XCTAssertFalse(v4.hasExplanation)
        let row = try XCTUnwrap(v4.rows.first)
        XCTAssertTrue(row.regionUnknown)
        XCTAssertTrue(row.scheduleOnly)
        XCTAssertEqual(row.embarkKey, "seattle")
        XCTAssertEqual(row.tripCost?.range, "$5,980–7,240")
        XCTAssertEqual(row.tripCost?.verdict, "YOUR_CALL")
    }

    func testSearchQueryKeepsOldSavedSearchesAndSendsCalls() throws {
        // A search saved by 1.4 (no `calls`) still opens.
        let old = try JSONDecoder().decode(SearchQuery.self, from: Data("""
        {"lines": ["Disney"], "ships": [], "sizes": [], "ports": ["Vancouver"], "regions": ["Alaska"], "months": [],
         "dealTypes": [], "sort": "price"}
        """.utf8))
        XCTAssertEqual(old.lines, ["Disney"])
        XCTAssertEqual(old.calls, [])
        XCTAssertEqual(old.sort, "price")

        var q = SearchQuery()
        q.calls = ["Juneau", "Glacier Bay", "juneau"]
        let items = q.queryItems()
        XCTAssertEqual(items.first { $0.name == "calls" }?.value, "Juneau,Glacier Bay")
        XCTAssertTrue(q.summary.contains("visits Juneau or Glacier Bay"))
        XCTAssertNil(SearchQuery().queryItems().first { $0.name == "calls" })
    }

    func testSummariesNameEveryLineNeverPlusN() {
        var q = SearchQuery()
        q.lines = ["Royal Caribbean", "Disney", "Norwegian"]
        XCTAssertTrue(q.summary.hasPrefix("Royal Caribbean, Disney and Norwegian"), q.summary)
        XCTAssertFalse(q.summary.contains("+"))
        var trip = TripPrefs()
        trip.lines = ["Royal Caribbean", "Celebrity", "Disney"]
        XCTAssertEqual(trip.linesSummary, "Royal Caribbean, Celebrity and Disney")
    }

    // MARK: Collection (CONTRACT_V5 section 1.2)

    func testCollectStateWords() throws {
        let state = try JSONDecoder().decode(CollectState.self, from: Data("""
        {"linesState": {"trip": "saved", "effective": ["Royal Caribbean", "Disney"]},
         "lines": [{"line": "Royal Caribbean", "state": "collecting", "why": ["always"], "tier": "daily",
                    "sources": [{"source": "allaboard", "listed": 5000, "collected": 412, "ships": null, "passDays": 1}]},
                   {"line": "Disney", "state": "queued", "why": ["collect"], "sources": [{"source": "allaboard",
                    "listed": 700, "collected": 0, "passDays": 1}], "note": "added 17:20"},
                   {"line": "Cunard", "state": "no_source", "why": []},
                   {"line": "Viking", "state": "parked_somehow"}],
         "generatedAt": "2026-11-27T17:00:00Z"}
        """.utf8))
        XCTAssertEqual(state.linesState?.isLegacyDefault, false)
        XCTAssertEqual(state.line("Royal Caribbean")?.stateText, "collecting · 412 sailings")
        XCTAssertEqual(state.line("Disney")?.stateText, "queued · first results in about 1 day")
        XCTAssertEqual(state.line("Cunard")?.stateText, "no source we read lists this line")
        XCTAssertEqual(state.line("Viking")?.stateText, "parked somehow", "an unknown state is shown as it is")
        XCTAssertEqual(state.line("Disney")?.whyText, "Collect prices for")
    }

    func testCollectPrefsAreCleanedAndNeverOther() {
        let prefs = CollectPrefs(lines: ["Disney", "disney", "Other", "Norwegian Cruise Line"], every: false)
        let clean = prefs.cleaned()
        XCTAssertEqual(clean.lines, ["Disney", "Norwegian"])
        let fields = prefs.fields(stamp: "2026-11-27T00:00:00Z")
        XCTAssertEqual(fields["lines"], .array([.string("Disney"), .string("Norwegian")]))
        XCTAssertEqual(fields["every"], .bool(false))
        XCTAssertTrue(clean.has("disney"))
    }

    // MARK: The sheet (CONTRACT_V5 section 2)

    func testSheetDecodesAndReadsPlainly() throws {
        let sheet = try XCTUnwrap(Samples.sheet)
        XCTAssertEqual(sheet.partyText, "for 2 adults + 1 child")
        XCTAssertEqual(sheet.total?.headline, "$3,716 – $5,040")
        XCTAssertEqual(sheet.firmText, "Cruise, taxes, tips $3,452")
        XCTAssertFalse(sheet.total?.isComplete ?? true, "a partial sum is never complete")
        XCTAssertEqual(sheet.total?.missing.count, 3)
        XCTAssertEqual(sheet.verdict?.word, .yourCall)
        XCTAssertEqual(sheet.cabinTitle, "Balcony · Ocean View Balcony")
        let fare = try XCTUnwrap(sheet.lines.first { $0.key == "fare" })
        XCTAssertEqual(fare.amountText, "$2,552")
        XCTAssertEqual(fare.tag, "read · Example agency")
        let third = try XCTUnwrap(sheet.lines.first { $0.key == "extraGuests" })
        XCTAssertEqual(third.amountText, "up to $1,276")
        XCTAssertEqual(third.tag, "not shown")
        let wifi = try XCTUnwrap(sheet.lines.first { $0.key == "addon:voom" })
        XCTAssertEqual(wifi.amountText, "$264 – $312")
        XCTAssertEqual(sheet.budget?.line, "Cabin only vs your $3,200 budget: $3,119 – $4,395 (at the edge of the budget)")
        XCTAssertEqual(sheet.travel?.modeValue, .fly)
        XCTAssertEqual(sheet.itinerary?.text, "2 sea days · 3 port days")
        XCTAssertEqual(sheet.tripCost.range, "$3,716–5,040")
    }

    func testUnknownVerdictBasisAndModeAreShownNeutrally() throws {
        let raw = JSONValue.object(["sheet": .object([
            "lines": .array([.object(["key": .string("x"), "label": .string("Port fee"), "amount": .int(40),
                                      "basis": .string("guessed")])]),
            "total": .object(["firm": .int(40), "low": .int(40), "high": .int(40), "complete": .bool(true),
                              "notShown": .array([])]),
            "verdict": .object(["label": .string("MAYBE_LATER")]),
            "travel": .object(["mode": .string("teleport")]),
            "cabin": .object(["type": .string("balcony"), "category": .string("Verandah")]),
            "brandNewField": .array([.int(1)]),
        ])])
        let sheet = try XCTUnwrap(DealSheet.from(raw))
        XCTAssertEqual(sheet.verdict?.word, .unknown("MAYBE_LATER"))
        XCTAssertEqual(sheet.verdict?.word.title, "MAYBE LATER")
        XCTAssertEqual(sheet.lines.first?.basisValue, .unknown("guessed"))
        XCTAssertEqual(sheet.lines.first?.tag, "guessed")
        XCTAssertEqual(sheet.travel?.modeValue, .other("teleport"))
        XCTAssertEqual(sheet.total?.headline, "$40")
        XCTAssertTrue(sheet.total?.isComplete ?? false)
        XCTAssertEqual(sheet.cabin, "balcony")
        XCTAssertEqual(sheet.category, "Verandah")
        XCTAssertNil(DealSheet.from(.object(["sheet": .object([:])])), "an empty sheet is no sheet")
        XCTAssertNil(DealSheet.from(.object(["sheet": .string("no")])))
    }

    func testDealAndTrackedReadTheSheetOnTheirOwn() throws {
        var docs = Samples.docsV5
        // An odd sheet never hides the deal.
        let odd = docs["deals"]?["sample-call"]?.data.merging(["sheet": .int(3)]) ?? .null
        docs["deals"]?["sample-call"]?.data = odd
        let fits = try XCTUnwrap(docs["deals"]?["sample-fits"].flatMap { Deal(raw: $0) })
        XCTAssertNotNil(fits.sheet)
        let call = try XCTUnwrap(docs["deals"]?["sample-call"].flatMap { Deal(raw: $0) })
        XCTAssertNil(call.sheet)
        let star = try XCTUnwrap(docs["tracked"]?["trk-sample-star"].flatMap { TrackedSailing(raw: $0) })
        XCTAssertNotNil(star.sheet)
    }

    func testNoLabelAssumesThree() {
        let saved = PartyText.current
        defer { PartyText.current = saved }
        PartyText.current = (adults: 2, children: 0)
        XCTAssertEqual(PartyText.unit, "for 2")
        XCTAssertEqual(PartyText.guests, 2)
        XCTAssertFalse(PartyText.words(adults: 2, children: 0).contains("3"))
        XCTAssertEqual(PartyText.words(adults: 2, children: 1), "2 adults + 1 child")
        XCTAssertEqual(PartyText.words(adults: 1, children: 2), "1 adult + 2 children")
        PartyText.current = nil
        XCTAssertEqual(PartyText.unit, "for the party")
    }

    func testMoneyRanges() {
        XCTAssertEqual(Money.range(5980, 7240), "$5,980 – $7,240")
        XCTAssertEqual(Money.range(5980, 7240, compact: true), "$5,980–7,240")
        XCTAssertEqual(Money.range(336, 336), "$336")
        XCTAssertEqual(Money.range(nil, 1650), "up to $1,650")
        XCTAssertNil(Money.range(nil, nil))
        XCTAssertEqual(AddonPrice.range(18.5, 21), "$18.50 – $21")
    }

    // MARK: Reference (CONTRACT_V5 section 3)

    func testAddonsGuideReadsEveryShape() throws {
        let guide = try XCTUnwrap(Samples.addonsGuide)
        XCTAssertEqual(guide.addons.count, 2)
        XCTAssertEqual(guide.addons.first?.priceText, "$22 – $26 a device a day; $28 – $32 on board")
        XCTAssertEqual(guide.gratuity?.ratesText, "$18.50 standard · $21 suite a person a day")
        XCTAssertEqual(guide.forParty.first?.counted, true)

        // The same entry under `lines`, keyed by the line's name.
        let wrapped = """
        {"lines": {"Royal Caribbean": {"included": ["Main dining"], "addons": []}}, "asOf": "2026-11-27"}
        """
        let fromLines = try XCTUnwrap(AddonsGuide.decodeResponse(Data(wrapped.utf8), line: "Royal Caribbean"))
        XCTAssertEqual(fromLines.included, ["Main dining"])
        XCTAssertEqual(fromLines.asOf, "2026-11-27")
        XCTAssertNil(AddonsGuide.decodeResponse(Data("{}".utf8), line: "Royal Caribbean"))
    }

    func testTripExtrasRoundTripAndAreSentOnlyWhenAsked() throws {
        var draft = TripDraft()
        draft.ship = "Norwegian Aqua"
        draft.sailDate = Fmt.day("2026-11-01")
        draft.extras = [TripExtra(name: "Drinks package", kind: "drinks", how: "promo", liked: true), TripExtra(name: "  ")]
        XCTAssertNil(draft.fields(isNew: true)["extras"], "1.4 servers never see extras")
        let sent = draft.fields(isNew: true, sendExtras: true)["extras"]
        XCTAssertEqual(sent, .array([.object(["name": .string("Drinks package"), "kind": .string("drinks"),
                                              "how": .string("promo"), "liked": .bool(true)])]))
        let back = TripExtra.from(.object(["extras": sent ?? .null]))
        XCTAssertEqual(back.map { $0.name }, ["Drinks package"])
        XCTAssertEqual(back.first?.liked, true)
    }

    func testTripPrefsKeepV5KnobsOutOfMyTripSave() throws {
        let prefs = try XCTUnwrap(JSONValue.object([
            "adults": .int(2), "buyKinds": .array([.string("wifi")]), "groundPorts": .array([.string("Vancouver")]),
            "hotelNightBefore": .bool(false), "budgetBasis": .string("trip"),
        ]).decode(TripPrefs.self))
        XCTAssertEqual(prefs.buyKinds, ["wifi"])
        XCTAssertEqual(prefs.groundPorts, ["Vancouver"])
        XCTAssertEqual(prefs.hotelNightBefore, false)
        XCTAssertEqual(prefs.budgetBasis, "trip")
        let fields = prefs.fields(v3: true, v4: Set(V4Feature.allCases))
        for key in ["buyKinds", "groundPorts", "hotelNightBefore", "budgetBasis"] {
            XCTAssertNil(fields[key], "My Trip's PATCH leaves \(key) alone")
        }
    }

    // MARK: Ship classes, every ship named (Jim: never "+ N more")

    func testClassGroupsNameEveryShipWithAPlainTotal() throws {
        let catalog = Samples.catalogV5
        let breakaway = try XCTUnwrap(catalog.classGroup(line: "Norwegian", ship: "Norwegian Getaway"))
        XCTAssertEqual(breakaway.title, "Breakaway class")
        XCTAssertEqual(breakaway.label, "2 ships in this class: Norwegian Getaway, Norwegian Breakaway")
        XCTAssertEqual(breakaway.countText, "2 ships in this class")
        let groups = catalog.classGroups(line: "Norwegian")
        XCTAssertEqual(groups.map { $0.name }, ["Prima", "Breakaway"])
        for group in catalog.allClassGroups {
            XCTAssertFalse(group.label.contains("more"), group.label)
            XCTAssertFalse(group.label.contains("+"), group.label)
            XCTAssertEqual(group.shipNames.count, group.ships.count)
            XCTAssertTrue(group.label.hasPrefix(group.shipNames.count == 1 ? "1 ship in this class: "
                                                                             : "\(group.shipNames.count) ships in this class: "))
        }
        let icon = try XCTUnwrap(catalog.classGroup(line: "Royal Caribbean", classKey: "icon"))
        XCTAssertEqual(icon.shipNames, ["Icon of the Seas", "Star of the Seas", "Legend of the Seas"])
        XCTAssertNil(catalog.classGroup(line: "Royal Caribbean", classKey: "other"))
    }

    // MARK: Ship photos

    func testShipPhotoManifestShapesAndSafePaths() {
        let flat = ShipPhotoManifest.decode(Data("""
        {"Norwegian|Breakaway": {"file": "norwegian-breakaway.jpg", "shipInPhoto": "Norwegian Getaway",
           "sister": "Norwegian Getaway", "author": "A", "license": "CC BY-SA 4.0",
           "commonsPage": "https://commons.wikimedia.org/wiki/File:X.jpg", "length_ft": 1068},
         "Bad|Path": {"file": "../../etc/passwd"},
         "no-bar": {"file": "x.jpg"},
         "Royal Caribbean|Icon": "not an object"}
        """.utf8))
        XCTAssertEqual(flat.photos.count, 1, "unsafe paths and malformed keys are dropped")
        let photo = flat.photo(line: "Norwegian", className: "Breakaway")
        XCTAssertEqual(photo?.path, "/v1/ships/photo/norwegian-breakaway.jpg")
        XCTAssertEqual(photo?.lengthFt, 1068)
        XCTAssertEqual(photo?.sister, true)
        XCTAssertEqual(photo?.credit, "Norwegian Getaway (a sister ship) by A, CC BY-SA 4.0")

        let wrapped = ShipPhotoManifest.decode(Data("""
        {"photos": {"Norwegian|Prima": {"file": "p.jpg", "url": "/v1/ships/photo/p.jpg"}}}
        """.utf8))
        XCTAssertEqual(wrapped.photo(line: "norwegian", className: "prima")?.path, "/v1/ships/photo/p.jpg")
        XCTAssertTrue(ShipPhotoManifest.decode(Data("[]".utf8)).isEmpty)
        XCTAssertEqual(ShipScale.lengthText(1080), "1,080 ft · 3.0 football fields")
    }

    func testSizeEntriesDrawAtThePhotoShipsLength() throws {
        let catalog = Samples.catalogV5
        let group = try XCTUnwrap(catalog.classGroup(line: "Norwegian", ship: "Norwegian Breakaway"))
        let entry = ShipSizeEntry.make(group, manifest: Samples.shipPhotos)
        XCTAssertEqual(entry.lengthFt, 1068)
        XCTAssertEqual(entry.drawn, "Norwegian Getaway", "the ship in the photo is the one drawn")
        XCTAssertTrue(entry.figure.hasPrefix("1,068 ft · 3.0 football fields"))
    }

    // MARK: Places in the Deals filter

    func testPlacesMatchPortsAndRegionTrees() {
        let catalog = Samples.catalogV5
        XCTAssertTrue(PlaceMatch.matches("Galveston", port: "Galveston", region: nil, catalog: catalog))
        XCTAssertTrue(PlaceMatch.matches("Caribbean", port: "Galveston", region: "Western Caribbean", catalog: catalog))
        XCTAssertTrue(PlaceMatch.matches("Western Caribbean", port: nil, region: "Western Caribbean", catalog: catalog))
        XCTAssertFalse(PlaceMatch.matches("Alaska", port: "Galveston", region: "Western Caribbean", catalog: catalog))
    }
}

@MainActor
final class StoreV5Tests: XCTestCase {
    func testTheDefaultIsVisibleUntilLinesAreSaved() throws {
        let store = Store.previewV5()
        XCTAssertTrue(store.has(.catalog5))
        XCTAssertTrue(store.has(.sheet))
        XCTAssertFalse(store.has(.flights), "flights wait on the provider")
        XCTAssertNil(store.trip?.lines)
        XCTAssertTrue(store.showsDefaultLinesBanner)
        XCTAssertEqual(store.collectPrefs.lines, ["Disney"])

        // On v4 there is no banner and no v5 part.
        let v4 = Store.previewV4()
        XCTAssertFalse(v4.showsDefaultLinesBanner)
        XCTAssertFalse(v4.has(.catalog5))
        XCTAssertFalse(v4.has(.sheet))
    }

    func testPreviewSearchExplainsTheDisneyAlaskaQuestion() async throws {
        let store = Store.previewV5()
        let result = try await store.search(Samples.disneyAlaska)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.hasExplanation)
        XCTAssertEqual(result.coverageGap.first?.action, "open_line")
        XCTAssertTrue(result.whyLines.first?.contains("Disney Magic") ?? false)
    }

    func testV5DealsCarryTheirSheet() throws {
        let store = Store.previewV5()
        let deal = try XCTUnwrap(store.deal("sample-fits"))
        XCTAssertEqual(deal.sheet?.verdict?.word, .yourCall)
        XCTAssertEqual(deal.totalEstimate, 3716, "the trip cost's low end sorts and filters")
        XCTAssertEqual(store.pastTrip("trip-sample-aqua")?.extras.first?.name, "Drinks package")
        XCTAssertEqual(store.yardstick?.name, "Norwegian Aqua")
    }
}
