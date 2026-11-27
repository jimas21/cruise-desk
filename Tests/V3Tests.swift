import XCTest
@testable import DealDesk

// MARK: - v3 (DESIGN_V3.md, CONTRACT_V3.md)

private func decode(_ json: String) throws -> RawDoc {
    try JSONDecoder().decode(RawDoc.self, from: Data(json.utf8))
}

private func deal(_ json: String) throws -> Deal {
    try XCTUnwrap(Deal(raw: decode(json)))
}

private func tracked(_ data: String, id: String = "trk-1") throws -> TrackedSailing {
    try XCTUnwrap(TrackedSailing(raw: decode(#"{"id": "\#(id)", "version": 2, "data": \#(data)}"#)))
}

private func future(_ days: Int) -> String { Samples.isoDay(daysFromNow: days) }

final class LineTests: XCTestCase {
    func testAbsentLineIsRoyalCaribbean() throws {
        let icon = try deal(#"{"id": "icon-2028-10-15-7n", "version": 1, "data": {"kind": "fits", "ship": "Icon of the Seas", "shipClass": "icon", "sailDate": "2028-10-15", "nights": 7}}"#)
        XCTAssertEqual(icon.line, "Royal Caribbean")
        XCTAssertTrue(icon.isRoyal)
        XCTAssertEqual(icon.shipClass, .icon)
        XCTAssertEqual(icon.classTitle, "Icon class")
        XCTAssertEqual(icon.sizeTier, .mega, "the Royal fleet's sizes are built in")
        XCTAssertEqual(icon.eyebrow, "Royal Caribbean · Mega ship")
    }

    func testAnotherLinesDealKeepsItsOwnClassAndSize() throws {
        let beyond = try deal(#"{"id": "celebrity-celebrity-beyond-2027-04-11-7n", "version": 1, "data": {"kind": "fits", "line": "Celebrity", "ship": "Celebrity Beyond", "shipClass": "edge", "shipSize": "large", "sailDate": "2027-04-11", "nights": 7}}"#)
        XCTAssertEqual(beyond.line, "Celebrity")
        XCTAssertFalse(beyond.isRoyal)
        XCTAssertNil(beyond.shipClass, "Royal's class enum never applies to another line")
        XCTAssertEqual(beyond.classTitle, "Edge class")
        XCTAssertEqual(beyond.sizeTier, .large)
        XCTAssertTrue(Speech.deal(beyond).contains("Celebrity, Large ship"))
    }

    func testUnknownSizeIsShownPlainlyAndNeverReplaced() throws {
        let odd = try deal(#"{"id": "x", "version": 1, "data": {"kind": "fits", "ship": "Icon of the Seas", "shipSize": "giant"}}"#)
        XCTAssertNil(odd.sizeTier)
        XCTAssertEqual(odd.sizeTitle, "Giant ship")
    }

    func testSlugsMatchTheServer() {
        XCTAssertEqual(Slug.ship("Royal Caribbean's Icon of the Seas"), "icon-of-the-seas")
        XCTAssertEqual(Slug.ship("Icon of the Seas®"), "icon-of-the-seas")
        XCTAssertEqual(Slug.ship("MSC World América"), "msc-world-america")
        XCTAssertEqual(Slug.ship("Roatán"), "roatan")
        XCTAssertEqual(CruiseLine.slug("Holland America"), "holland-america")
        XCTAssertEqual(CruiseLine.canonical("RCI"), "Royal Caribbean")
        XCTAssertEqual(CruiseLine.canonical("celebrity-cruises"), "Celebrity")
        XCTAssertEqual(CruiseLine.canonical("Norwegian Cruise Line"), "Norwegian")
        XCTAssertEqual(CruiseLine.canonical("royal-caribbean-international"), "Royal Caribbean")
        XCTAssertNil(CruiseLine.canonical("Bogus Line"))
    }

    func testSizeTiersByTonnage() {
        XCTAssertEqual(ShipSize.tier(gt: 69_999), .small)
        XCTAssertEqual(ShipSize.tier(gt: 70_000), .mid)
        XCTAssertEqual(ShipSize.tier(gt: 119_999), .mid)
        XCTAssertEqual(ShipSize.tier(gt: 120_000), .large)
        XCTAssertEqual(ShipSize.tier(gt: 179_999), .large)
        XCTAssertEqual(ShipSize.tier(gt: 180_000), .mega)
        XCTAssertNil(ShipSize.tier(gt: nil))
    }

    func testCatalogDecodesLenientlyAndSwitchesV3On() throws {
        let body = #"""
        {"apiVersion": 3, "catalogVersion": 2, "generatedAt": "2026-11-27T00:00:00Z",
         "sizes": [{"tier": "mega", "label": "Mega", "gtMin": 180000, "gtMax": null}],
         "lines": [{"name": "Royal Caribbean", "slug": "royal-caribbean", "coverage": "tracking_live",
                    "coverageNote": "3 sources live · 412 sailings", "liveSources": ["A"], "sailings": 412,
                    "ships": [{"name": "Icon of the Seas", "slug": "icon-of-the-seas", "class": "Icon", "classSlug": "icon",
                               "size": "mega", "gt": "lots"}]},
                   {"name": "Celebrity", "slug": "celebrity", "coverage": "partial_feed", "ships": []}]}
        """#
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(body.utf8))
        XCTAssertTrue(catalog.isV3)
        XCTAssertEqual(catalog.lineNames, ["Royal Caribbean", "Celebrity"])
        XCTAssertEqual(catalog.line("royal-caribbean")?.coverageState, Coverage.live)
        XCTAssertEqual(catalog.line("Celebrity")?.coverageState, Coverage.unknown("partial_feed"))
        XCTAssertEqual(catalog.line("Celebrity")?.coverageState?.title, "Partial feed", "a new state shows as it is")
        let icon = try XCTUnwrap(catalog.ship(line: nil, named: "Icon of the Seas"))
        XCTAssertNil(icon.gt, "a field of the wrong type is dropped, not the catalog")
        XCTAssertEqual(icon.tier, .mega)
        XCTAssertFalse(Catalog.builtIn.isV3, "the built-in copy never turns v3 on")
        XCTAssertEqual(Catalog.builtIn.size(line: "Royal Caribbean", ship: "Grandeur of the Seas"), .mid)
    }
}

final class TripV3Tests: XCTestCase {
    private var celebrity: Deal { Deal(id: "c", data: Samples.celebrity) }
    private var icon: Deal { Deal(id: "i", data: Samples.fits) }

    func testLinesSizesAndMonthsFilterTheTrip() {
        var trip = Samples.trip
        XCTAssertNil(trip.lines)
        XCTAssertEqual(TripCheck.evaluate(celebrity, trip).reasons, ["Celebrity"], "absent lines = Royal Caribbean only")
        trip.lines = []
        XCTAssertTrue(TripCheck.evaluate(celebrity, trip).fits, "empty lines = every line")
        trip.lines = ["Celebrity"]
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["Royal Caribbean"])
        trip.lines = []
        trip.shipClasses = ["oasis"]
        XCTAssertTrue(TripCheck.evaluate(celebrity, trip).fits, "Royal classes apply to Royal deals only")
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["Icon class"])
        trip = Samples.trip
        trip.lines = []
        trip.shipSizes = ["small"]
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["Mega ship"])
        XCTAssertEqual(TripCheck.evaluate(celebrity, trip).reasons, ["Large ship"])
        var unknown = Samples.fits
        unknown.ship = "Some New Ship"
        unknown.shipClass = nil
        XCTAssertTrue(TripCheck.evaluate(Deal(id: "u", data: unknown), trip).fits, "an unknown size never fails")
        trip = Samples.trip
        trip.sailMonths = [10, 11]
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["Sep sailing"])
        trip.sailMonths = [9]
        XCTAssertTrue(TripCheck.evaluate(icon, trip).fits)
    }

    func testDealTypesAreWorkedOutNeverStored() {
        XCTAssertEqual(DealType.of(icon, fits: false, minPctUnder: 15), [.underTypical])
        XCTAssertEqual(DealType.of(icon, fits: true, minPctUnder: 20), [.fitsTrip])
        let drop = Deal(id: "d", data: Samples.drop)
        XCTAssertTrue(DealType.of(drop, fits: false, minPctUnder: 15).contains(.drop))
        let sale = Deal(id: "s", data: Samples.sale)
        XCTAssertEqual(DealType.of(sale, fits: false, minPctUnder: 15), [.sale])
        var low = Samples.fits
        low.lowestSeenPP = 1276
        XCTAssertTrue(DealType.of(Deal(id: "l", data: low), fits: false, minPctUnder: 15).contains(.newLow))
        XCTAssertTrue(DealType.matches(icon, picked: [], fits: false, minPctUnder: 15), "none picked = every kind")
        XCTAssertFalse(DealType.matches(icon, picked: ["sale", "new_low"], fits: false, minPctUnder: 15))
        XCTAssertTrue(ScoreFloor.passes(sale, 99), "sales are exempt")
        XCTAssertFalse(ScoreFloor.passes(icon, 80))
        XCTAssertTrue(ScoreFloor.passes(icon, 78))
    }

    func testV3SettingsDecodeCleanAndGoOnlyToAV3Server() throws {
        let raw = JSONValue.object([
            "shipClasses": .array([.string("icon")]), "nightsMin": .int(4), "nightsMax": .int(7),
            "cabinTypes": .array([.string("balcony")]), "adults": .int(2), "children": .int(1),
            "budgetTotal": .int(3000), "lines": .array([.string("Royal Caribbean"), .string("Celebrity")]),
            "shipSizes": .array([.string("mega")]), "dealTypes": .array([.string("new_low")]), "minPctUnder": .int(20),
            "minScore": .int(70), "sailMonths": .array([.int(9)]), "refreshMinutes": .int(15),
        ])
        let prefs = try XCTUnwrap(raw.decode(TripPrefs.self))
        XCTAssertEqual(prefs.lines, ["Royal Caribbean", "Celebrity"])
        XCTAssertEqual(prefs.shipSizes, ["mega"])
        XCTAssertEqual(prefs.minScore, 70)
        XCTAssertEqual(prefs.refreshMinutes, 15)
        let legacy = try XCTUnwrap(JSONValue.object(["nightsMin": .int(4)]).decode(TripPrefs.self))
        XCTAssertNil(legacy.lines)
        XCTAssertEqual(legacy.effectiveLines, ["Royal Caribbean"])
        XCTAssertEqual(legacy.minPctUnder, 15)
        XCTAssertEqual(legacy.refreshMinutes, 30)

        let v3Keys: Set<String> = ["lines", "shipSizes", "dealTypes", "minPctUnder", "minScore", "sailMonths", "refreshMinutes"]
        XCTAssertTrue(Set(legacy.fields().keys).isDisjoint(with: v3Keys), "an older server never sees a v3 field")
        let sent = legacy.fields(v3: true)
        XCTAssertTrue(v3Keys.isSubset(of: Set(sent.keys)))
        XCTAssertEqual(sent["lines"], JSONValue.array([JSONValue.string("Royal Caribbean")]), "a v3 app always says which lines")
        XCTAssertEqual(sent["minScore"], JSONValue.null)

        var messy = TripPrefs()
        messy.lines = ["RCI", "Other", "celebrity", "Bogus", "Royal Caribbean"]
        messy.shipSizes = ["mega", "giant"]
        messy.dealTypes = ["sale", "nope"]
        messy.minPctUnder = 120
        messy.minScore = -5
        messy.sailMonths = [13, 9, 9, 1]
        messy.refreshMinutes = 45
        let clean = messy.cleaned()
        XCTAssertEqual(clean.lines, ["Royal Caribbean", "Celebrity"])
        XCTAssertEqual(clean.shipSizes, ["mega"])
        XCTAssertEqual(clean.dealTypes, ["sale"])
        XCTAssertEqual(clean.minPctUnder, 90)
        XCTAssertEqual(clean.minScore, 0)
        XCTAssertEqual(clean.sailMonths, [1, 9])
        XCTAssertEqual(clean.refreshMinutes, 30)
        XCTAssertEqual(clean.linesSummary, "Royal Caribbean & Celebrity")
    }

    func testFiltersByLineSizeKindAndScore() {
        var filters = DealFilters()
        filters.lines = ["Celebrity"]
        XCTAssertEqual(Samples.deals.filter { filters.matches($0) }.map { $0.id }, ["sample-celebrity"])
        filters = DealFilters()
        filters.sizes = ["mega"]
        XCTAssertEqual(Samples.deals.filter { filters.matches($0) }.map { $0.id },
                       ["sample-sale", "sample-fits", "sample-call", "sample-drop"], "a sale's size is unknown, so it stays")
        filters = DealFilters()
        filters.dealTypes = ["drop"]
        XCTAssertEqual(Samples.deals.filter { filters.matches($0) }.map { $0.id }, ["sample-drop"])
        filters = DealFilters()
        filters.minScore = 70
        XCTAssertEqual(Samples.deals.filter { filters.matches($0) }.map { $0.id }, ["sample-sale", "sample-fits"])
        XCTAssertEqual(filters.activeCount, 1)
        let old = DealFilters.decode(#"{"shipClasses": ["icon"], "nightsMin": 5}"#)
        XCTAssertEqual(old.shipClasses, ["icon"], "filters saved by 1.2 still read back")
        XCTAssertEqual(old.nightsMin, 5)
        XCTAssertTrue(old.lines.isEmpty)
    }
}

@MainActor
final class BucketV3Tests: XCTestCase {
    func testDealKindsAndTheLowestScoreShapeTheBuckets() throws {
        let store = Store.preview()
        var prefs = try XCTUnwrap(store.trip)
        prefs.dealTypes = ["sale"]
        store.saveTrip(prefs)
        XCTAssertEqual(store.bucket(.best, filters: DealFilters(), sort: .score).map { $0.id }, ["sample-sale"])
        XCTAssertEqual(store.bucket(.trip, filters: DealFilters(), sort: .score).count, 3, "kinds don't apply to For my trip")
        prefs.dealTypes = []
        prefs.minScore = 60
        store.saveTrip(prefs)
        XCTAssertEqual(store.bucket(.best, filters: DealFilters(), sort: .score).map { $0.id },
                       ["sample-sale", "sample-fits", "sample-quantum", "sample-call"])
        XCTAssertEqual(store.bucket(.trip, filters: DealFilters(), sort: .score).map { $0.id },
                       ["sample-fits", "sample-quantum"])
    }
}

final class TrackedTests: XCTestCase {
    func testEachFillStateSaysWhatIsMissing() throws {
        let day = future(200)
        let pending = try tracked(#"{"line": "Royal Caribbean", "ship": "Star of the Seas", "sailDate": "\#(day)", "nights": 7, "cabin": "balcony", "addedVia": "pick", "addedAt": "\#(Fmt.stamp())"}"#)
        XCTAssertEqual(pending.state, .pending)
        XCTAssertEqual(pending.missing(), "filling…")
        XCTAssertEqual(pending.missing(.enrich), "filling…")

        let stale = Fmt.stamp(Date().addingTimeInterval(-8 * 86400))
        let searching = try tracked(#"{"line": "Royal Caribbean", "ship": "Star of the Seas", "sailDate": "\#(day)", "nights": 7, "cabin": "balcony", "addedAt": "\#(stale)", "fareState": "searching"}"#)
        XCTAssertEqual(searching.missing(), "not found yet")

        let none = try tracked(#"{"line": "Norwegian", "ship": "Norwegian Prima", "sailDate": "\#(day)", "nights": 7, "cabin": "oceanview", "fareState": "no_coverage", "coverage": "news_only"}"#)
        XCTAssertEqual(none.missing(), "no price source for Norwegian yet")
        XCTAssertEqual(none.coverage, .newsOnly)

        let matched = try tracked(#"{"line": "Royal Caribbean", "ship": "Star of the Seas", "sailDate": "\#(day)", "nights": 7, "cabin": "balcony", "fareState": "matched", "pricePP": 1312, "typicalN": 3, "enrichedAt": "\#(Fmt.stamp())"}"#)
        XCTAssertEqual(matched.missing(), "not shown")
        XCTAssertEqual(matched.missing(.typical), "not enough history")
        XCTAssertEqual(matched.missing(.enrich), "not shown")

        let sailed = try tracked(#"{"line": "Royal Caribbean", "ship": "Wonder of the Seas", "sailDate": "\#(future(-3))", "nights": 4, "cabin": "balcony", "fareState": "matched"}"#)
        XCTAssertEqual(sailed.state, .sailed, "a past date reads as sailed")
        XCTAssertEqual(sailed.missing(), "sailed")

        let odd = try tracked(#"{"ship": "Star of the Seas", "sailDate": "\#(day)", "nights": 7, "cabin": "balcony", "fareState": "rechecking", "coverage": "partial_feed", "pricePP": "cheap"}"#)
        XCTAssertEqual(odd.line, "Royal Caribbean")
        XCTAssertEqual(odd.state, .unknown("rechecking"))
        XCTAssertEqual(odd.state.title, "Rechecking")
        XCTAssertEqual(odd.coverage?.title, "Partial feed")
        XCTAssertNil(odd.data.pricePP, "one odd field never hides the sailing")
        XCTAssertEqual(odd.ship, "Star of the Seas")
    }

    func testTheSampleReadsAtAGlance() throws {
        let star = try XCTUnwrap(Samples.tracked.first)
        XCTAssertEqual(star.eyebrow, "Royal Caribbean · Mega ship")
        XCTAssertEqual(star.pickLine, "Balcony · Ocean View Balcony · Port Canaveral")
        XCTAssertEqual(star.route, "Port Canaveral → Perfect Day at CocoCay · Cozumel · Roatán → Port Canaveral")
        XCTAssertEqual(star.historyValues.count, 8)
        XCTAssertEqual(star.historyPoints.first?.seen != nil, true)
        XCTAssertNotNil(star.priceRange)
        let spoken = Speech.tracked(star)
        XCTAssertTrue(spoken.contains("Now $1,312 per person"), spoken)
        XCTAssertTrue(spoken.contains("Typical $1,480"))
        XCTAssertTrue(spoken.contains("Tracking live"))
        let order = Samples.tracked.sorted(by: TrackedSailing.order).map { $0.id }
        XCTAssertEqual(order.last, "trk-sample-sailed", "sailed ones go last")
        XCTAssertEqual(order.first, "trk-sample-star", "soonest first")
    }

    func testAPickIsExactlyTheServersPickFields() throws {
        var pick = TrackPick()
        XCTAssertEqual(pick.problem, "Pick a ship.")
        pick.ship = "Star of the Seas"
        XCTAssertEqual(pick.problem, "Pick the sail date.")
        pick.sailDate = Fmt.day(future(-1))
        XCTAssertEqual(pick.problem, "That sail date has passed.")
        pick.sailDate = Fmt.day(future(300))
        XCTAssertNil(pick.problem)
        pick.link = "http://example.com/x"
        XCTAssertNotNil(pick.problem, "only https links")
        pick.link = "https://example.com/x"
        pick.note = "  "
        let fields = pick.fields(stamp: "2026-11-27T10:00:00Z")
        XCTAssertEqual(Set(fields.keys), ["line", "ship", "sailDate", "nights", "cabin", "addedVia", "addedAt", "link"])
        XCTAssertEqual(fields["line"], JSONValue.string("Royal Caribbean"))
        XCTAssertEqual(fields["addedVia"], JSONValue.string("pick"))
        let same = TrackedSailing(id: "t", data: try XCTUnwrap(JSONValue.object(fields).decode(TrackedData.self)))
        XCTAssertEqual(same.key, pick.key, "the same sailing and cabin is the same key")
    }

    func testLinksAreReadOnThePhone() throws {
        let aad = try XCTUnwrap(LinkPick.read(Samples.sharedLink, catalog: Samples.catalog))
        XCTAssertEqual(aad.line, "Royal Caribbean")
        XCTAssertEqual(aad.ship, "Star of the Seas")
        XCTAssertEqual(aad.sailDate, "2027-06-26")
        XCTAssertEqual(aad.nights, 7)
        XCTAssertEqual(aad.link?.hasPrefix("https://allaboarddeals.com/cruise-lines/"), true)

        let line = try XCTUnwrap(LinkPick.read(
            "https://www.royalcaribbean.com/cruises/itinerary/5-night-western-caribbean?sailDate=2027-03-14&shipCode=OY&packageCode=OY05X123",
            catalog: Samples.catalog))
        XCTAssertEqual(line.line, "Royal Caribbean")
        XCTAssertEqual(line.ship, "Odyssey of the Seas")
        XCTAssertEqual(line.sailDate, "2027-03-14")
        XCTAssertEqual(line.nights, 5)

        let text = try XCTUnwrap(LinkPick.read("Celebrity Beyond, Nov 7, 2027, 7 nights, Veranda", catalog: Samples.catalog))
        XCTAssertEqual(text.line, "Celebrity")
        XCTAssertEqual(text.ship, "Celebrity Beyond")
        XCTAssertEqual(text.sailDate, "2027-11-07")
        XCTAssertNil(text.link)
        XCTAssertNil(LinkPick.read("hello there", catalog: Samples.catalog))
        var pick = TrackPick()
        TrackBuilder.apply(aad, to: &pick)
        XCTAssertEqual(pick.via, "link")
        XCTAssertEqual(pick.ship, "Star of the Seas")
    }
}

@MainActor
final class StoreTrackingTests: XCTestCase {
    private func pick(_ ship: String = "Star of the Seas", days: Int = 400) -> TrackPick {
        var pick = TrackPick()
        pick.ship = ship
        pick.sailDate = Fmt.day(future(days))
        pick.nights = 7
        pick.cabin = .balcony
        return pick
    }

    func testTrackingShowsAtOnceAndNeverDuplicates() throws {
        let store = Store.preview()
        let before = store.tracked.count
        guard case .added(let id) = store.track(pick()) else { return XCTFail("not added") }
        XCTAssertTrue(id.hasPrefix("local-"))
        XCTAssertTrue(Router.isValidId(id))
        let local = try XCTUnwrap(store.trackedSailing(id))
        XCTAssertTrue(local.isLocal)
        XCTAssertEqual(local.missing(), "filling…")
        XCTAssertTrue(store.isPending("tracked", id))
        XCTAssertEqual(store.tracked.count, before + 1)
        XCTAssertEqual(store.track(pick()), .already(id))

        store.editTracked(local, cabinName: "Ocean View Balcony", port: "", link: "", note: "anniversary")
        XCTAssertEqual(store.trackedSailing(id)?.data.note, "anniversary", "a pick not sent yet takes the change")
        XCTAssertEqual(store.trackedSailing(id)?.data.cabinName, "Ocean View Balcony")

        store.stopTracking(try XCTUnwrap(store.trackedSailing(id)))
        XCTAssertNil(store.trackedSailing(id))
        XCTAssertFalse(store.isPending("tracked", id), "a pick never sent is simply dropped")
        XCTAssertEqual(store.tracked.count, before)

        var star = pick()
        star.sailDate = Fmt.day("2027-06-12")
        XCTAssertEqual(store.track(star), .already("trk-sample-star"))

        let server = try XCTUnwrap(store.trackedSailing("trk-sample-prima"))
        store.stopTracking(server)
        XCTAssertNil(store.trackedSailing("trk-sample-prima"))
        XCTAssertTrue(store.isPending("tracked", "trk-sample-prima"), "a delete waits to send")
    }

    func testAnOlderServerGetsNoTrackedWrites() {
        let store = Store(previewDocs: Samples.docs, level: .v2)
        XCTAssertFalse(store.isV3)
        XCTAssertEqual(store.track(pick()), .comingSoon)
        XCTAssertEqual(store.pendingCount, 0)
        var prefs = store.trip ?? TripPrefs()
        prefs.nightsMin = 4
        store.saveTrip(prefs)
        XCTAssertNil(store.trip?.minScore)
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testInvalidAndFullPicksAreRefused() {
        let store = Store.preview()
        var bad = pick()
        bad.ship = ""
        XCTAssertEqual(store.track(bad), .invalid("Pick a ship."))
        var added = 0
        var outcome = TrackOutcome.comingSoon
        for day in 0..<60 {
            outcome = store.track(pick("Utopia of the Seas", days: 30 + day))
            if case .added = outcome { added += 1 }
        }
        XCTAssertEqual(store.tracked.count, Store.trackedLimit)
        XCTAssertEqual(outcome, .full)
        XCTAssertEqual(added, Store.trackedLimit - Samples.tracked.count)
    }

    func testDealDetailKnowsATrackedSailing() throws {
        let store = Store.preview()
        var data = Samples.quantum
        data.ship = "Star of the Seas"
        data.sailDate = "2027-06-12"
        data.nights = 7
        data.cabin = "balcony"
        XCTAssertEqual(store.trackedMatch(for: Deal(id: "x", data: data))?.id, "trk-sample-star")
        XCTAssertNil(store.trackedMatch(for: Deal(id: "y", data: Samples.quantum)))
        let seeded = TrackPick(deal: Deal(id: "z", data: Samples.celebrity))
        XCTAssertEqual(seeded.line, "Celebrity")
        XCTAssertEqual(seeded.cabinName, "Veranda")
        XCTAssertEqual(seeded.link, "https://example.com/beyond")
    }
}

@MainActor
final class RouterV3Tests: XCTestCase {
    func testTrackingLinksAndPushes() {
        let router = Router()
        router.handle(url: URL(string: "dealdesk://tracked/trk-sample-star")!)
        XCTAssertEqual(router.tab, .tracking)
        XCTAssertEqual(router.trackingPath, ["trk-sample-star"])
        router.handle(url: URL(string: "dealdesk://track?link=https%3A%2F%2Fexample.com%2Fs")!)
        XCTAssertEqual(router.trackSeed?.text, "https://example.com/s")
        let store = Store.preview()
        router.trackingPath = []
        router.openPushed("trk-sample-beyond", store: store)
        XCTAssertEqual(router.tab, .tracking)
        XCTAssertEqual(router.trackingPath, ["trk-sample-beyond"])
        router.openPushed("sample-fits", store: store)
        XCTAssertEqual(router.tab, .deals)
        XCTAssertEqual(router.dealsPath, ["sample-fits"])
    }
}
