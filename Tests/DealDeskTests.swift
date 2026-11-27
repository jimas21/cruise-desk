import XCTest
@testable import DealDesk

/// A deal exactly as dealdesk-api stores it (DESIGN.md "deals"), with every field filled.
private let serverDeal = """
{"id": "icon-2028-10-15-7n", "version": 3, "updatedAt": "2026-11-27T10:21:00Z", "data": {
  "kind": "fits", "ship": "Icon of the Seas", "shipClass": "icon", "sailDate": "2028-10-15", "nights": 7,
  "port": "Galveston", "roundTrip": true, "region": "Western Caribbean", "cabin": "balcony",
  "cabinName": "Ocean View Balcony", "oceanViewConfirmed": null, "pricePP": 1138, "priceIncludesTaxes": true,
  "usualPP": 1520, "previousPP": 1187, "lowestSeenPP": 1138, "perNightPP": 163, "totalFor3": 2580,
  "totalAssumes": "3rd guest sails free", "score": 70, "scoreLabel": "Great",
  "why": "Lowest Icon balcony we've seen — $163/night vs $216", "breaks": null, "flight": "~3h nonstop",
  "perks": ["Free 3rd guest", "BOGO60"], "bookBy": "2026-11-29", "bookByWhat": "Black Friday $300 off",
  "link": "https://example.com/sailing", "linkLabel": "Example",
  "sources": [{"name": "Example", "url": "https://example.com/a", "pricePP": 1138, "includesTaxes": true},
              {"name": "Other", "url": "https://example.com/b", "pricePP": null, "includesTaxes": null}],
  "ports": ["Roatán", "Cozumel"], "nearby": null, "scoreHow": "+40 below median", "notes": null,
  "offers": null, "endsAt": null, "postedAt": "2026-11-27T10:21:00Z", "changedAt": "2026-11-27T10:21:00Z",
  "someFutureField": {"nested": [1, 2.5, "x"]}
}}
"""

final class FormatTests: XCTestCase {
    func testMoney() {
        XCTAssertEqual(Fmt.usd(2580), "$2,580")
        XCTAssertEqual(Fmt.usd(163), "$163")
        XCTAssertEqual(Fmt.usd(12450), "$12,450")
    }

    func testDateRanges() throws {
        XCTAssertEqual(Fmt.range(from: try XCTUnwrap(Fmt.day("2028-10-15")), nights: 7), "Oct 15–22, 2028")
        XCTAssertEqual(Fmt.range(from: try XCTUnwrap(Fmt.day("2028-10-29")), nights: 7), "Oct 29 – Nov 5, 2028")
        XCTAssertEqual(Fmt.range(from: try XCTUnwrap(Fmt.day("2027-12-28")), nights: 7), "Dec 28, 2027 – Jan 4, 2028")
        XCTAssertEqual(Fmt.nights(1), "1 night")
        XCTAssertEqual(Fmt.nights(6), "6 nights")
        XCTAssertNil(Fmt.day("soon"))
    }

    func testCountdown() {
        let day: TimeInterval = 86400
        XCTAssertEqual(Fmt.countdown(Date()), "last day")
        XCTAssertEqual(Fmt.countdown(Date().addingTimeInterval(day)), "1 day left")
        XCTAssertEqual(Fmt.countdown(Date().addingTimeInterval(2 * day)), "2 days left")
        XCTAssertEqual(Fmt.countdown(Date().addingTimeInterval(-2 * day)), "ended")
        XCTAssertEqual(Fmt.weekday(Fmt.day("2026-11-29")!), "Sun Nov 29")
    }

    func testTimestamps() {
        XCTAssertNotNil(Fmt.timestamp("2026-11-27T10:21:00Z"))
        XCTAssertNotNil(Fmt.timestamp("2026-11-27T10:21:00.123Z"))
        XCTAssertNil(Fmt.timestamp("yesterday"))
        let stamp = Fmt.stamp(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(stamp, "1970-01-01T00:00:00Z")
    }

    func testOnlyWebLinksOpen() {
        XCTAssertNotNil(Fmt.webURL("https://example.com/deal"))
        XCTAssertNil(Fmt.webURL("javascript:alert(1)"))
        XCTAssertNil(Fmt.webURL("dealdesk://deal/x"))
        XCTAssertNil(Fmt.webURL(nil))
    }
}

final class ModelTests: XCTestCase {
    func testServerDealDecodes() throws {
        let raw = try JSONDecoder().decode(RawDoc.self, from: Data(serverDeal.utf8))
        let deal = try XCTUnwrap(Deal(raw: raw))
        XCTAssertEqual(deal.id, "icon-2028-10-15-7n")
        XCTAssertEqual(deal.version, 3)
        XCTAssertEqual(deal.kind, .fits)
        XCTAssertEqual(deal.tripLine, "7 nights · Oct 15–22, 2028 · Galveston")
        XCTAssertEqual(deal.cabinTitle, "Balcony")
        XCTAssertEqual(deal.dropPP, 49)
        XCTAssertEqual(deal.data.totalFor3, 2580)
        XCTAssertEqual(deal.data.sources?.count, 2)
        XCTAssertNil(deal.data.sources?[1].pricePP)
        XCTAssertNotNil(deal.link)
    }

    func testSpeechReadsTheGlance() throws {
        let raw = try JSONDecoder().decode(RawDoc.self, from: Data(serverDeal.utf8))
        let spoken = Speech.deal(try XCTUnwrap(Deal(raw: raw)), fails: ["4 nights"])
        XCTAssertTrue(spoken.hasPrefix("Icon of the Seas, Icon class."), spoken)
        XCTAssertTrue(spoken.contains("$2,580 for 3"))
        XCTAssertTrue(spoken.contains("Ocean View Balcony, type not confirmed"))
        XCTAssertTrue(spoken.contains("Price 25 percent under typical, $1,520"))
        XCTAssertTrue(spoken.contains("Score 70, Great"))
        XCTAssertTrue(spoken.hasSuffix("Not for your trip: 4 nights"))
    }

    func testSyncResponseDecodes() throws {
        let body = """
        {"serverTime": "2026-11-27T17:12:00Z",
         "docs": {"deals": [\(serverDeal)],
                  "meta": [{"id": "status", "version": 9, "updatedAt": "2026-11-27T17:12:00Z",
                            "data": {"lastRun": "2026-11-27T17:12:00Z", "ok": false, "sourcesWorked": ["A", "B"],
                                     "sourcesFailed": ["C"], "sailingsChecked": 203, "newItems": 0,
                                     "error": "timed out"}}],
                  "feedback": []},
         "deleted": [{"coll": "rules", "id": "old-rule", "deletedAt": "2026-11-27T17:00:00Z"}]}
        """
        let result = try JSONDecoder().decode(SyncResult.self, from: Data(body.utf8))
        XCTAssertEqual(result.serverTime, "2026-11-27T17:12:00Z")
        XCTAssertEqual(result.docs["deals"]?.count, 1)
        XCTAssertEqual(result.deleted?.first?.id, "old-rule")
        let status = try XCTUnwrap(RunStatus(raw: try XCTUnwrap(result.docs["meta"]?.first)))
        XCTAssertTrue(status.failed)
        XCTAssertEqual(status.worked, ["A", "B"])
        XCTAssertEqual(status.data.sailingsChecked, 203)
    }

    func testPlayCatchFieldMaps() throws {
        let raw = RawDoc(id: "p", data: .object(["kind": .string("now"), "title": .string("T"),
                                                 "catch": .string("Non-refundable")]), version: 1, updatedAt: nil)
        let play = try XCTUnwrap(Play(raw: raw))
        XCTAssertTrue(play.isLive)
        XCTAssertEqual(play.data.catchText, "Non-refundable")
    }
}

final class JSONValueTests: XCTestCase {
    func testPatchMergeRemovesNulls() {
        let doc: JSONValue = .object(["verdict": .string("pass"), "claudeReply": .string("ok"), "note": .string("")])
        let merged = doc.merging(["verdict": .string("later"), "claudeReply": .null])
        XCTAssertEqual(merged, .object(["verdict": .string("later"), "note": .string("")]))
    }

    func testIntegersStayIntegers() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["pricePP": .int(1138)]))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"pricePP\":1138}")
        let back = try JSONDecoder().decode(JSONValue.self, from: Data("[1138, 2.5, true, null]".utf8))
        XCTAssertEqual(back, .array([.int(1138), .double(2.5), .bool(true), .null]))
    }

    func testValidationErrorsReadPlainly() {
        let body = Data(#"{"detail": [{"loc": ["body", "data", "why"], "msg": "at most 90 characters"}]}"#.utf8)
        XCTAssertEqual(APIClient.describe(body), "why: at most 90 characters")
        XCTAssertEqual(APIClient.describe(Data(#"{"detail": "not allowed"}"#.utf8)), "not allowed")
        // dealdesk-api's own shapes
        let api = Data(#"{"error": "validation failed", "errors": [{"field": "why", "msg": "at most 90 characters"}]}"#.utf8)
        XCTAssertEqual(APIClient.describe(api), "why: at most 90 characters")
        XCTAssertEqual(APIClient.describe(Data(#"{"error": "the app may only change a rule's status"}"#.utf8)),
                       "the app may only change a rule's status")
    }
}

@MainActor
final class StoreTests: XCTestCase {
    func testAnswerMovesDealToReviewed() throws {
        let store = Store.preview()
        let before = store.inbox.count
        let deal = try XCTUnwrap(store.deal("sample-fits"))
        store.answer(deal, verdict: .pass, reasons: ["price", "dates"], note: "Too long a flight")
        XCTAssertEqual(store.inbox.count, before - 1)
        XCTAssertEqual(store.feedback["sample-fits"]?.verdict, .pass)
        XCTAssertEqual(store.feedback["sample-fits"]?.data.reasons, ["price", "dates"])
        XCTAssertTrue(store.isPending("feedback", "sample-fits"))
        XCTAssertEqual(store.reviewed(.pass).map { $0.id }, ["sample-fits"])
    }

    func testChangingAnAnswerHidesTheOldReplyWithoutTouchingClaudesFields() throws {
        let store = Store.preview()
        XCTAssertNotNil(store.feedback["sample-drop"]?.reply)
        let deal = try XCTUnwrap(store.deal("sample-drop"))
        store.answer(deal, verdict: .later, reasons: [], note: "")
        XCTAssertEqual(store.feedback["sample-drop"]?.verdict, .later)
        XCTAssertNil(store.feedback["sample-drop"]?.reply, "the old reply answered the old answer")
        XCTAssertNotNil(store.feedback["sample-drop"]?.data.claudeReply, "the app never writes Claude's fields")
    }

    func testReplyShowsOnceClaudeHasReadTheAnswer() throws {
        let raw = RawDoc(id: "d", data: .object([
            "dealId": .string("d"), "verdict": .string("pass"), "reasons": .array([]),
            "updatedAt": .string("2026-11-27T10:00:00Z"), "claudeReadAt": .string("2026-11-27T11:00:00Z"),
            "claudeReply": .string("Noted."),
        ]), version: 2, updatedAt: nil)
        XCTAssertEqual(Feedback(raw: raw)?.reply, "Noted.")
    }

    func testRuleLifecycle() throws {
        let store = Store.preview()
        store.addRule(text: "No 4-night sailings", unless: "", fromDeal: "sample-call")
        let rule = try XCTUnwrap(store.rules.first { $0.text == "No 4-night sailings" })
        XCTAssertEqual(rule.status, .active)
        XCTAssertEqual(rule.data.origin, "jim")
        XCTAssertEqual(rule.data.fromDeal, "sample-call")
        XCTAssertTrue(rule.id.hasPrefix("jim-"))
        store.setRule(rule, status: .paused)
        XCTAssertEqual(store.rules.first { $0.id == rule.id }?.status, .paused)
        store.deleteRule(rule)
        XCTAssertNil(store.rules.first { $0.id == rule.id })
    }

    func testPlayNote() {
        let store = Store.preview()
        store.savePlayNote(playId: "sample-standing", status: .question, note: "Does this work after final payment?")
        XCTAssertEqual(store.playNotes["sample-standing"]?.status, .question)
    }

    func testNewIdsFitTheServerPattern() {
        let id = Store.newId(prefix: "jim")
        XCTAssertTrue(Router.isValidId(id))
        XCTAssertLessThanOrEqual(id.count, 80)
    }
}

@MainActor
final class RouterTests: XCTestCase {
    func testDealLinksOpenTheDeal() {
        let router = Router()
        router.tab = .rules
        router.handle(url: URL(string: "dealdesk://deal/icon-2028-10-15-7n")!)
        XCTAssertEqual(router.tab, .deals)
        XCTAssertEqual(router.dealsPath, ["icon-2028-10-15-7n"])
    }

    func testOtherLinksAreIgnored() {
        let router = Router()
        router.handle(url: URL(string: "https://example.com/deal/x")!)
        router.handle(url: URL(string: "dealdesk://deal/Not%20An%20Id")!)
        router.handle(url: URL(string: "dealdesk://rules/x")!)
        XCTAssertEqual(router.dealsPath, [])
    }
}

// MARK: - v2 (DESIGN_V2.md)

/// A deal in the v2 shape the brain writes now (summary sheet fields, the scoop, the trip verdict).
private let serverDealV2 = """
{"id": "icon-2027-09-05-6n", "version": 1, "updatedAt": "2026-11-27T10:21:00Z", "data": {
  "kind": "fits", "ship": "Icon of the Seas", "shipClass": "icon", "sailDate": "2027-09-05", "returnDate": "2027-09-11",
  "nights": 6, "port": "Galveston", "roundTrip": true, "region": "Western Caribbean",
  "stops": ["Cozumel", "Roatán", "Costa Maya"], "cabin": "balcony", "cabinName": "Ocean View Balcony",
  "oceanViewConfirmed": true, "pricePP": 1276, "priceIncludesTaxes": true, "typicalPP": 1560, "lowPP": 1180,
  "highPP": 1940, "pctUnderTypical": 18, "totalFor3": 2650, "score": 78, "scoreLabel": "Great",
  "why": "Lowest Icon balcony we've seen this year", "link": "https://example.com/s", "linkLabel": "Example",
  "cabinOptions": [{"category": "Interior", "type": "interior", "pricePP": 899, "taxesIncluded": true, "source": "Example"},
                   {"category": "Ocean View Balcony", "type": "balcony", "pricePP": 1276, "taxesIncluded": null, "source": null}],
  "itineraryDays": [{"day": 1, "date": "2027-09-05", "port": "Galveston", "arrive": null, "depart": "4:00 PM"},
                    {"day": 2, "date": null, "port": "At sea", "arrive": null, "depart": null},
                    {"day": 7, "date": "2027-09-11", "port": "Galveston", "arrive": "6:00 AM", "depart": null}],
  "scoop": "A six-night trip on the newest ship.", "fitsTrip": true, "failsBecause": [],
  "postedAt": "2026-11-27T10:21:00Z", "changedAt": "2026-11-27T10:21:00Z"
}}
"""

private func decodeDeal(_ json: String) throws -> Deal {
    try XCTUnwrap(Deal(raw: JSONDecoder().decode(RawDoc.self, from: Data(json.utf8))))
}

final class SummarySheetTests: XCTestCase {
    func testV2DealReadsAsTheSummarySheet() throws {
        let deal = try decodeDeal(serverDealV2)
        XCTAssertEqual(deal.datesLine, "Sun Sep 5 – Sat Sep 11, 2027 · 6 nights")
        XCTAssertEqual(deal.route, "Galveston → Cozumel · Roatán · Costa Maya → Galveston")
        XCTAssertEqual(deal.cabinLabel, "Ocean View Balcony")
        XCTAssertEqual(deal.typicalPP, 1560)
        XCTAssertEqual(deal.pctUnder, 18)
        XCTAssertEqual(deal.data.cabinOptions?.count, 2)
        XCTAssertNil(deal.data.cabinOptions?[1].taxesIncluded)
        XCTAssertEqual(deal.data.itineraryDays?.last?.arrive, "6:00 AM")
        XCTAssertEqual(deal.data.scoop, "A six-night trip on the newest ship.")
        let range = try XCTUnwrap(deal.priceRange)
        XCTAssertEqual(range.bounds.lo, 1180)
        XCTAssertEqual(range.bounds.hi, 1940)
        XCTAssertLessThan(range.fraction(1276), range.fraction(1560))
        XCTAssertEqual(UnderTypical.text(pct: deal.pctUnder, typical: deal.typicalPP), "18% under typical ($1,560)")
        XCTAssertTrue(Speech.deal(deal).contains("Price 18 percent under typical"))
        XCTAssertTrue(Speech.deal(deal).contains("Galveston to Cozumel, Roatán, Costa Maya to Galveston"))
    }

    func testV1DealStillRenders() throws {
        let deal = try decodeDeal(serverDeal)
        XCTAssertEqual(deal.typicalPP, 1520, "usualPP stands in for typicalPP")
        XCTAssertEqual(deal.pctUnder, 25)
        XCTAssertEqual(deal.route, "Galveston → Roatán · Cozumel → Galveston", "ports stand in for stops")
        XCTAssertEqual(deal.datesLine, "Sun Oct 15 – Sun Oct 22, 2028 · 7 nights")
        let range = try XCTUnwrap(deal.priceRange)
        XCTAssertEqual(range.low, 1138)
        XCTAssertNil(range.high)
    }

    func testRouteDropsSeaDaysAndRepeatedEnds() {
        var data = DealData()
        data.port = "Galveston"
        data.roundTrip = true
        data.stops = ["Galveston, Texas", "Cozumel", "At Sea", "Galveston"]
        XCTAssertEqual(Deal(id: "x", data: data).route, "Galveston → Cozumel → Galveston")
        data.stops = []
        XCTAssertEqual(Deal(id: "x", data: data).route, "Galveston round trip")
    }

    func testOverTypicalReadsPlainly() {
        XCTAssertEqual(UnderTypical.text(pct: -6, typical: 1000), "6% over typical ($1,000)")
        XCTAssertEqual(UnderTypical.text(pct: 0, typical: nil), "At the typical price")
        XCTAssertNil(UnderTypical.text(pct: nil, typical: 1000))
    }

    func testHistoryDecodes() throws {
        let body = #"{"history": [{"pricePP": 1420, "cabin": "balcony", "source": "aad", "seenAt": "2026-10-01T10:00:00Z"}, {"pricePP": 1276, "cabin": null, "source": null, "seenAt": "2026-11-27T10:00:00Z"}]}"#
        let result = try JSONDecoder().decode(HistoryResult.self, from: Data(body.utf8))
        XCTAssertEqual(result.history.map { $0.pricePP }, [1420, 1276])
        XCTAssertNil(result.history[1].cabin)
        XCTAssertNotNil(result.history[0].seen)
    }
}

final class TripCheckTests: XCTestCase {
    private func sample(_ id: String) throws -> Deal {
        try XCTUnwrap(Samples.deals.first { $0.id == id })
    }

    private func reasons(_ change: (inout DealData) -> Void) -> [String] {
        var data = Samples.fits
        change(&data)
        return TripCheck.evaluate(Deal(id: "t", data: data), Samples.trip).reasons
    }

    func testSampleDealsBucket() throws {
        XCTAssertTrue(TripCheck.evaluate(try sample("sample-fits"), Samples.trip).fits)
        let quantum = TripCheck.evaluate(try sample("sample-quantum"), Samples.trip)
        XCTAssertTrue(quantum.fits)
        XCTAssertEqual(quantum.tradeoff, "Trade-off: over $2,800")
        let call = TripCheck.evaluate(try sample("sample-call"), Samples.trip)
        XCTAssertFalse(call.fits)
        XCTAssertEqual(call.reasons, ["4 nights"])
        XCTAssertFalse(TripCheck.evaluate(try sample("sample-sale"), Samples.trip).fits)
    }

    func testEachRuleSaysWhy() {
        XCTAssertEqual(reasons { _ in }, [])
        XCTAssertEqual(reasons { $0.shipClass = "other" }, ["Smaller ship"])
        XCTAssertEqual(reasons { $0.cabin = "interior"; $0.cabinName = nil }, ["Interior cabin"])
        XCTAssertEqual(reasons { $0.oceanViewConfirmed = false }, ["No ocean view"])
        XCTAssertEqual(reasons { $0.cabinName = "Central Park View Balcony" }, ["Central Park balcony"])
        XCTAssertEqual(reasons { $0.totalFor3 = 3400 }, ["Over $3,200"])
        XCTAssertEqual(reasons { $0.nights = 9 }, ["9 nights"])
        XCTAssertEqual(reasons { $0.ship = "Grandeur of the Seas"; $0.shipClass = nil }, [], "unknown facts never fail")
        XCTAssertEqual(reasons { $0.oceanViewConfirmed = nil }, [], "unconfirmed is shown on the card, not failed")
    }

    func testPortsRegionsDatesAndHolidays() {
        let icon = Deal(id: "t", data: Samples.fits)
        var trip = Samples.trip
        trip.portsExcluded = ["galveston"]
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["Galveston"])
        trip = Samples.trip
        trip.regions = ["Alaska"]
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["Western Caribbean"])
        trip.regions = ["Caribbean"]
        XCTAssertTrue(TripCheck.evaluate(icon, trip).fits)
        trip = Samples.trip
        trip.dateTo = "2027-06-30"
        XCTAssertEqual(TripCheck.evaluate(icon, trip).reasons, ["After Jun 30"])
        trip = Samples.trip
        trip.avoidHolidays = true
        XCTAssertTrue(TripCheck.evaluate(icon, trip).fits)
        var christmas = Samples.fits
        christmas.sailDate = "2027-12-26"
        christmas.returnDate = "2028-01-01"
        XCTAssertEqual(TripCheck.evaluate(Deal(id: "t", data: christmas), trip).reasons, ["Holiday week"])
    }

    func testWithoutSettingsTheBrainsVerdictCounts() throws {
        var data = Samples.call
        data.fitsTrip = false
        data.failsBecause = ["4 nights", "Florida"]
        let fit = TripCheck.verdict(for: Deal(id: "t", data: data), prefs: nil)
        XCTAssertFalse(fit.fits)
        XCTAssertEqual(fit.reasons, ["4 nights", "Florida"])
        XCTAssertTrue(TripCheck.verdict(for: try sample("sample-fits"), prefs: nil).fits)
    }

    func testTripSettingsDecodeWithDefaultsAndSaveTheWholeDocument() throws {
        let raw = JSONValue.object([
            "shipClasses": .array([.string("icon")]), "nightsMin": .int(4), "nightsMax": .int(7),
            "cabinTypes": .array([.string("balcony")]), "adults": .int(2), "children": .int(1),
            "budgetTotal": .int(3000), "tradeoffBudget": .null, "someNewField": .bool(true),
        ])
        let prefs = try XCTUnwrap(raw.decode(TripPrefs.self))
        XCTAssertEqual(prefs.shipClasses, ["icon"])
        XCTAssertEqual(prefs.nightsMax, 7)
        XCTAssertNil(prefs.tradeoffBudget)
        XCTAssertEqual(prefs.mustSeeMinScore, 80)
        let fields = prefs.fields(stamp: "2026-11-27T10:00:00Z")
        // Exactly dealdesk-api's PREFS_TRIP fields (server/api/schema.py), nothing else.
        let server: Set<String> = [
            "shipClasses", "preferredClasses", "excludeShips", "nightsMin", "nightsMax", "nightsPreferredMin",
            "cabinTypes", "requireOceanView", "excludeBalconyTypes", "adults", "children", "childAges", "budgetTotal",
            "tradeoffBudget", "homeAirport", "portsPreferred", "portsExcluded", "regions", "dateFrom", "dateTo",
            "avoidHolidays", "mustSeeMinScore", "alertForMyTrip", "alertMustSee", "quietHoursStart", "quietHoursEnd",
            "notes", "updatedAt",
        ]
        XCTAssertEqual(Set(fields.keys), server)
        XCTAssertEqual(fields["homeAirport"], JSONValue.null, "unset fields go as null so a PATCH removes them")
        XCTAssertEqual(fields["budgetTotal"], JSONValue.int(3000))
        XCTAssertEqual(fields["updatedAt"], JSONValue.string("2026-11-27T10:00:00Z"))
    }

    func testCleanedFitsTheServerCaps() {
        var prefs = TripPrefs()
        prefs.nightsMin = 9
        prefs.nightsMax = 4
        prefs.homeAirport = " atl1x "
        prefs.excludeShips = ["", "  Grandeur  ", "Grandeur"]
        prefs.shipClasses = ["icon", "bogus"]
        prefs.dateFrom = "2027-10-01"
        prefs.dateTo = "2027-03-01"
        prefs.notes = "   "
        prefs.quietHoursStart = "22:00"
        let clean = prefs.cleaned()
        XCTAssertEqual(clean.nightsMin, 4)
        XCTAssertEqual(clean.nightsMax, 9)
        XCTAssertEqual(clean.homeAirport, "ATL1")
        XCTAssertEqual(clean.excludeShips, ["Grandeur"])
        XCTAssertEqual(clean.shipClasses, ["icon"])
        XCTAssertEqual(clean.dateFrom, "2027-03-01")
        XCTAssertEqual(clean.dateTo, "2027-10-01")
        XCTAssertNil(clean.notes)
        XCTAssertEqual(clean.quietHoursStart, "22:00")
    }

    func testSortOrders() {
        let deals = Samples.deals
        XCTAssertEqual(Array(DealOrder.sorted(deals, by: .score).map { $0.id }.prefix(3)),
                       ["sample-sale", "sample-fits", "sample-quantum"])
        XCTAssertEqual(DealOrder.sorted(deals, by: .total).first?.id, "sample-call")
        XCTAssertEqual(DealOrder.sorted(deals, by: .total).last?.id, "sample-sale", "no total sorts last")
        XCTAssertEqual(DealOrder.sorted(deals, by: .under).first?.id, "sample-call")
        XCTAssertEqual(DealOrder.sorted(deals, by: .soonest).first?.id, "sample-call")
        XCTAssertEqual(DealOrder.sorted(deals, by: .newest).first?.id, "sample-sale")
    }

    func testFilters() {
        var filters = DealFilters()
        XCTAssertFalse(filters.isActive)
        filters.shipClasses = ["oasis"]
        XCTAssertEqual(Samples.deals.filter(filters.matches).map { $0.id }, ["sample-call", "sample-drop"])
        XCTAssertEqual(filters.summary, "Oasis")
        filters = DealFilters()
        filters.months = ["2027-09"]
        XCTAssertEqual(Samples.deals.filter(filters.matches).map { $0.id }, ["sample-fits"])
        filters = DealFilters()
        filters.maxTotal = 2000
        XCTAssertEqual(Samples.deals.filter(filters.matches).map { $0.id }, ["sample-call"])
        filters = DealFilters()
        filters.places = ["Galveston"]
        filters.nightsMin = 7
        XCTAssertEqual(Samples.deals.filter(filters.matches).map { $0.id }, ["sample-drop"])
        XCTAssertEqual(filters.activeCount, 2)
        XCTAssertEqual(DealFilters.decode(filters.encoded()), filters)
        XCTAssertEqual(DealFilters.decode("not json"), DealFilters())
    }
}

@MainActor
final class StoreV2Tests: XCTestCase {
    func testBucketsFollowMyTripLive() throws {
        let store = Store.preview()
        XCTAssertEqual(store.bucket(.trip, filters: DealFilters(), sort: .score).map { $0.id },
                       ["sample-fits", "sample-quantum"])
        XCTAssertEqual(store.bucket(.best, filters: DealFilters(), sort: .score).count, 4, "answered deals leave the inbox")
        var relaxed = try XCTUnwrap(store.trip)
        relaxed.nightsMin = 4
        store.saveTrip(relaxed)
        XCTAssertEqual(store.trip?.nightsMin, 4)
        XCTAssertTrue(store.isPending("prefs", "trip"))
        XCTAssertTrue(store.bucket(.trip, filters: DealFilters(), sort: .score).contains { $0.id == "sample-call" })
    }

    func testAskingAddsToTheRightThread() throws {
        let store = Store.preview()
        XCTAssertEqual(store.thread("sample-fits").count, 2)
        XCTAssertTrue(store.awaitingAnswer("sample-fits"))
        XCTAssertFalse(store.awaitingAnswer(nil))
        let id = try XCTUnwrap(store.ask("  Is the drinks package worth it?  ", dealId: "sample-fits"))
        XCTAssertTrue(id.hasPrefix("q-"))
        XCTAssertTrue(Router.isValidId(id))
        XCTAssertEqual(store.thread("sample-fits").last?.text, "Is the drinks package worth it?")
        XCTAssertTrue(store.isPending("questions", id))
        let general = try XCTUnwrap(store.ask("Any Alaska deals?", dealId: nil))
        XCTAssertNil(store.question(general)?.data.dealId, "a general question carries no dealId")
        XCTAssertEqual(store.thread(nil).count, 2)
        XCTAssertNil(store.ask("   ", dealId: nil))
    }

    func testThreadLinksAndAnswerAlerts() {
        let store = Store.preview()
        let router = Router()
        router.handle(url: URL(string: "dealdesk://deal/icon-2027-09-05-6n/ask")!)
        XCTAssertEqual(router.dealsPath, ["icon-2027-09-05-6n"])
        XCTAssertEqual(router.askFocus, "icon-2027-09-05-6n")
        router.handle(url: URL(string: "dealdesk://ask")!)
        XCTAssertTrue(router.showAsk)
        XCTAssertEqual(router.dealsPath, [])
        router.openAnswer("sample-fits", store: store)
        XCTAssertEqual(router.askFocus, "sample-fits")
        XCTAssertFalse(router.showAsk)
        router.openAnswer("q-sample-general", store: store)
        XCTAssertTrue(router.showAsk, "a question id with no deal opens the general thread")
        XCTAssertTrue(Router.isAnswerAlert("Answer ready"))
        XCTAssertTrue(Router.isAnswerAlert("Answer ready: Icon of the Seas"))
        XCTAssertFalse(Router.isAnswerAlert("Icon of the Seas · Oct 15 · $2,580 for 3"))
    }
}
